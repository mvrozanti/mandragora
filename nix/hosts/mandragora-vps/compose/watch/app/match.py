import re

OPERATORS = {"AND", "OR", "NOT"}
_TOKEN_RE = re.compile(r'"[^"]*"|\(|\)|[^\s()]+')


class MatchError(ValueError):
    pass


def tokenize(expr: str) -> list[str]:
    return [t for t in _TOKEN_RE.findall(expr or "") if t.strip()]


def _term_pattern(term: str) -> re.Pattern:
    body = term[1:-1] if len(term) >= 2 and term.startswith('"') and term.endswith('"') else term
    body = body.strip()
    if not body:
        raise MatchError("empty term")
    parts = [re.escape(p) for p in body.split()]
    return re.compile(r"\b" + r"\s+".join(parts) + r"\b", re.IGNORECASE)


class Parser:
    def __init__(self, tokens: list[str]) -> None:
        self.tokens = tokens
        self.pos = 0

    def peek(self) -> str | None:
        return self.tokens[self.pos] if self.pos < len(self.tokens) else None

    def next(self) -> str:
        tok = self.peek()
        if tok is None:
            raise MatchError("unexpected end of expression")
        self.pos += 1
        return tok

    def parse(self):
        node = self.parse_or()
        if self.peek() is not None:
            raise MatchError(f"unexpected {self.peek()!r}")
        return node

    def parse_or(self):
        node = self.parse_and()
        while self.peek() == "OR":
            self.next()
            node = ("or", node, self.parse_and())
        return node

    def parse_and(self):
        node = self.parse_not()
        while True:
            tok = self.peek()
            if tok is None or tok == ")" or tok == "OR":
                return node
            if tok == "AND":
                self.next()
            node = ("and", node, self.parse_not())

    def parse_not(self):
        if self.peek() == "NOT":
            self.next()
            return ("not", self.parse_not())
        return self.parse_atom()

    def parse_atom(self):
        tok = self.next()
        if tok == "(":
            node = self.parse_or()
            if self.next() != ")":
                raise MatchError("unbalanced parenthesis")
            return node
        if tok in OPERATORS or tok == ")":
            raise MatchError(f"unexpected {tok!r}")
        return ("term", _term_pattern(tok), tok)


def parse(expr: str):
    tokens = tokenize(expr)
    if not tokens:
        raise MatchError("empty expression")
    return Parser(tokens).parse()


def evaluate(node, haystack: str) -> bool:
    kind = node[0]
    if kind == "term":
        return node[1].search(haystack) is not None
    if kind == "and":
        return evaluate(node[1], haystack) and evaluate(node[2], haystack)
    if kind == "or":
        return evaluate(node[1], haystack) or evaluate(node[2], haystack)
    if kind == "not":
        return not evaluate(node[1], haystack)
    raise MatchError(f"bad node {kind!r}")


def is_valid(expr: str) -> tuple[bool, str]:
    try:
        parse(expr)
    except MatchError as exc:
        return False, str(exc)
    except re.error as exc:
        return False, f"bad term: {exc}"
    return True, ""


def haystack(*texts: str) -> str:
    return " ".join(t for t in texts if t)


def matches(expr: str, *texts: str) -> bool:
    if not (expr or "").strip():
        return True
    return evaluate(parse(expr), haystack(*texts))


def unmatched_terms(node, haystack_text: str) -> list[str]:
    kind = node[0]
    if kind == "term":
        return [] if node[1].search(haystack_text) else [node[2]]
    if kind in ("and", "or"):
        return unmatched_terms(node[1], haystack_text) + unmatched_terms(node[2], haystack_text)
    if kind == "not":
        return []
    return []


def explain(expr: str, *texts: str) -> str:
    if not (expr or "").strip():
        return "no rule — everything from this source counts"
    hay = haystack(*texts)
    node = parse(expr)
    if evaluate(node, hay):
        return "matched"
    missing = unmatched_terms(node, hay)
    if missing:
        return "not found in the text: " + ", ".join(dict.fromkeys(missing))
    return "rule not satisfied"


def from_must_mention(must_mention: str | None) -> str:
    terms = [t.strip() for t in re.split(r"[,\s]+", str(must_mention or "")) if t.strip()]
    return " AND ".join(terms)
