#!/usr/bin/env python3
"""Regression checks for policy rendering, synchronization and shell boundaries."""
from pathlib import Path
import tempfile
import unittest
import sync_privacy


class PrivacySyncTests(unittest.TestCase):
    def test_offline_policy_keeps_https_link_destinations(self):
        native, website = sync_privacy.render('# Policy\n\n## Support\n\nSee [GitHub](https://github.com/privacy).\n')
        self.assertIn('See GitHub (https://github.com/privacy).', native)
        self.assertIn('<h2>Support</h2>', website)
        self.assertIn('<a href="https://github.com/privacy">GitHub</a>', website)

    def test_html_content_and_attributes_are_escaped(self):
        _, website = sync_privacy.render('# Policy\n\nA <script> & [A&B](https://example.com/?a=1&b=2).\n')
        self.assertNotIn('<script>', website)
        self.assertIn('&lt;script&gt; &amp;', website)
        self.assertIn('href="https://example.com/?a=1&amp;b=2"', website)
        self.assertIn('A&amp;B</a>', website)

    def test_rejects_unsupported_format_and_missing_title(self):
        for source in ['', 'No title', '# Policy\n\n[Broken](http://example.com)', '# Policy\n\n### Unsupported', '# Policy\n\n- unsupported', '# Policy\n\n**bold**', '# One\n\n# Two']:
            with self.subTest(source=source), self.assertRaises(ValueError):
                sync_privacy.render(source)

    def test_shell_is_preserved_and_outputs_follow_canonical_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'docs/privacy').mkdir(parents=True)
            policy = root / 'PRIVACY.md'
            policy.write_text('# Policy\n\nLocal information.\n')
            shell = '<main>\n' + sync_privacy.BEGIN + '\nold\n' + sync_privacy.END + '\n</main>'
            (root / 'docs/privacy/index.html').write_text(shell)
            outputs = sync_privacy.outputs(root)
            page = outputs[root / 'docs/privacy/index.html']
            self.assertTrue(page.startswith('<main>\n' + sync_privacy.BEGIN))
            self.assertTrue(page.endswith(sync_privacy.END + '\n</main>'))
            self.assertNotIn('\nold\n', page)
            policy.write_text('# Policy\n\nUpdated local information.\n')
            changed = sync_privacy.outputs(root)
            for path in outputs:
                self.assertNotEqual(outputs[path], changed[path])

    def test_requires_single_ordered_marker_pair(self):
        for shell in [sync_privacy.END + sync_privacy.BEGIN,
                      sync_privacy.BEGIN + sync_privacy.BEGIN + sync_privacy.END,
                      sync_privacy.BEGIN, '<main></main>']:
            with self.subTest(shell=shell), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / 'docs/privacy').mkdir(parents=True)
                (root / 'PRIVACY.md').write_text('# Policy\n\nLocal information.\n')
                (root / 'docs/privacy/index.html').write_text(shell)
                with self.assertRaises(ValueError):
                    sync_privacy.outputs(root)


if __name__ == '__main__':
    unittest.main()
