#!/usr/bin/env python3
"""Check local Markdown and image links in the public documentation surface."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from html import unescape
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parent.parent
LINK_START = re.compile(r"!?\[([^\]\n]*)\]\(")
FENCE_START = re.compile(r"^ {0,3}(`{3,}|~{3,})")
HTML_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
HTML_TAG = re.compile(r"<[A-Za-z][^>]*>", re.DOTALL)
HTML_ATTRIBUTE = re.compile(r"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))")


@dataclass(frozen=True)
class Link:
    destination: str
    line: int


def documentation_files(root: Path) -> list[Path]:
    """Return only the requested Markdown files, in a stable order."""
    paths = {root / "README.md"}
    paths.update(root.glob("*.md"))
    paths.update(path for path in (root / "docs").rglob("*.md") if "evidence" not in path.relative_to(root / "docs").parts)
    paths.update((root / ".github").rglob("*.md"))
    paths.add(root / "WatchApp" / "Art" / "README.md")
    paths.add(root / "scripts" / "fixtures" / "art_import" / "README.md")
    return sorted(path for path in paths if path.is_file())


def without_fenced_code(text: str) -> str:
    """Blank fenced code blocks while preserving line numbers."""
    output: list[str] = []
    fence_char = ""
    fence_length = 0
    for line in text.splitlines(keepends=True):
        if not fence_char:
            opening = FENCE_START.match(line)
            if opening:
                marker = opening.group(1)
                fence_char, fence_length = marker[0], len(marker)
                output.append("\n" if line.endswith("\n") else "")
                continue
            output.append(line)
            continue

        closing = re.match(r"^ {0,3}(`+|~+)[ \t]*$", line.rstrip("\r\n"))
        if closing and closing.group(1)[0] == fence_char and len(closing.group(1)) >= fence_length:
            fence_char, fence_length = "", 0
        output.append("\n" if line.endswith("\n") else "")
    return "".join(output)


def parse_destination(text: str, start: int) -> tuple[str, int] | None:
    """Read an inline Markdown destination and return it with its end offset."""
    index = start
    while index < len(text) and text[index].isspace():
        index += 1
    if index >= len(text):
        return None

    if text[index] == "<":
        index += 1
        destination: list[str] = []
        while index < len(text):
            char = text[index]
            if char == "\\" and index + 1 < len(text):
                destination.append(text[index + 1])
                index += 2
                continue
            if char == ">":
                return "".join(destination), index + 1
            destination.append(char)
            index += 1
        return None

    destination = []
    paren_depth = 0
    while index < len(text):
        char = text[index]
        if char == "\\" and index + 1 < len(text):
            destination.append(text[index + 1])
            index += 2
            continue
        if char.isspace() and paren_depth == 0:
            break
        if char == ")":
            if paren_depth == 0:
                break
            paren_depth -= 1
            destination.append(char)
            index += 1
            continue
        if char == "(":
            paren_depth += 1
        destination.append(char)
        index += 1
    return "".join(destination), index


def has_link_close(text: str, start: int) -> bool:
    """Accept a closing paren with or without a Markdown title."""
    index = start
    while index < len(text) and text[index].isspace():
        index += 1
    if index < len(text) and text[index] == ")":
        return True
    if index >= len(text):
        return False

    quote = text[index] if text[index] in "\"'" else ""
    parenthesized_title = text[index] == "("
    if not quote and not parenthesized_title:
        return False
    depth = 1 if parenthesized_title else 0
    index += 1
    while index < len(text):
        char = text[index]
        if char == "\\" and index + 1 < len(text):
            index += 2
            continue
        if quote and char == quote:
            index += 1
            break
        if parenthesized_title:
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    index += 1
                    break
        index += 1
    while index < len(text) and text[index].isspace():
        index += 1
    return index < len(text) and text[index] == ")"


def markdown_links(text: str) -> list[Link]:
    """Extract Markdown and HTML links/images, excluding fences and comments."""
    visible = HTML_COMMENT.sub(lambda match: "\n" * match.group(0).count("\n"), without_fenced_code(text))
    links: list[Link] = []
    for match in LINK_START.finditer(visible):
        parsed = parse_destination(visible, match.end())
        if parsed is None:
            continue
        destination, end = parsed
        if has_link_close(visible, end):
            links.append(Link(destination, visible.count("\n", 0, match.start()) + 1))
    for tag in HTML_TAG.finditer(visible):
        for attribute in HTML_ATTRIBUTE.finditer(tag.group(0)):
            if attribute.group(1).lower() not in {"src", "href"}:
                continue
            destination = next((value for value in attribute.groups()[1:] if value is not None), "")
            links.append(Link(unescape(destination), visible.count("\n", 0, tag.start()) + 1))
    return links


def exists_with_exact_case(root: Path, candidate: Path) -> bool:
    """Resolve each path component exactly, even on case-insensitive filesystems."""
    try:
        relative = candidate.relative_to(root)
    except ValueError:
        return False

    current = root
    for component in relative.parts:
        if component in ("", "."):
            continue
        if component == "..":
            current = current.parent
        else:
            if not current.is_dir():
                return False
            child = next((entry for entry in current.iterdir() if entry.name == component), None)
            if child is None:
                return False
            current = child
        try:
            if not current.resolve().is_relative_to(root):
                return False
        except OSError:
            return False
    return current.exists()


def local_target(source: Path, destination: str, root: Path) -> Path | None:
    """Map an internal relative or repository-root path to a local path."""
    value = destination.strip()
    if not value or value.startswith("#"):
        return None

    parsed = urlsplit(value)
    if parsed.scheme or parsed.netloc or not parsed.path:
        return None

    path = Path(unquote(parsed.path))
    candidate = root / path.as_posix().lstrip("/") if path.is_absolute() else source.parent / path
    try:
        resolved_parent = candidate.parent.resolve()
        if not resolved_parent.is_relative_to(root):
            return candidate
    except OSError:
        return candidate
    return candidate


def check(root: Path = ROOT) -> int:
    root = root.resolve()
    broken: list[tuple[Path, Link]] = []
    total = 0
    files = documentation_files(root)
    for source in files:
        for link in markdown_links(source.read_text(encoding="utf-8")):
            target = local_target(source, link.destination, root)
            if target is None:
                continue
            total += 1
            if not exists_with_exact_case(root, target):
                broken.append((source.relative_to(root), link))

    if broken:
        for source, link in broken:
            print(f"{source}:{link.line}: missing local target {link.destination!r}", file=sys.stderr)
        print(f"Found {len(broken)} broken local link(s) among {total} in {len(files)} Markdown files.", file=sys.stderr)
        return 1

    print(f"Checked {total} local link(s) in {len(files)} Markdown files; none are broken.")
    return 0


if __name__ == "__main__":
    raise SystemExit(check())
