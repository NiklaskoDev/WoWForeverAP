import pytest
from att_lua import (
    AttAssign,
    AttCall,
    AttName,
    AttOpaque,
    AttParseError,
    iter_calls,
    parse_chunk,
    parse_file,
)


def only_call(text: str) -> AttCall:
    nodes = parse_chunk(text)
    assert len(nodes) == 1
    assert isinstance(nodes[0], AttCall)
    return nodes[0]


def test_quest_call_keeps_its_id_table_and_name_comment():
    call = only_call("q(783, {\t-- A Threat Within\n\tlvl = 4,\n})")
    assert call == AttCall("q", [783, {"lvl": 4}], 1, "A Threat Within")


def test_comment_is_the_first_one_on_the_line_of_the_call():
    call = only_call("q(1, { lvl = 1, -- first\n -- second\n})  -- trailing")
    assert call.comment == "first"
    assert only_call("q(2, {})\n-- next line").comment is None
    assert only_call("q(3, {})  -- after the call").comment == "after the call"


def test_comment_text_survives_crlf_line_ends():
    assert only_call("q(1, {\t-- Name\r\n})").comment == "Name"


def test_dotted_names_and_identifiers_become_name_nodes():
    call = only_call("q(1, { coord = { 48.1, 42.9, MAP.ELWYNN_FOREST }, races = ALLIANCE_ONLY })")
    table = call.args[1]
    assert table["coord"] == [48.1, 42.9, AttName("MAP.ELWYNN_FOREST")]
    assert table["races"] == AttName("ALLIANCE_ONLY")


def test_lists_of_markers_and_races():
    call = only_call("q(1, { timeline = { TIMELINE.ADDED_1_60_1 }, races = { HUMAN, GNOME } })")
    assert call.args[1]["timeline"] == [AttName("TIMELINE.ADDED_1_60_1")]
    assert call.args[1]["races"] == [AttName("HUMAN"), AttName("GNOME")]


def test_nested_calls_are_found_depth_first_in_order():
    call = only_call(
        "maproot(MAP.A, MAP.B, { groups = { m(MAP.C, { groups = { n(QUESTS, { q(1, {}), q(2, {}) }) } }) } })")
    assert call.args[:2] == [AttName("MAP.A"), AttName("MAP.B")]
    assert [c.args[0] for c in iter_calls(call, "q")] == [1, 2]
    assert [c.name for c in iter_calls(call, "m")] == ["m"]
    assert [c.name for c in iter_calls(call, "maproot")] == ["maproot"]
    assert list(iter_calls(call, "missing")) == []


def test_calls_inside_a_container_table_are_found():
    call = only_call("n(QUESTS, { { allianceQuestData = q(1, {}), hordeQuestData = q(2, {}), lvl = 5 } })")
    assert [c.args[0] for c in iter_calls(call, "q")] == [1, 2]


def test_function_bodies_are_opaque_and_parsing_continues():
    text = """q(1, {
        OnInit = function(t)
            if t.x then return 1 end
            for i = 1, 3 do print("end") end
        end,
        lvl = 7,
    })"""
    call = only_call(text)
    assert isinstance(call.args[1]["OnInit"], AttOpaque)
    assert call.args[1]["lvl"] == 7


def test_statements_that_are_blocks_are_skipped():
    text = """
    local x = 5
    for k, v in pairs({ 1, 2 }) do
        q(99, {})
    end
    if x then q(98, {}) else q(97, {}) end
    while false do end
    repeat x = 1 until x == 1
    do q(96, {}) end
    local function f() return q(95, {}) end
    function g() end
    q(1, {})
    """
    nodes = parse_chunk(text)
    assert [type(node).__name__ for node in nodes] == ["AttAssign", "AttCall"]
    assert nodes[0] == AttAssign(("x",), [5], 2)
    assert nodes[1].args[0] == 1


def test_block_comments_and_long_strings():
    text = "--[[ q(0, {}) ]]\nq(1, { lore = [[a -- not a comment ]] }) --[==[ more ]==]\n"
    call = only_call(text)
    assert call.args[1]["lore"] == "a -- not a comment "
    assert call.comment is None


def test_end_inside_a_string_or_comment_does_not_close_a_block():
    text = 'q(1, { f = function() local s = "end" -- end\n return s end, lvl = 3 })'
    assert only_call(text).args[1]["lvl"] == 3


def test_concatenation_arithmetic_and_unary_operators_are_opaque():
    call = only_call('q(1, { a = "x" .. y, b = 1 + 2, c = -foo, d = not x, e = #t, f = a and b, g = -5 })')
    table = call.args[1]
    for key in "abcdef":
        assert isinstance(table[key], AttOpaque), key
    assert table["g"] == -5


def test_method_calls_index_chains_and_string_arguments():
    nodes = parse_chunk('a.b:c(1)\nf"text"\nt[1](2)\nlocal v = x[1]')
    assert nodes == [AttCall("a.b:c", [1], 1, None), AttCall("f", ["text"], 2, None),
                     AttAssign(("v",), [AttOpaque(4)], 4)]  # the call through an index is not data: no node


def test_assignments_with_several_targets_and_values():
    nodes = parse_chunk("a, b = 1, MAP.X\nExportDB.t.x = { 1 }")
    assert nodes[0] == AttAssign(("a", "b"), [1, AttName("MAP.X")], 1)
    assert nodes[1] == AttAssign(("ExportDB.t.x",), [[1]], 2)


def test_numbers_strings_and_booleans():
    call = only_call(r'f(0x10, -2, 1.5, "a\"b\065", true, false, nil)')
    assert call.args == [16, -2, 1.5, 'a"bA', True, False, None]


def test_input_is_never_executed():
    nodes = parse_chunk("os.exit()\nio.open('x', 'w')")
    assert [node.name for node in nodes] == ["os.exit", "io.open"]
    assert nodes[0].args == []


def test_return_ends_the_chunk():
    assert [node.args[0] for node in parse_chunk("q(1)\nreturn q(2)\nq(3)")] == [1]


@pytest.mark.parametrize("text, line", [
    ("q(1, {\n lvl = 3,\n", 3),
    ("q(1, { lvl = 3 }", 1),
    ('q(1, { a = "open\n })', 1),
    ("q(1\n,,)", 2),
    ("f = function()\n  if x then\n", 3),
    ("x y", 1),
])
def test_malformed_input_raises_with_path_and_line(text, line):
    with pytest.raises(AttParseError) as raised:
        parse_chunk(text, "zones/broken.lua")
    assert raised.value.path == "zones/broken.lua"
    assert raised.value.line == line
    assert str(raised.value).startswith("zones/broken.lua: line ")


def test_deeply_nested_tables_are_rejected():
    with pytest.raises(AttParseError, match="deeper"):
        parse_chunk("q(1, " + "{" * 200 + "})")


def test_parse_file_reads_utf8_with_bom_and_crlf(tmp_path):
    path = tmp_path / "zone.lua"
    path.write_bytes("﻿q(1, {\t-- Café\r\n})\r\n".encode())
    assert parse_file(path)[0].comment == "Café"
