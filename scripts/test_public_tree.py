#!/usr/bin/env python3
"""Publication guard regressions, using synthetic temporary source trees."""
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

CHECKER = Path(__file__).with_name('check_public_tree.py')


class PublicBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='pickleblast-public-check-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / 'Source with spaces'
        (self.root / 'scripts').mkdir(parents=True)
        shutil.copyfile(CHECKER, self.root / 'scripts/check_public_tree.py')

    def run_check(self):
        return subprocess.run([sys.executable, str(self.root / 'scripts/check_public_tree.py')],
                              capture_output=True, text=True)

    def init_repository(self):
        subprocess.run(['git', 'init', '--quiet', str(self.root)], check=True,
                       capture_output=True)

    def test_initialized_unstaged_source_is_scanned(self):
        self.init_repository()
        (self.root / 'README.md').write_text('Ordinary source.\n')
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('2 proposed public files', result.stdout)

    def test_untracked_secret_after_staging_cannot_escape_scan(self):
        self.init_repository()
        subprocess.run(['git', 'add', 'scripts/check_public_tree.py'], cwd=self.root,
                       check=True, capture_output=True)
        token = 'ghp_' + 'a' * 36
        (self.root / 'untracked.txt').write_text(token)
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('credential token', result.stdout)
        self.assertNotIn(token, result.stdout + result.stderr)

    def test_ignored_local_signing_is_excluded(self):
        self.init_repository()
        (self.root / '.gitignore').write_text('/Configuration/Signing.local.xcconfig\n')
        (self.root / 'Configuration').mkdir()
        (self.root / 'Configuration/Signing.local.xcconfig').write_text('DEVELOPMENT_TEAM = ' + 'A' * 10 + '\n')
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_initialized_repository_with_zero_inputs_is_rejected(self):
        self.init_repository()
        (self.root / '.gitignore').write_text('*\n')
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('no proposed public files', result.stdout + result.stderr)

    def test_clean_source_zip_is_accepted(self):
        (self.root / 'README.md').write_text('Ordinary public documentation.\n')
        self.assertEqual(self.run_check().returncode, 0)

    def test_private_bundle_directory_cannot_hide_ordinary_files(self):
        for suffix in ['xcresult', 'xcarchive', 'dSYM', 'app']:
            with self.subTest(suffix=suffix):
                folder = self.root / 'results' / ('private.' + suffix)
                folder.mkdir(parents=True)
                (folder / 'Info.plist').write_text('Synthetic private diagnostic.\n')
                result = self.run_check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('private/obsolete development input', result.stdout)
                shutil.rmtree(folder)

    def test_credential_match_is_rejected_without_printing_value(self):
        token = 'ghp_' + 'a' * 36
        (self.root / 'note.txt').write_text(token)
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('credential token', result.stdout)
        self.assertNotIn(token, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
