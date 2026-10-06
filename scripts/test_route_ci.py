#!/usr/bin/env python3
"""Routing regressions: never omit full validation for app/build/policy changes."""
from pathlib import Path
import subprocess
import tempfile
import unittest
import route_ci


class PathRoutingTests(unittest.TestCase):
    def test_current_copy_and_site_paths_are_lightweight(self):
        self.assertTrue(route_ci.docs_only(['README.md', 'docs/index.html', 'docs/privacy/index.html',
                                            'docs/assets/site.css', 'docs/images/boss-rally.png',
                                            'docs/app_store/metadata_en_US.json', '.github/CONTRIBUTING.md']))

    def test_app_build_asset_test_ci_policy_and_unknown_paths_are_full(self):
        for path in ['Sources/PickleBlastCore/Engine.swift', 'WatchApp/GameScreens.swift',
                     'WatchApp/Art/Player.atlas/frame.png', 'WatchApp/Assets.xcassets/Contents.json',
                     'WatchApp/Policy/Privacy.txt', 'PRIVACY.md', 'Package.swift',
                     'PickleBlast.xcodeproj/project.pbxproj', 'Configuration/Signing.xcconfig',
                     'scripts/generate_project.py', 'scripts/ci_docs.sh', 'scripts/test_site.py',
                     'Tests/PickleBlastCoreTests/EngineTests.swift', 'WatchUITests/Test.swift',
                     '.github/workflows/validation.yml', 'docs/new_build_tool.py', 'new-input.toml',
                     '../README.md', '/README.md']:
            with self.subTest(path=path):
                self.assertFalse(route_ci.docs_only(['README.md', path]))

    def test_empty_change_list_is_full(self):
        self.assertFalse(route_ci.docs_only([]))

    def test_manual_unknown_and_missing_comparisons_are_full(self):
        for event, base, head in [('workflow_dispatch', '', ''), ('unknown', '', ''),
                                  ('push', '0' * 40, 'a' * 40), ('push', '', 'a' * 40),
                                  ('push', 'not-a-sha', 'a' * 40)]:
            with self.subTest(event=event, base=base):
                self.assertTrue(route_ci.route(event, base, head)[0])


class GitDiffRoutingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.name', 'Routing Test')
        self.git('config', 'user.email', 'routing@example.invalid')
        self.write('README.md')
        self.write('Sources/App.swift')
        self.base = self.commit()

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, stderr=subprocess.DEVNULL).decode().strip()

    def write(self, name, text='content\n'):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def commit(self):
        self.git('add', '-A')
        self.git('commit', '-qm', 'Fixture change')
        return self.git('rev-parse', 'HEAD')

    def test_push_docs_diff_and_deleted_doc_are_lightweight(self):
        (self.root / 'README.md').unlink()
        self.write('docs/new name\nwith newline.md')
        head = self.commit()
        self.assertFalse(route_ci.route('push', self.base, head, self.root)[0])

    def test_source_rename_into_docs_is_full(self):
        self.write('docs/source.txt', (self.root / 'Sources/App.swift').read_text())
        (self.root / 'Sources/App.swift').unlink()
        self.assertTrue(route_ci.route('push', self.base, self.commit(), self.root)[0])

    def test_deleted_source_is_full(self):
        (self.root / 'Sources/App.swift').unlink()
        self.assertTrue(route_ci.route('push', self.base, self.commit(), self.root)[0])

    def test_pull_request_uses_merge_base_not_new_base_changes(self):
        self.git('switch', '-qc', 'feature')
        self.write('README.md', 'Updated copy\n')
        head = self.commit()
        self.git('switch', '-q', 'main')
        self.write('Sources/App.swift', 'New app code on base\n')
        newer_base = self.commit()
        self.assertFalse(route_ci.route('pull_request', newer_base, head, self.root)[0])
        self.assertTrue(route_ci.route('push', newer_base, head, self.root)[0])

    def test_unavailable_base_is_full(self):
        self.assertTrue(route_ci.route('push', 'a' * 40, self.base, self.root)[0])

    def test_zero_diff_is_full(self):
        self.assertTrue(route_ci.route('push', self.base, self.base, self.root)[0])


if __name__ == '__main__':
    unittest.main()
