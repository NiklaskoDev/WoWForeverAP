"""Parser and renderer for the small Lua subset WoW SavedVariables files use. Pure module.

Parsed values: ``None``, ``bool``, ``int``, ``float``, ``str``, ``list`` and ``dict``. A table whose keys are
exactly 1..n becomes a list, any other non-empty table a dict, and the empty table ``{}`` an empty dict.
Only data is ever parsed: there is no expression evaluation, no function call and no ``require``.
"""
import math
import re
from typing import Any

MAX_DEPTH = 64
MAX_STRING_LENGTH = 200  # render truncates longer strings: they may come from other players

_IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_NUMBER = re.compile(r"0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?")
_LONG_BRACKET_OPEN = re.compile(r"\[(=*)\[")
_SIMPLE_ESCAPES = {"n": 10, "r": 13, "t": 9, "a": 7, "b": 8, "f": 12, "v": 11, "\\": 92, '"': 34, "'": 39, "\n": 10}


class LuaParseError(ValueError):
    """Syntax error in Lua table text, with the 1-based position."""

    def __init__(self, line: int, col: int, message: str):
        super().__init__(f"line {line}, column {col}: {message}")
        self.line = line
        self.col = col
        self.msg = message


class _Parser:
    def __init__(self, text: str):
        self.text = text
        self.pos = 0

    # -- helpers --------------------------------------------------------------------------------

    def error(self, message: str, pos: int | None = None) -> LuaParseError:
        pos = self.pos if pos is None else pos
        line = self.text.count("\n", 0, pos) + 1
        col = pos - (self.text.rfind("\n", 0, pos) + 1) + 1
        return LuaParseError(line, col, message)

    def peek(self) -> str:
        return self.text[self.pos] if self.pos < len(self.text) else ""

    def skip_space(self) -> None:
        text = self.text
        while self.pos < len(text):
            char = text[self.pos]
            if char.isspace():
                self.pos += 1
            elif text.startswith("--", self.pos):
                self._skip_comment()
            else:
                return

    def _skip_comment(self) -> None:
        start = self.pos
        self.pos += 2
        opening = _LONG_BRACKET_OPEN.match(self.text, self.pos)
        if opening:
            closing = "]" + opening.group(1) + "]"
            end = self.text.find(closing, opening.end())
            if end < 0:
                raise self.error("unterminated long comment", start)
            self.pos = end + len(closing)
            return
        end = self.text.find("\n", self.pos)
        self.pos = len(self.text) if end < 0 else end + 1

    def expect(self, char: str) -> None:
        self.skip_space()
        if self.peek() != char:
            raise self.error(f"expected '{char}'")
        self.pos += 1

    # -- grammar --------------------------------------------------------------------------------

    def parse_assignments(self) -> dict[str, Any]:
        result: dict[str, Any] = {}
        while True:
            self.skip_space()
            if self.pos >= len(self.text):
                return result
            if self.peek() == ";":
                self.pos += 1
                continue
            match = _IDENTIFIER.match(self.text, self.pos)
            if not match:
                raise self.error("expected a variable name")
            self.pos = match.end()
            self.expect("=")
            result[match.group()] = self.parse_value(0)

    def parse_value(self, depth: int) -> Any:
        self.skip_space()
        char = self.peek()
        if char == "{":
            return self.parse_table(depth + 1)
        if char in ('"', "'"):
            return self.parse_quoted_string()
        if char == "[":
            return self.parse_long_string()
        if char == "-":
            self.pos += 1
            self.skip_space()
            value = self.parse_number()
            return -value
        if char.isdigit() or char == ".":
            return self.parse_number()
        match = _IDENTIFIER.match(self.text, self.pos)
        if match and match.group() in ("nil", "true", "false"):
            self.pos = match.end()
            return {"nil": None, "true": True, "false": False}[match.group()]
        raise self.error("expected a value")

    def parse_number(self) -> int | float:
        match = _NUMBER.match(self.text, self.pos)
        if not match:
            raise self.error("expected a number")
        self.pos = match.end()
        literal = match.group()
        if literal[:2] in ("0x", "0X"):
            return int(literal, 16)
        if re.fullmatch(r"\d+", literal):
            return int(literal)
        return float(literal)

    def parse_long_string(self) -> str:
        opening = _LONG_BRACKET_OPEN.match(self.text, self.pos)
        if not opening:
            raise self.error("expected a value")
        closing = "]" + opening.group(1) + "]"
        end = self.text.find(closing, opening.end())
        if end < 0:
            raise self.error("unterminated long string")
        body = self.text[opening.end():end]
        self.pos = end + len(closing)
        return body[1:] if body.startswith("\n") else body  # Lua drops the first newline

    def parse_quoted_string(self) -> str:
        quote = self.text[self.pos]
        start = self.pos
        self.pos += 1
        out = bytearray()  # escapes such as \195\164 are bytes of one UTF-8 character
        text = self.text
        while True:
            if self.pos >= len(text) or text[self.pos] == "\n":
                raise self.error("unterminated string", start)
            char = text[self.pos]
            if char == quote:
                self.pos += 1
                return out.decode("utf-8", errors="replace")
            if char == "\\":
                out.extend(self._parse_escape())
            else:
                out.extend(char.encode("utf-8", errors="replace"))
                self.pos += 1

    def _parse_escape(self) -> bytes:
        escape_start = self.pos
        self.pos += 1
        char = self.peek()
        if char in _SIMPLE_ESCAPES:
            self.pos += 1
            return bytes([_SIMPLE_ESCAPES[char]])
        digits = re.compile(r"\d{1,3}").match(self.text, self.pos)
        if digits:
            value = int(digits.group())
            if value > 255:
                raise self.error("decimal escape too large", escape_start)
            self.pos = digits.end()
            return bytes([value])
        raise self.error("invalid escape sequence", escape_start)

    def parse_table(self, depth: int) -> Any:
        if depth > MAX_DEPTH:
            raise self.error(f"tables nested deeper than {MAX_DEPTH}")
        self.pos += 1  # '{'
        entries: dict[Any, Any] = {}
        next_index = 1
        while True:
            self.skip_space()
            char = self.peek()
            if char == "}":
                self.pos += 1
                return _normalise(entries)
            if char == "":
                raise self.error("unterminated table")
            key, value = self._parse_entry(depth, next_index)
            if key == next_index and isinstance(key, int) and not isinstance(key, bool):
                next_index += 1
            entries[key] = value
            self.skip_space()
            if self.peek() in (",", ";"):
                self.pos += 1
            elif self.peek() != "}":
                raise self.error("expected ',' or '}'")

    def _parse_entry(self, depth: int, next_index: int) -> tuple[Any, Any]:
        char = self.peek()
        if char == "[" and not _LONG_BRACKET_OPEN.match(self.text, self.pos):
            self.pos += 1
            key = self.parse_value(depth)
            if key is None or isinstance(key, bool) or (isinstance(key, float) and math.isnan(key)):
                raise self.error("unsupported table key")
            self.expect("]")
            self.expect("=")
            return key, self.parse_value(depth)
        match = _IDENTIFIER.match(self.text, self.pos)
        if match and match.group() not in ("nil", "true", "false"):
            after = match.end()
            probe = _Parser(self.text)
            probe.pos = after
            probe.skip_space()
            if probe.peek() == "=" and not self.text.startswith("==", probe.pos):
                self.pos = probe.pos + 1
                return match.group(), self.parse_value(depth)
        return next_index, self.parse_value(depth)


def _normalise(entries: dict[Any, Any]) -> Any:
    """Turn a table with keys exactly 1..n into a list."""
    if entries and all(key == index for index, key in enumerate(entries, start=1)):
        if all(isinstance(key, int) for key in entries):
            return list(entries.values())
    return entries


def parse_assignments(text: str) -> dict[str, Any]:
    """Parse top-level ``NAME = <value>`` statements; raises ``LuaParseError`` on malformed input."""
    return _Parser(text).parse_assignments()


# --- rendering -------------------------------------------------------------------------------

_ESCAPED = {'"': '\\"', "\\": "\\\\", "\n": "\\n", "\r": "\\r"}


def _escape_string(value: str, max_length: int) -> str:
    out = []
    for char in value[:max_length]:
        if char in _ESCAPED:
            out.append(_ESCAPED[char])
        elif ord(char) < 32 or ord(char) == 127:
            out.append(f"\\{ord(char):03d}")  # three digits: a following digit must not extend the escape
        else:
            out.append(char)
    return '"' + "".join(out) + '"'


def _key_order(key: Any) -> tuple[int, Any]:
    return (0, key) if not isinstance(key, str) else (1, key)


def _render_key(key: Any, max_length: int) -> str:
    if isinstance(key, bool) or key is None:
        raise TypeError(f"unsupported table key {key!r}")
    if isinstance(key, str):
        return f"[{_escape_string(key, max_length)}]"
    if isinstance(key, (int, float)):
        return f"[{_render_number(key)}]"
    raise TypeError(f"unsupported table key type {type(key).__name__}")


def _render_number(value: int | float) -> str:
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError(f"cannot render {value!r}")
        return repr(value)
    return str(value)


def _render_value(value: Any, indent: int, max_length: int, depth: int) -> str:
    if depth > MAX_DEPTH:
        raise ValueError(f"values nested deeper than {MAX_DEPTH}")
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return _render_number(value)
    if isinstance(value, str):
        return _escape_string(value, max_length)
    pad, inner = "\t" * indent, "\t" * (indent + 1)
    if isinstance(value, (list, tuple)):
        lines = [f"{inner}{_render_value(item, indent + 1, max_length, depth + 1)}," for item in value]
    elif isinstance(value, dict):
        lines = [
            f"{inner}{_render_key(key, max_length)} = {_render_value(value[key], indent + 1, max_length, depth + 1)},"
            for key in sorted(value, key=_key_order)
        ]
    else:
        raise TypeError(f"cannot render {type(value).__name__}")
    return "{\n" + "\n".join(lines) + f"\n{pad}}}" if lines else "{}"


def render(name: str, value: Any, max_string_length: int = MAX_STRING_LENGTH) -> str:
    """Render ``NAME = value`` deterministically (sorted keys); every string is escaped and length-capped."""
    if not _IDENTIFIER.fullmatch(name):
        raise ValueError(f"invalid Lua variable name {name!r}")
    return f"{name} = {_render_value(value, 0, max_string_length, 0)}\n"
