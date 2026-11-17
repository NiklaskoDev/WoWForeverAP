"""Reader for AllTheThings (ATT) database source files. Dev-time only; never shipped with the apworld.

ATT files are Lua code: ``maproot(...)`` / ``q(...)`` calls with identifiers (``MAP.ELWYNN_FOREST``,
``ALLIANCE_ONLY``) and a quest name in a trailing ``-- comment``. They are untrusted input, so this module only
*reads* the syntax: nothing is evaluated, imported or called. What it cannot read as data (``function ... end``
bodies, arithmetic, concatenation) becomes an ``AttOpaque`` node and parsing carries on.

Values: Lua literals become Python values (tables as in ``client.lua_table``), calls ``AttCall``, identifiers
``AttName``. ``parse_chunk`` returns the top-level call and assignment statements; ``iter_calls`` finds nested calls.
"""
import bisect
import re
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from _apworld import apworld_module

lua_table = apworld_module("client.lua_table")

_IDENTIFIER = lua_table._IDENTIFIER
_LONG_BRACKET_OPEN = lua_table._LONG_BRACKET_OPEN
_BLOCK_OPENERS = frozenset({"function", "if", "do", "repeat"})  # for/while open through their "do"
_BLOCK_CLOSERS = frozenset({"end", "until"})
_BLOCK_STATEMENTS = frozenset({"for", "if", "while", "do", "repeat", "function"})
_WORD_OPERATORS = ("and", "or")
_SYMBOL_OPERATORS = ("..", "==", "~=", "<=", ">=", "+", "-", "*", "/", "%", "^", "<", ">")
_COMMENT_START = "--"


class AttParseError(ValueError):
    """Syntax error in an ATT file, with its path and 1-based position."""

    def __init__(self, path: str, line: int, col: int, msg: str):
        super().__init__(f"{path}: line {line}, column {col}: {msg}")
        self.path = path
        self.line = line
        self.col = col
        self.msg = msg


@dataclass
class AttCall:
    """``name(args...)``; ``comment`` is the first ``--`` comment on the line the call starts on."""
    name: str
    args: list
    line: int
    comment: str | None = None


@dataclass(frozen=True)
class AttName:
    dotted: str


@dataclass(frozen=True)
class AttOpaque:
    """An expression that is not plain data (function body, arithmetic, concatenation, ...)."""
    line: int


@dataclass(frozen=True)
class AttAssign:
    """``a, b = x, y`` or ``local a = x``: target names and the values read for them."""
    targets: tuple[str, ...]
    values: list
    line: int


@dataclass
class _Chunk:
    nodes: list = field(default_factory=list)
    calls: list = field(default_factory=list)


class _AttParser(lua_table._Parser):
    def __init__(self, text: str):
        super().__init__(text)
        self._line_starts = [0] + [match.end() for match in re.finditer("\n", text)]
        self._comments: dict[int, str] = {}
        self._calls: list[AttCall] = []

    # -- helpers --------------------------------------------------------------------------------

    def line_of(self, pos: int) -> int:
        return bisect.bisect_right(self._line_starts, pos)

    def _skip_comment(self) -> None:
        start = self.pos
        super()._skip_comment()
        if not _LONG_BRACKET_OPEN.match(self.text, start + len(_COMMENT_START)):
            text = self.text[start + len(_COMMENT_START):self.pos].strip()
            self._comments.setdefault(self.line_of(start), text)

    def _word_at(self) -> str:
        match = _IDENTIFIER.match(self.text, self.pos)
        return match.group() if match else ""

    def _skip_block(self) -> None:
        """Skip a ``function`` / ``if`` / ``for`` ... ``end`` block by keyword balance (strings, comments aware)."""
        depth = 0
        while True:
            self.skip_space()
            char = self.peek()
            if char == "":
                raise self.error("unterminated block")
            if char in ('"', "'"):
                self.parse_quoted_string()
            elif char == "[" and _LONG_BRACKET_OPEN.match(self.text, self.pos):
                self.parse_long_string()
            else:
                word = self._word_at()
                self.pos += len(word) or 1
                if word in _BLOCK_OPENERS:
                    depth += 1
                elif word in _BLOCK_CLOSERS:
                    depth -= 1
                    if depth <= 0:
                        return

    # -- expressions ----------------------------------------------------------------------------

    def parse_value(self, depth: int) -> Any:
        if depth > lua_table.MAX_DEPTH:
            raise self.error(f"values nested deeper than {lua_table.MAX_DEPTH}")
        self.skip_space()
        start = self.pos
        value = self._parse_operand(depth)
        while self._operator_ahead():
            self._skip_operator()
            self._parse_operand(depth)
            value = AttOpaque(self.line_of(start))
        return value

    def _operator_ahead(self) -> bool:
        self.skip_space()
        text, pos = self.text, self.pos
        if text.startswith(_COMMENT_START, pos):
            return False
        word = self._word_at()
        if word in _WORD_OPERATORS:
            return True
        return any(text.startswith(symbol, pos) for symbol in _SYMBOL_OPERATORS)

    def _skip_operator(self) -> None:
        word = self._word_at()
        if word in _WORD_OPERATORS:
            self.pos += len(word)
            return
        self.pos += next(len(symbol) for symbol in _SYMBOL_OPERATORS if self.text.startswith(symbol, self.pos))

    def _parse_operand(self, depth: int) -> Any:
        if depth > lua_table.MAX_DEPTH:  # unary operators recurse without going through parse_value
            raise self.error(f"values nested deeper than {lua_table.MAX_DEPTH}")
        self.skip_space()
        char, start = self.peek(), self.pos
        if char == "-" and not self.text.startswith(_COMMENT_START, start):
            self.pos += 1
            self.skip_space()
            if self.peek().isdigit() or self.peek() == ".":
                return -self.parse_number()
            self._parse_operand(depth + 1)
            return AttOpaque(self.line_of(start))
        if char == "#" or self._word_at() == "not":
            self.pos += 1 if char == "#" else 3
            self._parse_operand(depth + 1)
            return AttOpaque(self.line_of(start))
        if self._word_at() == "function":
            self._skip_block()
            return AttOpaque(self.line_of(start))
        if char == "(":
            self.pos += 1
            inner = self.parse_value(depth + 1)
            self.expect(")")
            return self._parse_suffixes(inner, depth, start)
        if char == "{":
            return self.parse_table(depth + 1)
        if char in ('"', "'"):
            return self.parse_quoted_string()
        if char == "[":
            return self.parse_long_string()
        if char.isdigit() or char == ".":
            return self.parse_number()
        word = self._word_at()
        if word in ("nil", "true", "false"):
            self.pos += len(word)
            return {"nil": None, "true": True, "false": False}[word]
        if not word:
            raise self.error("expected a value")
        self.pos += len(word)
        return self._parse_suffixes(AttName(word), depth, start)

    def _parse_suffixes(self, node: Any, depth: int, start: int) -> Any:
        """Field access, method and function calls after a name or parenthesised expression."""
        line = self.line_of(start)
        while True:
            char = self.peek()  # no skip_space: Lua allows a newline before "(" but ATT never uses it, and a
            if char == ".":     # statement like `a\n(b)` would otherwise be misread
                self.pos += 1
                node = self._extend_name(node, ".", line)
            elif char == ":":
                self.pos += 1
                node = self._extend_name(node, ":", line)
            elif char == "(":
                node = self._parse_call(node, self._parse_call_args(depth), line)
            elif char in ("{", '"', "'"):
                node = self._parse_call(node, [self.parse_value(depth + 1)], line)
            elif char == "[" and not _LONG_BRACKET_OPEN.match(self.text, self.pos):
                self.pos += 1
                self.parse_value(depth + 1)
                self.expect("]")
                node = AttOpaque(line)
            else:
                return node

    def _extend_name(self, node: Any, separator: str, line: int) -> Any:
        word = self._word_at()
        if not word:
            raise self.error("expected a name")
        self.pos += len(word)
        if isinstance(node, AttName):
            return AttName(f"{node.dotted}{separator}{word}")
        return AttOpaque(line)

    def _parse_call_args(self, depth: int) -> list:
        self.pos += 1  # '('
        args = []
        while True:
            self.skip_space()
            if self.peek() == ")":
                self.pos += 1
                return args
            if self.peek() == "":
                raise self.error("unterminated argument list")
            args.append(self.parse_value(depth + 1))
            self.skip_space()
            if self.peek() == ",":
                self.pos += 1
            elif self.peek() != ")":
                raise self.error("expected ',' or ')'")

    def _parse_call(self, callee: Any, args: list, line: int) -> Any:
        if not isinstance(callee, AttName):
            return AttOpaque(line)
        call = AttCall(callee.dotted, args, line)
        self._calls.append(call)
        return call

    # -- statements -----------------------------------------------------------------------------

    def parse_chunk(self) -> list:
        nodes: list = []
        while True:
            self.skip_space()
            if self.pos >= len(self.text):
                break
            if self.peek() == ";":
                self.pos += 1
                continue
            if not self._parse_statement(nodes):
                break
        for call in self._calls:
            call.comment = self._comments.get(call.line)
        return nodes

    def _parse_statement(self, nodes: list) -> bool:
        """Parse one statement into ``nodes``; False once a ``return`` ended the chunk."""
        word = self._word_at()
        if word == "return":
            return False
        if word == "local":
            self.pos += len(word)
            self.skip_space()
            if self._word_at() == "function":
                self._skip_block()
            else:
                self._parse_assignment(nodes, declaration=True)
        elif word in _BLOCK_STATEMENTS:
            self._skip_block()
            if word == "repeat":
                self.parse_value(0)  # the "until" condition
        else:
            self._parse_assignment(nodes)
        return True

    def _parse_assignment(self, nodes: list, declaration: bool = False) -> None:
        start = self.pos
        line = self.line_of(start)
        targets, last = [], None
        while True:
            self.skip_space()
            last = self._parse_operand(0)
            targets.append(last)
            self.skip_space()
            if self.peek() == "," and not self.text.startswith(",,", self.pos):
                self.pos += 1
                continue
            break
        if self.peek() == "=" and not self.text.startswith("==", self.pos):
            self.pos += 1
            values = [self.parse_value(0)]
            self.skip_space()
            while self.peek() == ",":
                self.pos += 1
                values.append(self.parse_value(0))
                self.skip_space()
            names = tuple(target.dotted if isinstance(target, AttName) else "?" for target in targets)
            nodes.append(AttAssign(names, values, line))
        elif len(targets) == 1 and isinstance(last, AttCall):
            nodes.append(last)
        elif not (declaration or (len(targets) == 1 and isinstance(last, AttOpaque))):
            raise self.error("expected a statement", start)


def parse_chunk(text: str, path: str = "<string>") -> list:
    """Top-level call and assignment statements of ``text``, in order; raises ``AttParseError``."""
    try:
        return _AttParser(text).parse_chunk()
    except lua_table.LuaParseError as error:
        raise AttParseError(path, error.line, error.col, error.msg) from None


def parse_file(path: Path) -> list:
    return parse_chunk(path.read_text(encoding="utf-8-sig"), str(path))


def iter_calls(node: Any, name: str) -> Iterator[AttCall]:
    """Every call to ``name`` in ``node``, depth-first (a call comes before the calls in its own arguments)."""
    if isinstance(node, AttCall):
        if node.name == name:
            yield node
        children: Any = node.args
    elif isinstance(node, AttAssign):
        children = node.values
    elif isinstance(node, dict):
        children = node.values()
    elif isinstance(node, list):
        children = node
    else:
        return
    for child in children:
        yield from iter_calls(child, name)
