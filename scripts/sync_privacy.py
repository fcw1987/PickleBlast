#!/usr/bin/env python3
"""Generate the offline Watch policy and website policy from PRIVACY.md (stdlib only)."""
from pathlib import Path
import argparse
import html
import re

ROOT = Path(__file__).resolve().parents[1]
BEGIN = '<!-- BEGIN GENERATED PRIVACY POLICY -->'
END = '<!-- END GENERATED PRIVACY POLICY -->'
LINK = re.compile(r'\[([^\]\n]+)\]\((https://[^\s)]+)\)')


def inline_html(text):
    pieces = []
    cursor = 0
    for match in LINK.finditer(text):
        pieces.append(html.escape(text[cursor:match.start()]))
        pieces.append(f'<a href="{html.escape(match[2], quote=True)}">{html.escape(match[1])}</a>')
        cursor = match.end()
    pieces.append(html.escape(text[cursor:]))
    return ''.join(pieces)


def render(source):
    """The canonical policy uses headings, paragraphs and ordinary HTTPS links."""
    blocks = []
    for block in source.strip().split('\n\n'):
        block = ' '.join(block.splitlines()).strip()
        if not block:
            continue
        if block.startswith('## '):
            tag, content = 'h2', block[3:]
        elif block.startswith('# '):
            tag, content = 'h1', block[2:]
        else:
            tag, content = 'p', block
        if content.startswith(('#', '- ', '* ', '> ')) or '`' in content or '**' in content:
            raise ValueError('Use only H1/H2 headings, paragraphs and HTTPS inline links in PRIVACY.md.')
        if '[' in LINK.sub('', content) or '](' in LINK.sub('', content):
            raise ValueError('Policy links must use [label](https://address) syntax.')
        blocks.append((tag, content))
    if not blocks or sum(tag == 'h1' for tag, _ in blocks) != 1 or blocks[0][0] != 'h1':
        raise ValueError('PRIVACY.md must start with its single H1 title.')
    website = '\n'.join(f'<{tag}>{inline_html(content)}</{tag}>' for tag, content in blocks)
    native = '\n\n'.join(({'h1': '# ', 'h2': '## '}.get(tag, '') +
                             LINK.sub(lambda m: f'{m[1]} ({m[2]})', content)) for tag, content in blocks) + '\n'
    return native, website


def outputs(root):
    native, website = render((root / 'PRIVACY.md').read_text())
    page = root / 'docs/privacy/index.html'
    shell = page.read_text()
    if shell.count(BEGIN) != 1 or shell.count(END) != 1 or shell.index(BEGIN) >= shell.index(END):
        raise ValueError('Privacy HTML shell needs exactly one ordered pair of generated-policy markers.')
    before, rest = shell.split(BEGIN)
    _, after = rest.split(END)
    return {root / 'WatchApp/Policy/Privacy.txt': native,
            page: before + BEGIN + '\n' + website + '\n' + END + after}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Check generated content without writing.')
    args = parser.parse_args()
    try:
        expected = outputs(ROOT)
    except (ValueError, OSError) as error:
        raise SystemExit(f'Privacy sync failed: {error}')
    stale = []
    for path, content in expected.items():
        if args.check:
            if not path.exists() or path.read_text() != content:
                stale.append(path.relative_to(ROOT).as_posix())
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    if stale:
        raise SystemExit('Privacy sync stale: ' + ', '.join(stale) + '; run python3 scripts/sync_privacy.py.')
    print('PASS: canonical, website and bundled offline privacy content match.' if args.check
          else 'Generated website and bundled offline privacy from PRIVACY.md.')


if __name__ == '__main__':
    main()
