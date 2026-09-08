"""Tests for fail-closed same-installed-app evidence helpers (no Simulator mocks)."""
import hashlib
import runpy
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts' / 'verify'
HELPERS = runpy.run_path(str(SCRIPT)) if SCRIPT.exists() else {}


class EvidenceTests(unittest.TestCase):
    def helper(self, name):
        self.assertIn(name, HELPERS, f'verification helper missing: {name}')
        return HELPERS[name]

    def test_manifest_includes_every_file_sorted_and_detects_resource_change(self):
        manifest = self.helper('manifest')
        with tempfile.TemporaryDirectory(dir=ROOT / '.artifacts') as directory:
            root = Path(directory)
            (root / 'z').write_bytes(b'last')
            (root / 'a').write_bytes(b'first')
            first = manifest(root)
            self.assertEqual(list(first), ['a', 'z'])
            self.assertEqual(first['a'], hashlib.sha256(b'first').hexdigest())
            (root / 'z').write_bytes(b'changed')
            self.assertNotEqual(first, manifest(root))

    def test_manifest_includes_hidden_files_and_rejects_symlinks(self):
        manifest = self.helper('manifest')
        with tempfile.TemporaryDirectory(dir=ROOT / '.artifacts') as directory:
            root = Path(directory)
            (root / '.hidden').write_bytes(b'resource')
            self.assertIn('.hidden', manifest(root))
            (root / 'link').symlink_to(root / '.hidden')
            with self.assertRaisesRegex(AssertionError, 'symlink'):
                manifest(root)

    def test_stage2_log_requires_socket_closes_and_out_of_order_completion(self):
        check = self.helper('require_stage2_events')
        lines = [
            'GET /fixtures/http-error 503 tag=s2-http',
            'POST /api/quote 422 tag=s2-quote',
            'GET /fixtures/business-error 200 tag=s2-business',
            'GET /fixtures/malformed-json 200 tag=s2-json',
            'GET /fixtures/delay connection-close tag=s2-timeout',
            'GET /fixtures/delay connection-close tag=s2-cancel',
            'GET /fixtures/delay 200 tag=s2-fast',
            'GET /fixtures/delay 200 tag=s2-slow',
        ]
        self.assertEqual(check('\n'.join(lines)), lines)
        for index in range(len(lines)):
            with self.subTest(missing=lines[index]), self.assertRaisesRegex(AssertionError, 's2-'):
                check('\n'.join(lines[:index] + lines[index + 1:]))
        with self.assertRaisesRegex(AssertionError, 'order'):
            check('\n'.join(lines[:-2] + list(reversed(lines[-2:]))))
        with self.assertRaisesRegex(AssertionError, 's2-cancel'):
            check('\n'.join(lines + ['GET /fixtures/delay 200 tag=s2-cancel']))
        with self.assertRaisesRegex(AssertionError, 's2-fast'):
            check('\n'.join(lines + [lines[-2]]))

    def test_same_app_rejects_container_change_and_non_executable_change(self):
        same = self.helper('require_same_app')
        first = {'udid': 'device', 'container': '/app/one', 'files': {'BridgeLab': 'exe', 'Info.plist': 'plist'}}
        same(first, first.copy())
        for field, value in [('udid', 'other'), ('container', '/app/two'),
                             ('files', {'BridgeLab': 'exe', 'Info.plist': 'changed'})]:
            with self.subTest(field=field), self.assertRaisesRegex(AssertionError, field):
                same(first, {**first, field: value})


if __name__ == '__main__':
    unittest.main()
