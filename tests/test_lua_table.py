from pathlib import Path

import pytest
from worlds.wow_forever.client import lua_table
from worlds.wow_forever.client.lua_table import LuaParseError, parse_assignments, render

FIXTURES = Path(__file__).parent / "fixtures"
HOSTILE = '"]] end os.exit() -- \n\r\0\x01\x1f\x7f \\ \\" \' ]==] }, ["x"] = {'


def parse_fixture(name: str) -> dict:
    return parse_assignments((FIXTURES / name).read_text(encoding="utf-8"))


def test_parses_a_real_looking_saved_variables_file():
    db = parse_fixture("WoWForeverAP_two_chars.lua")["WoWForeverAP_DB"]
    character = db["characters"]["Player-1234-0A1B2C3D"]
    assert character["name"] == "Arthas Menethil"
    assert character["skillAtLink"] == {171: 0, 186: 12}
    assert character["slotKey"] == 'AP_1234:Wow"Slot'
    outbox = db["slots"]['AP_1234:Wow"Slot']["outbox"]
    assert [entry["id"] for entry in outbox] == [5110000783, 5120000002]  # positional entries become a list
    assert db["slots"]['AP_1234:Wow"Slot']["goal"]["t"] == 1763390000


def test_parses_numbers_strings_and_comments():
    db = parse_fixture("WoWForeverAP_two_chars.lua")["WoWForeverAP_DB"]
    assert db["ratio"] == -0.5
    assert db["big"] == 31
    assert db["exp"] == 1500.0
    assert db["note"] == 'long\nstring with "quotes" and \\ backslash'  # first newline of a long string is dropped
    assert db["levelled"] == "contains ]] inside"
    assert db["escapes"] == 'tab\there\ncarriage\rzero\x00 ä \\ "'
    assert db["characters"]["Player-1234-0A1B2C3E"]["name"] == "Jaina Prächtig"
    assert db["characters"]["Player-1234-0A1B2C3E"]["slotKey"] is None


def test_scalar_literals_and_multiple_assignments():
    parsed = parse_assignments("A = nil\nB = true; C = false\n-- comment\nD = 'single'\nE = -3\nF = {}\nG = .5")
    assert parsed == {"A": None, "B": True, "C": False, "D": "single", "E": -3, "F": {}, "G": 0.5}


def test_table_forms_and_separators():
    parsed = parse_assignments('T = { 1, 2; 3, name = "x", [10] = "ten", nested = { { a = 1 }, { a = 2 }, }, }')
    table = parsed["T"]
    assert isinstance(table, dict)  # positional and named entries mixed: stays a dict
    assert table["name"] == "x"
    assert table[10] == "ten"
    assert table["nested"] == [{"a": 1}, {"a": 2}]
    assert (table[1], table[2], table[3]) == (1, 2, 3)


def test_utf8_escape_bytes_form_one_character():
    assert parse_assignments('S = "\\195\\164\\226\\130\\172"')["S"] == "ä€"


@pytest.mark.parametrize("text, line, fragment", [
    ('A = {', 1, "unterminated table"),
    ('A = "open', 1, "unterminated string"),
    ('\n\nA = ', 3, "expected a value"),
    ('A = [[never closed', 1, "unterminated long string"),
    ('A = 1 B', 1, "expected '='"),
    ('A = { 1 2 }', 1, "expected ',' or '}'"),
    ('A = "bad \\q escape"', 1, "invalid escape"),
    ('A = "big \\300"', 1, "decimal escape too large"),
    ('A = f()', 1, "expected a value"),
    ('A = 1 + 2', 1, "expected a variable name"),
    ('A = {\n\n  [nil] = 1 }', 3, "unsupported table key"),
    ('--[[ never closed\nA = 1', 1, "unterminated long comment"),
    ('A = 1\nB = {\n  name = os.exit() }', 3, "expected a value"),
])
def test_malformed_input_raises_with_line(text, line, fragment):
    with pytest.raises(LuaParseError) as error:
        parse_assignments(text)
    assert error.value.line == line
    assert fragment in error.value.msg
    assert f"line {line}" in str(error.value)


def test_truncated_fixture_is_a_parse_error():
    with pytest.raises(LuaParseError):
        parse_fixture("WoWForeverAP_broken.lua")


def test_excessive_nesting_is_rejected_instead_of_crashing():
    with pytest.raises(LuaParseError, match="nested deeper"):
        parse_assignments("A = " + "{" * 200 + "}" * 200)


# --- render --------------------------------------------------------------------------------

def test_render_then_parse_round_trips():
    value = {
        "schema": 1, "written": 1763380000, "ratio": 0.25, "flag": True, "off": False,
        "slots": {"seed:slot": {"locations": {5110000783: True, 5110000007: True}, "items": [
            {"id": 5110001429, "sender": "Aly", "loc": 5110000783}, {"id": 5110001430, "sender": "Bob", "loc": 1}]}},
        "text": 'quote " backslash \\ newline \n tab \t ä',
        "empty": {},
        5: "int key",
    }
    assert parse_assignments(render("WoWForeverAP_Inbox", value))["WoWForeverAP_Inbox"] == value


def test_render_is_deterministic_and_sorted():
    first = render("X", {"b": 1, "a": 2, 3: 4, 1: 5})
    second = render("X", {1: 5, 3: 4, "a": 2, "b": 1})
    assert first == second
    assert first.index("[1]") < first.index("[3]") < first.index('["a"]') < first.index('["b"]')


def test_render_format():
    assert render("A", {"k": [1, "x"]}) == 'A = {\n\t["k"] = {\n\t\t1,\n\t\t"x",\n\t},\n}\n'


def test_hostile_string_renders_as_one_inert_literal():
    rendered = render("Data", {"name": HOSTILE})
    parsed = parse_assignments(rendered)
    assert parsed == {"Data": {"name": HOSTILE}}  # exactly one assignment, the string survives byte for byte
    assert len(rendered.splitlines()) == 3  # header, one entry line, closing brace: no raw newline leaked
    entry = rendered.splitlines()[1]
    assert "\r" not in rendered and "\x00" not in rendered
    assert entry.startswith('\t["name"] = "') and entry.endswith('",')


def test_hostile_keys_are_escaped_too():
    parsed = parse_assignments(render("Data", {HOSTILE: 1}))
    assert parsed == {"Data": {HOSTILE: 1}}


def test_control_characters_use_three_digit_escapes():
    assert "\\000" in render("A", {"s": "\x001"})
    assert parse_assignments(render("A", {"s": "\x001"}))["A"]["s"] == "\x001"


def test_strings_from_players_are_length_capped():
    parsed = parse_assignments(render("A", {"sender": "x" * 1000}))["A"]
    assert parsed["sender"] == "x" * lua_table.MAX_STRING_LENGTH
    assert parse_assignments(render("A", {"s": "abcdef"}, max_string_length=3))["A"]["s"] == "abc"


def test_render_rejects_bad_names_types_and_numbers():
    with pytest.raises(ValueError):
        render("not valid", 1)
    with pytest.raises(TypeError):
        render("A", {"s": object()})
    with pytest.raises(TypeError):
        render("A", {True: 1})
    with pytest.raises(ValueError):
        render("A", float("inf"))


def test_render_of_deep_value_is_rejected():
    value: dict = {}
    for _ in range(100):
        value = {"x": value}
    with pytest.raises(ValueError, match="nested deeper"):
        render("A", value)
