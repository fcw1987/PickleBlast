#!/usr/bin/env python3
"""Choose lightweight documentation checks; unknown or unavailable diffs run full CI."""
from pathlib import Path, PurePosixPath
import argparse
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SHA = re.compile(r'[0-9a-fA-F]{40}')
DOC_SUFFIXES = {'.md', '.html', '.css', '.png', '.jpg', '.jpeg', '.svg', '.webp', '.gif', '.json', '.txt'}


def docs_only(paths):
    if not paths:
        return False
    for path in paths:
        parts = PurePosixPath(path).parts
        if not parts or path.startswith('/') or '..' in parts or path == 'PRIVACY.md':
            return False
        if path.startswith('docs/') and PurePosixPath(path).suffix in DOC_SUFFIXES:
            continue
        if len(parts) == 1 and path.endswith('.md'):
            continue
        if path.startswith('.github/') and path.endswith('.md'):
            continue
        return False
    return True


def route(event, base, head, root=ROOT):
    if event == 'workflow_dispatch':
        return True, 'Manual request always runs full Watch validation.'
    if event not in {'push', 'pull_request'}:
        return True, 'Unknown event; run full validation.'
    if not all(SHA.fullmatch(sha or '') and int(sha, 16) for sha in (base, head)):
        return True, 'Missing or initial-push comparison; run full validation.'
    try:
        # Fetch only a missing comparison commit. Missing ancestry on a shallow PR
        # checkout also fails closed to full validation rather than guessing.
        for sha in (base, head):
            exists = subprocess.run(['git', 'cat-file', '-e', sha + '^{commit}'], cwd=root,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if exists.returncode:
                subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', sha],
                               cwd=root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        comparison = base
        if event == 'pull_request':
            comparison = subprocess.check_output(['git', 'merge-base', base, head], cwd=root,
                                                 stderr=subprocess.DEVNULL).decode().strip()
        # No rename detection: inspect both deleted and added paths. A source file
        # moved into docs must still take the full route. NUL preserves odd names.
        changed = subprocess.check_output(['git', 'diff', '--no-renames', '--name-only', '-z',
                                           comparison, head, '--'], cwd=root, stderr=subprocess.DEVNULL)
        paths = [path.decode('utf-8', errors='surrogateescape') for path in changed.split(b'\0') if path]
    except (OSError, subprocess.CalledProcessError):
        return True, 'Comparison unavailable; run full validation.'
    if docs_only(paths):
        return False, 'Only documentation/site paths changed.'
    return True, 'App, policy, tooling, CI, unknown paths, or an empty diff require full validation.'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--github-output', type=Path)
    args = parser.parse_args()
    full, reason = route(os.environ.get('CI_EVENT_NAME', ''),
                         os.environ.get('CI_BASE_SHA', ''), os.environ.get('CI_HEAD_SHA', ''))
    print(('Full Watch validation: ' if full else 'Lightweight documentation validation: ') + reason)
    if args.github_output:
        with args.github_output.open('a') as output:
            output.write(f'full={str(full).lower()}\n')


if __name__ == '__main__':
    main()
