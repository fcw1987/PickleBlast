#!/usr/bin/env python3
"""Isolated failure-case tests for static routes, metadata and screenshot checks."""
from pathlib import Path
import hashlib
import json
import struct
import tempfile
import unittest
import zlib
import check_site
import sync_privacy


def png(width=422, height=514, alpha=False, transparent=False):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    channels = 4 if alpha else 3
    header = struct.pack('>IIBBBBB', width, height, 8, 6 if alpha else 2, 0, 0, 0)
    image = b'\x00' * (height * (1 + width * channels))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) +
            (chunk(b'tRNS', b'\x00' * 6) if transparent else b'') +
            chunk(b'IDAT', zlib.compress(image)) + chunk(b'IEND', b''))


def page(body):
    return '<!doctype html><html lang="en"><head><title>PickleBlast</title><meta name="viewport" content="width=device-width"></head><body><main id="main">' + body + '</main></body></html>'


class SiteTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.docs = self.root / 'docs'
        for folder in ['privacy', 'support', 'assets', 'app_store/screenshots', 'images']:
            (self.docs / folder).mkdir(parents=True, exist_ok=True)
        (self.docs / '.nojekyll').touch()
        (self.docs / 'assets/site.css').write_text(':focus-visible{outline:1px solid white}@media(prefers-reduced-motion:reduce){*{animation:none}}')
        for name in ['index.html', '404.html']:
            (self.docs / name).write_text(page('<h1>PickleBlast</h1><a href="privacy/">Privacy</a><a href="support/">Support</a>'))
        templates = ('bug_report.yml', 'feature_request.yml', 'support_question.yml')
        support = '<h1>Support</h1><a href="../">Home</a>'
        folder = self.root / '.github/ISSUE_TEMPLATE'
        folder.mkdir(parents=True)
        for template in templates:
            (folder / template).write_text('name: Support\n')
            support += f'<a href="{check_site.REPO}/issues/new?template={template}">Report</a>'
        support += f'<a href="{check_site.REPO}/security/advisories/new">Security</a>'
        (self.docs / 'support/index.html').write_text(page(support))
        (self.root / 'PRIVACY.md').write_text('# Privacy\n\nLocal gameplay information.\n')
        (self.docs / 'privacy/index.html').write_text(page(sync_privacy.BEGIN + '\n' + sync_privacy.END))
        for path, content in sync_privacy.outputs(self.root).items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        self.metadata_path = self.docs / 'app_store/metadata_en_US.json'
        self.metadata = {key: 'Draft' for key in ('name', 'subtitle', 'description', 'keywords', 'promotional_text', 'copyright', 'version', 'prepared_build', 'bundle_identifier')}
        self.metadata.update(support_url=check_site.BASE+'support/', privacy_policy_url=check_site.BASE+'privacy/', marketing_url=check_site.BASE,
            release_plan={'distribution':'Public App Store', 'price':'Free', 'storefronts':['United States'], 'automatically_include_new_territories':False, 'preorder':False})
        self.metadata_path.write_text(json.dumps(self.metadata))
        (self.docs / 'app_store/review_notes.txt').write_text('Watch-only game; no demo login needed.')
        self.manifest_path = self.docs / 'app_store/screenshot_manifest.json'
        self.capture = {'id':'boss-rally', 'store_path':'screenshots/boss.png', 'website_path':'../images/boss.png', 'width':422, 'height':514}
        self.evidence = {'app_source_commit':'a'*40, 'captures':[self.capture]}
        self.write_images(png())

    def write_images(self, contents):
        (self.docs / 'app_store/screenshots/boss.png').write_bytes(contents)
        (self.docs / 'images/boss.png').write_bytes(contents)
        self.capture['sha256'] = self.capture['website_sha256'] = hashlib.sha256(contents).hexdigest()
        self.write_manifest()

    def write_manifest(self):
        self.manifest_path.write_text(json.dumps(self.evidence))

    def failures_contain(self, phrase):
        failures = check_site.check(self.root)
        self.assertTrue(any(phrase in error for error in failures), failures)

    def test_valid_fixture_passes(self):
        self.assertEqual(check_site.check(self.root), [])

    def test_direct_nested_routes_and_fragments(self):
        self.assertEqual(check_site.target_for('support/index.html', '../privacy/', self.docs), self.docs/'privacy/index.html')
        with (self.docs/'index.html').open('a') as stream: stream.write('<a href="privacy/#missing">Missing</a>')
        self.failures_contain('missing anchor')

    def test_prefix_traversal_and_case_errors(self):
        for href in ['/privacy/', '../outside.txt', '%2e%2e/outside.txt', 'privacy/%2e%2e/%2e%2e/outside.txt', 'Privacy/']:
            with self.subTest(href=href), self.assertRaises((ValueError, OSError)):
                check_site.target_for('index.html', href, self.docs)

    def test_site_symlink_is_rejected_before_read(self):
        secret = self.root/'outside.txt'; secret.write_text('Private fixture')
        (self.docs/'images/escape.png').symlink_to(secret)
        self.failures_contain('site symlink')

    def test_active_automatic_external_resources_are_rejected(self):
        original = (self.docs/'index.html').read_text()
        for markup in ['<img src="https://example.com/image.png" width="1" height="1" alt="">', '<link rel="apple-touch-icon" href="//example.com/icon.png">', '<link rel="preconnect" href="https://example.com">', '<div style="background:url(https://example.com/pixel)"></div>', '<style>body{background:url(//example.com/pixel)}</style>', '<meta http-equiv="refresh" content="0;url=https://example.com">', '<script src="assets/no.js"></script>']:
            with self.subTest(markup=markup):
                (self.docs/'index.html').write_text(original+markup)
                self.assertTrue(check_site.check(self.root))

    def test_additional_served_html_and_css_are_audited(self):
        extra = self.docs/'extra.html'
        extra.write_text(page('<h1>More information</h1><iframe src="https://example.com"></iframe>'))
        self.failures_contain('unexpected active or embedded content')
        extra.unlink()
        (self.docs/'assets/extra.css').write_text('body{background:url(https://example.com/pixel)}')
        self.failures_contain('external automatic resource request')

    def test_external_or_missing_css_resources_fail(self):
        css = self.docs/'assets/site.css'; original = css.read_text()
        for rule in ['body{background:url(//example.com/pixel)}', 'body{background:url(../images/missing.png)}']:
            with self.subTest(rule=rule):
                css.write_text(original+rule)
                self.assertTrue(check_site.check(self.root))

    def test_missing_malformed_and_wrong_type_metadata_fail_without_crash(self):
        for content in ['{', '[]', 'null', json.dumps({**self.metadata,'name':14}), json.dumps({**self.metadata,'keywords':[]}), json.dumps({k:v for k,v in self.metadata.items() if k!='description'})]:
            with self.subTest(content=content):
                self.metadata_path.write_text(content)
                self.assertTrue(check_site.check(self.root))

    def test_metadata_character_and_keyword_byte_limits(self):
        for key, content, phrase in [('name','x'*31,'name exceeds'),('description','x'*4001,'description exceeds'),('promotional_text','x'*171,'promotional_text exceeds'),('keywords','é'*51,'100 UTF-8 bytes')]:
            with self.subTest(key=key):
                self.metadata_path.write_text(json.dumps({**self.metadata,key:content}))
                self.failures_contain(phrase)

    def test_release_plan_preserves_fixed_owner_decisions(self):
        for key, content in [('price', 'Paid'), ('storefronts', ['United States', 'Canada']), ('preorder', True), ('automatically_include_new_territories', True), ('distribution', 'Private')]:
            with self.subTest(key=key):
                changed = {**self.metadata, 'release_plan': {**self.metadata['release_plan'], key: content}}
                self.metadata_path.write_text(json.dumps(changed))
                self.failures_contain('release plan differs from owner decision')

    def test_unsynchronized_policy_fails(self):
        (self.root/'PRIVACY.md').write_text('# Privacy\n\nChanged canonical text.\n')
        self.failures_contain('privacy content is not synchronized')

    def test_malformed_screenshot_provenance_fails_without_crash(self):
        for content in ['{','[]','null',json.dumps({'app_source_commit':None,'captures':None}),json.dumps({'app_source_commit':'a'*40,'captures':[None]}),json.dumps({'app_source_commit':'a'*40,'captures':[{**self.capture,'store_path':[]}]})]:
            with self.subTest(content=content):
                self.manifest_path.write_text(content)
                self.assertTrue(check_site.check(self.root))

    def test_capture_paths_missing_escape_and_absolute_fail(self):
        for path in ['screenshots/missing.png','../images/boss.png','../../../outside.png',str(self.root/'outside.png')]:
            with self.subTest(path=path):
                self.capture['store_path']=path
                self.write_manifest()
                self.assertTrue(check_site.check(self.root))

    def test_capture_hash_dimensions_and_alpha_fail(self):
        self.capture['sha256']='0'*64; self.write_manifest()
        self.failures_contain('mismatched sha256')
        self.write_images(png())
        self.capture['width']=410; self.write_manifest()
        self.failures_contain('manifest dimensions differ')
        self.capture['width']=422
        self.write_images(png(alpha=True)); self.failures_contain('alpha channel')
        self.write_images(png(transparent=True)); self.failures_contain('alpha channel')

    def test_truncated_png_fails_without_crash(self):
        for contents in [b'\x89PNG\r\n\x1a\n', png()[:33], b'not a PNG']:
            with self.subTest(length=len(contents)):
                self.write_images(contents)
                self.failures_contain('valid lossless PNG')


if __name__ == '__main__':
    unittest.main()
