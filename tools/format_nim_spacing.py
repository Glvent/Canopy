#!/usr/bin/env python3
"""Apply vertical spacing and whitespace cleanup to Nim sources."""

from __future__ import annotations

import sys
from pathlib import Path


def is_top_level(line: str) -> bool:
    return bool(line.strip()) and line[0] not in " \t"


def is_import_line(line: str) -> bool:
    stripped = line.strip()
    return stripped.startswith(("import ", "from ", "export ", "include "))


def is_doc_comment(line: str) -> bool:
    return line.strip().startswith("##")


def decl_kind(line: str) -> str | None:
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        return None
    for keyword in (
        "type",
        "const",
        "var",
        "let",
        "proc",
        "func",
        "iterator",
        "template",
        "macro",
        "method",
        "converter",
        "when",
        "static",
    ):
        if (
            stripped == keyword
            or stripped.startswith(keyword + " ")
            or stripped.startswith(keyword + "*")
            or stripped.startswith(keyword + "`")
        ):
            return keyword
    return None


def import_group_key(line: str) -> str:
    stripped = line.strip()
    if stripped.startswith(("import std", "from std")):
        return "std"
    if is_import_line(line):
        return "local"
    return "other"


def is_multiline_decl(lines: list[str], start: int) -> bool:
    first = lines[start]
    if "=" in first:
        rhs = first.split("=", 1)[1].strip()
        if rhs and not first.strip().endswith("="):
            return False
    i = start + 1
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        if is_top_level(line):
            return False
        return True
    return False


def format_nim(content: str) -> str:
    lines = [line.rstrip() for line in content.splitlines()]
    out: list[str] = []
    in_import_block = False
    prev_group: str | None = None
    prev_decl: str | None = None
    prev_multiline = False

    for index, line in enumerate(lines):
        stripped = line.strip()
        if not stripped:
            if out and out[-1] != "":
                out.append("")
            continue

        kind = decl_kind(line) if is_top_level(line) else None

        if is_top_level(line) and is_import_line(line):
            group = import_group_key(line)
            if (
                out
                and out[-1] != ""
                and prev_group
                and group != prev_group
                and in_import_block
            ):
                out.append("")
            in_import_block = True
            prev_group = group
            prev_decl = None
            prev_multiline = False
            out.append(line)
            continue
        elif is_top_level(line) and kind:
            if in_import_block and out and out[-1] != "":
                out.append("")
            in_import_block = False
            prev_group = None

            if out and out[-1] != "":
                prev = out[-1].strip()
                if is_doc_comment(stripped) or is_doc_comment(prev):
                    pass
                elif prev_decl in {"type", "const", "var", "let"} and kind in {
                    "proc",
                    "func",
                    "iterator",
                    "template",
                    "method",
                }:
                    out.append("")
                elif prev_multiline and kind in {
                    "proc",
                    "func",
                    "iterator",
                    "template",
                    "method",
                    "type",
                    "const",
                    "var",
                    "let",
                }:
                    out.append("")

            out.append(line)
            prev_decl = kind
            prev_multiline = is_multiline_decl(lines, index)
        else:
            in_import_block = False
            prev_group = None
            out.append(line)

    collapsed: list[str] = []
    for line in out:
        if line == "" and collapsed and collapsed[-1] == "":
            continue
        collapsed.append(line)

    while collapsed and collapsed[-1] == "":
        collapsed.pop()
    return "\n".join(collapsed) + "\n"


def main(argv: list[str]) -> int:
    paths = [Path(arg) for arg in argv[1:]]
    changed = 0
    for path in paths:
        original = path.read_text(encoding="utf-8")
        formatted = format_nim(original)
        if formatted != original:
            path.write_text(formatted, encoding="utf-8")
            changed += 1
    print(f"formatted {changed}/{len(paths)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
