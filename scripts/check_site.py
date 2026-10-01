#!/usr/bin/env python3
"""Validate the static project site, store drafts, and curated capture provenance."""
from __future__ import annotations
import hashlib
import json
import re
import struct
import sys
import zlib
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit
import sync_privacy

ROOT = Path(__file__).resolve().parents[1]
BASE = 'https://fcw1987.github.io/PickleBlast/'
REPO = 'https://github.com/fcw1987/PickleBlast'

class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.links, self.resources, self.ids, self.errors = [], [], set(), []
        self.title = self.main = self.h1 = self.lang = self.viewport = False
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in {'script', 'iframe', 'form', 'object', 'embed', 'video', 'audio'}:
            self.errors.append(f'unexpected active or embedded content: {tag}')
        if any(k.startswith('on') for k in a): self.errors.append('inline event handler')
        if tag == 'base': self.errors.append('base URL needs explicit audit')
        if tag == 'style' or 'style' in a: self.errors.append('inline CSS needs explicit audit; use local stylesheet')
        if tag == 'meta' and a.get('http-equiv', '').lower() == 'refresh': self.errors.append('automatic page redirect')
        if 'background' in a: self.resources.append(a['background'])
        if tag == 'image': self.resources.append(a.get('href', a.get('xlink:href', '')))
        if 'id' in a:
            if a['id'] in self.ids: self.errors.append('duplicate element ID')
            self.ids.add(a['id'])
        if tag == 'html': self.lang = a.get('lang') == 'en'
        if tag == 'title': self.title = True
        if tag == 'main': self.main = True
        if tag == 'h1': self.h1 = True
        if tag == 'meta' and a.get('name') == 'viewport': self.viewport = True
        if tag == 'a' and 'href' in a: self.links.append(a['href'])
        if tag == 'img':
            if 'alt' not in a: self.errors.append('image lacks alternative text (empty alt is valid for decoration)')
            if not a.get('width') or not a.get('height'): self.errors.append('image lacks dimensions')
        if 'src' in a: self.resources.append(a['src'])
        if 'srcset' in a: self.errors.append('srcset needs explicit audit; use local src')
        if tag == 'link' and set(a.get('rel', '').lower().split()) & {'stylesheet', 'icon', 'apple-touch-icon', 'preload', 'prefetch', 'preconnect', 'dns-prefetch', 'manifest'}:
            self.resources.append(a.get('href', ''))


def target_for(page: str, href: str, docs: Path) -> Path | None:
    parsed = urlsplit(urljoin(BASE + page, href))
    if parsed.scheme != 'https': raise ValueError('non-HTTPS or unsupported link')
    if parsed.netloc != 'fcw1987.github.io': return None
    if not parsed.path.startswith('/PickleBlast/'):
        raise ValueError('link escapes the project path prefix')
    relative = unquote(parsed.path[len('/PickleBlast/'):])
    if not relative or relative.endswith('/'): relative += 'index.html'
    target = docs / relative
    if any((docs / Path(*Path(relative).parts[:i])).is_symlink() for i in range(1, len(Path(relative).parts) + 1)):
        raise ValueError('symlink local target')
    if not target.resolve().is_relative_to(docs.resolve()): raise ValueError('link escapes site directory')
    current = docs
    for part in Path(relative).parts:
        if part not in {p.name for p in current.iterdir()}:
            raise ValueError('missing or wrong-case local target')
        current = current / part
    if not target.is_file(): raise ValueError('target is not a file')
    return target


def read_json_object(path: Path, label: str, failures: list[str]) -> dict:
    try:
        value = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        failures.append(f'{label}: unreadable or invalid JSON ({type(error).__name__})')
        return {}
    if not isinstance(value, dict):
        failures.append(f'{label}: JSON must be an object')
        return {}
    return value


def png_header(contents: bytes) -> tuple[int, int, bool] | None:
    if (len(contents) < 33 or contents[:8] != b'\x89PNG\r\n\x1a\n' or
            contents[8:16] != b'\x00\x00\x00\x0dIHDR'):
        return None
    width, height = struct.unpack('>II', contents[16:24])
    if not width or not height or contents[25] not in (0, 2, 3, 4, 6):
        return None
    alpha = contents[25] in (4, 6)
    offset = 8
    has_pixels = False
    while offset + 12 <= len(contents):
        length = struct.unpack('>I', contents[offset:offset + 4])[0]
        end = offset + length + 12
        if end > len(contents): return None
        chunk = contents[offset + 4:offset + 8]
        expected_crc = struct.unpack('>I', contents[end - 4:end])[0]
        if zlib.crc32(contents[offset + 4:end - 4]) & 0xffffffff != expected_crc: return None
        if chunk == b'IDAT' and length: has_pixels = True
        if chunk == b'tRNS': alpha = True
        if chunk == b'IEND': return (width, height, alpha) if has_pixels and length == 0 and end == len(contents) else None
        offset = end
    return None


def check(root: Path = ROOT) -> list[str]:
    docs = root / 'docs'
    failures, pages = [], {}
    if not docs.is_dir() or docs.is_symlink(): return ['missing site directory or site directory is a symlink']
    symlinks = [path for path in docs.rglob('*') if path.is_symlink()]
    if symlinks:
        return [f'{path.relative_to(docs)}: site symlink' for path in symlinks]
    required_pages = ['index.html', 'privacy/index.html', 'support/index.html', '404.html']
    additional_pages = sorted(path.relative_to(docs).as_posix() for path in docs.rglob('*.html')
                              if path.relative_to(docs).as_posix() not in required_pages)
    for rel in required_pages + additional_pages:
        path = docs / rel
        if not path.is_file():
            failures.append(f'{rel}: missing required page'); continue
        page = Page(); page.feed(path.read_text())
        pages[rel] = page
        failures.extend(f'{rel}: {e}' for e in page.errors)
        if not all((page.title, page.main, page.h1, page.lang, page.viewport)):
            failures.append(f'{rel}: missing page title, main, heading, language or viewport')
        if re.search(r'\b(?:TODO|TBD|PLACEHOLDER|lorem ipsum)\b', path.read_text(), re.I):
            failures.append(f'{rel}: unfinished public copy')
    for rel, page in pages.items():
        for href in page.links + page.resources:
            try:
                target = target_for(rel, href, docs)
                if href in page.resources and target is None:
                    raise ValueError('external automatic resource request')
                fragment = urlsplit(href).fragment
                if target and fragment and target.suffix.lower() == '.html':
                    other = Page(); other.feed(target.read_text())
                    if unquote(fragment) not in other.ids: raise ValueError('missing anchor')
            except (ValueError, OSError) as e: failures.append(f'{rel}: {href}: {e}')
    support = pages.get('support/index.html')
    if support:
        for template in ('bug_report.yml', 'feature_request.yml', 'support_question.yml'):
            expected = REPO + '/issues/new?template=' + template
            if expected not in support.links: failures.append(f'support: missing direct {template} link')
            if not (root / '.github/ISSUE_TEMPLATE' / template).is_file(): failures.append(f'missing {template}')
        if REPO + '/security/advisories/new' not in support.links: failures.append('missing private security route')
    css = docs / 'assets/site.css'
    if css.exists():
        text = css.read_text()
        if ':focus-visible' not in text: failures.append('CSS lacks visible keyboard focus')
        if 'prefers-reduced-motion' not in text: failures.append('CSS lacks reduced motion handling')
    else: failures.append('missing site CSS')
    for stylesheet in docs.rglob('*.css'):
        text = stylesheet.read_text()
        if re.search(r'''@import|https?://|data:|url\(\s*['"]?\s*//''', text, re.I): failures.append('CSS has unaudited external/inline resources')
        if '\\' in text: failures.append('CSS escapes need explicit resource audit')
        for match in re.finditer(r'url\(\s*([^)]*)\s*\)', text, re.I):
            href = match[1].strip().strip('\"\'')
            try:
                if target_for(stylesheet.relative_to(docs).as_posix(), href, docs) is None:
                    raise ValueError('external automatic resource request')
            except (ValueError, OSError) as error:
                failures.append(f'CSS resource: {href}: {error}')
    if not (docs / '.nojekyll').is_file(): failures.append('missing static deployment marker')
    for path in docs.rglob('*'):
        if path.is_symlink(): failures.append(f'{path.relative_to(docs)}: site symlink')
        if path.is_file() and path.stat().st_size > 2 * 1024 * 1024:
            failures.append(f'{path.relative_to(docs)}: exceeds curated file size limit')
    try:
        for path, expected in sync_privacy.outputs(root).items():
            if not path.is_file() or path.read_text() != expected:
                failures.append('privacy content is not synchronized: ' + path.relative_to(root).as_posix())
    except (ValueError, OSError) as error:
        failures.append('privacy synchronization check failed: ' + type(error).__name__)
    metadata = docs / 'app_store/metadata_en_US.json'
    if metadata.is_file():
        data = read_json_object(metadata, 'metadata', failures)
        required = {'name', 'subtitle', 'description', 'keywords', 'promotional_text', 'support_url', 'privacy_policy_url', 'marketing_url', 'copyright', 'version', 'prepared_build', 'bundle_identifier', 'release_plan'}
        for key in required:
            if key == 'release_plan':
                if not isinstance(data.get(key), dict) or not data[key]: failures.append('missing or invalid metadata release_plan')
            elif not isinstance(data.get(key), str) or not data[key].strip():
                failures.append(f'missing or invalid required metadata {key}')
        plan = data.get('release_plan')
        if isinstance(plan, dict):
            proposed = {'distribution': 'Public App Store', 'price': 'Free', 'storefronts': ['United States'],
                        'automatically_include_new_territories': False, 'preorder': False}
            for key, expected in proposed.items():
                if (expected is False and plan.get(key) is not False) or plan.get(key) != expected:
                    failures.append(f'release plan differs from owner decision: {key}')
        limits = {'name':30, 'app_name':30, 'subtitle':30, 'description':4000, 'promotional_text':170}
        for key, limit in limits.items():
            if isinstance(data.get(key), str) and len(data[key]) > limit: failures.append(f'{key} exceeds {limit} characters')
        if isinstance(data.get('keywords'), str) and len(data['keywords'].encode('utf-8')) > 100:
            failures.append('keywords exceed 100 UTF-8 bytes')
        for key, url in [('support_url', BASE+'support/'), ('privacy_policy_url', BASE+'privacy/'), ('marketing_url', BASE)]:
            if key in data and data[key] != url: failures.append(f'incorrect metadata {key}')
    else: failures.append('missing App Store metadata draft')
    notes = docs / 'app_store/review_notes.txt'
    if not notes.is_file() or not notes.read_text().strip(): failures.append('missing review notes')
    elif notes.stat().st_size > 4000: failures.append('review notes exceed 4000 UTF-8 bytes')
    manifest = docs / 'app_store/screenshot_manifest.json'
    if not manifest.is_file(): failures.append('missing screenshot provenance')
    else:
        evidence = read_json_object(manifest, 'screenshot provenance', failures)
        if not isinstance(evidence.get('app_source_commit'), str) or not re.fullmatch(r'[0-9a-f]{40}', evidence['app_source_commit']):
            failures.append('screenshot source commit missing or invalid')
        captures = evidence.get('captures', [])
        if not isinstance(captures, list):
            failures.append('captures must be an array'); captures = []
        if not 1 <= len(captures) <= 10: failures.append('require 1–10 store captures')
        dimensions = set()
        capture_ids = set()
        for capture in captures:
            if not isinstance(capture, dict):
                failures.append('capture must be an object'); continue
            identifier = capture.get('id')
            if not isinstance(identifier, str) or not identifier or identifier in capture_ids:
                failures.append('capture ID missing, invalid or duplicated')
            else: capture_ids.add(identifier)
            for key, hashkey in [('store_path','sha256'), ('website_path','website_sha256')]:
                raw_path = capture.get(key)
                if not isinstance(raw_path, str) or not raw_path or Path(raw_path).is_absolute():
                    failures.append(f'missing/invalid relative capture {key}'); continue
                path = (manifest.parent / raw_path).resolve()
                boundary = manifest.parent.resolve() if key == 'store_path' else docs.resolve()
                if not path.is_relative_to(boundary) or not path.is_file():
                    failures.append(f'missing/escaped capture {key}'); continue
                contents = path.read_bytes()
                if hashlib.sha256(contents).hexdigest() != capture.get(hashkey):
                    failures.append(f'{capture.get("id")}: mismatched {hashkey}')
                header = png_header(contents)
                if header is None:
                    failures.append('capture must be a valid lossless PNG'); continue
                width, height, alpha = header
                if key == 'store_path':
                    dimensions.add((width,height))
                    if (width,height) not in {(422,514),(410,502),(416,496),(396,484),(368,448),(312,390)}:
                        failures.append('store capture has unsupported dimensions')
                    if (width,height) != (capture.get('width'),capture.get('height')):
                        failures.append('capture manifest dimensions differ')
                    if alpha: failures.append('store capture must not have an alpha channel')
        if len(dimensions) != 1: failures.append('store capture dimensions must match')
    for path in list(docs.rglob('*.html')) + list((docs / 'app_store').glob('*.txt')) + list((docs / 'app_store').glob('*.json')):
        if re.search(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', path.read_text()):
            failures.append(f'{path.relative_to(docs)}: public email address')
    return failures

if __name__ == '__main__':
    errors = check()
    if errors:
        for error in errors: print('FAIL:', error, file=sys.stderr)
        raise SystemExit(1)
    print('PASS: project-prefix routes, local resources, semantic HTML, Issues, static-site safety, and metadata limits.')
