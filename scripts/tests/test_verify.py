"""Tests for fail-closed same-installed-app evidence helpers (no Simulator mocks)."""
import hashlib
import runpy
import sys
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

    def test_stage3_log_rejects_redirect_destinations_and_unadmitted_requests(self):
        check = self.helper('require_stage3_events')
        lines = [
            'GET /fixtures/redirect-same 302 tag=s3-redirect-same',
            'GET /fixtures/redirect-cross 302 tag=s3-redirect-cross',
            'GET /fixtures/redirect-loop 307 tag=s3-redirect-loop',
            'POST /fixtures/echo 200 tag=s3-body-limit',
            'POST /fixtures/echo 200 tag=s3-hostile',
            'GET /fixtures/large 200 tag=s3-response-limit',
            'GET /fixtures/binary 200 tag=s3-binary',
            'GET /fixtures/invalid-utf8 200 tag=s3-encoding',
        ] + [f'GET /fixtures/delay 200 tag=s3-slot-{i}' for i in range(8)]
        self.assertEqual(check('\n'.join(lines)), lines)
        for index in range(len(lines)):
            with self.subTest(missing=lines[index]), self.assertRaises(AssertionError):
                check('\n'.join(lines[:index] + lines[index + 1:]))
        for extra in ['GET /api/catalog 200 tag=-', 'GET /healthz 200 tag=-',
                      'GET /fixtures/delay 200 tag=s3-busy', lines[2],
                      'POST /fixtures/echo 200 tag=s3-denied-body',
                      'GET /stage3-frame-same.html 404 tag=-']:
            with self.subTest(extra=extra), self.assertRaises(AssertionError):
                check('\n'.join(lines + [extra]))

    def test_stage4_events_reject_leaks_late_success_and_forbidden_destinations(self):
        check = self.helper('require_stage4_events')
        events = [dict(path='/delay', tag=tag, event=event) for tag in
                  ('reload', 'navigation', 'close', 'destruction') for event in ('request', 'connection-close')]
        events += [dict(path='/inspect', tag='privacy-first', event='request', cookie=False, authorization=False)]
        check(events)
        for mutation in [events[:-2], events + [dict(path='/forbidden-frame', event='request')],
                         events + [dict(path='/delay', tag='reload', event='finished')],
                         events + [dict(path='/challenge', tag='privacy-auth-4', event='request', authorization=True)]]:
            with self.assertRaises(AssertionError):
                check(mutation)

    def test_same_app_rejects_container_change_and_non_executable_change(self):
        same = self.helper('require_same_app')
        first = {'udid': 'device', 'container': '/app/one', 'files': {'BridgeLab': 'exe', 'Info.plist': 'plist'}}
        same(first, first.copy())
        for field, value in [('udid', 'other'), ('container', '/app/two'),
                             ('files', {'BridgeLab': 'exe', 'Info.plist': 'changed'})]:
            with self.subTest(field=field), self.assertRaisesRegex(AssertionError, field):
                same(first, {**first, field: value})

    def test_explain_mode_reuses_owned_simulator_path_and_static_control_files(self):
        modes = self.helper('SIMULATOR_MODES')
        controls = self.helper('explain_control_names')()
        self.assertEqual(modes['simulator-explain-v2'], {'explain': True})
        self.assertEqual(controls, (
            'explain-enabled', 'api-failure-ready', 'api-failure-observed', 'api-recovery-observed',
            'asset-failure-ready', 'asset-failure-observed',
            'large-text-ready', 'matrix-observed',
        ))
        self.assertTrue(all('/' not in name for name in controls))

    def test_explain_log_requires_real_catalog_quote_retry_and_cold_repeat(self):
        check = self.helper('require_explain_events')
        catalog = 'GET /api/catalog 200 tag=scenario-a'
        quote = 'POST /api/quote 200 tag=scenario-b'
        lines = [catalog, quote, quote, quote, quote]
        self.assertEqual(check('\n'.join(lines)), {'catalog': 1, 'quote': 4})
        for mutation in [lines[1:], lines[:-1], lines + [catalog], lines + [quote]]:
            with self.assertRaises(AssertionError):
                check('\n'.join(mutation))

    def test_web_entry_requires_one_built_hashed_javascript_asset(self):
        entry = self.helper('web_entry')
        manifest = {'index.html': 'html', 'assets/index-Ab12.js': 'entry', 'assets/index-Cd34.css': 'css'}
        self.assertEqual(entry(manifest), 'assets/index-Ab12.js')
        for invalid in [
            {'index.html': 'html'},
            {'assets/index-a.js': 'a', 'assets/index-b.js': 'b'},
            {'assets/other.js': 'other'},
        ]:
            with self.assertRaises(AssertionError):
                entry(invalid)

    def test_command_failure_records_real_exit_and_reaps_owned_process_group(self):
        run = self.helper('Run')('unit-explain-command-failure')
        with self.assertRaisesRegex(RuntimeError, 'exit 7'):
            run.command('expected-failure', [sys.executable, '-c', 'raise SystemExit(7)'], timeout=5)
        self.assertEqual(run.commands[-1]['exit_code'], 7)
        self.assertEqual(run.children, [])

    def test_retry_command_records_transient_failure_and_real_success(self):
        run = self.helper('Run')('unit-explain-command-retry')
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / 'attempt'
            script = (
                "from pathlib import Path; import sys; "
                f"p=Path({str(marker)!r}); exists=p.exists(); p.write_text('seen'); "
                "raise SystemExit(0 if exists else 1)"
            )
            run.command_retry('flaky-status', [sys.executable, '-c', script], attempts=2, pause=0)
        attempts = [record for record in run.commands if record['name'].startswith('flaky-status')]
        self.assertEqual([record['exit_code'] for record in attempts], [1, 0])
        self.assertEqual(run.children, [])

    def test_lab_start_marks_cleanup_ownership_before_interruptible_command(self):
        run = self.helper('Run')('unit-lab-start-ownership')
        ownership = {'running': False, 'start_attempted': False}

        def interrupted(name, args):
            self.assertEqual(name, 'lab-start')
            self.assertEqual(args, ['ignored'])
            self.assertTrue(ownership['running'])
            self.assertTrue(ownership['start_attempted'])
            raise KeyboardInterrupt('between start completion and caller bookkeeping')

        run.command = interrupted
        with self.assertRaises(KeyboardInterrupt):
            run.command_lab_start('lab-start', ['ignored'], ownership)
        self.assertTrue(ownership['running'])
        self.assertTrue(ownership['start_attempted'])

    def test_missing_entry_fault_is_cleanup_eligible_before_and_after_interrupted_move(self):
        move = self.helper('move_entry_for_fault')
        restore = self.helper('restore_entry_after_fault')

        class HiddenEntry:
            moved = False
            restored = False

            def exists(self):
                return self.moved

            def replace(self, entry):
                self.restored = True
                self.moved = False

        class InterruptingEntry:
            def __init__(self, hidden, ownership, after_move):
                self.hidden = hidden
                self.ownership = ownership
                self.after_move = after_move

            def replace(self, hidden):
                self.assert_registered(hidden)
                if self.after_move:
                    hidden.moved = True
                raise KeyboardInterrupt('fault move interrupted')

            def assert_registered(self, hidden):
                if self.ownership.get('paths') != (self, hidden):
                    raise AssertionError('cleanup ownership was not registered before move')

        for after_move in (False, True):
            with self.subTest(after_move=after_move):
                ownership = {'paths': None}
                hidden = HiddenEntry()
                entry = InterruptingEntry(hidden, ownership, after_move)
                with self.assertRaises(KeyboardInterrupt):
                    move(entry, hidden, ownership)
                self.assertEqual(ownership['paths'], (entry, hidden))
                restore(ownership)
                self.assertIsNone(ownership['paths'])
                self.assertEqual(hidden.restored, after_move)


if __name__ == '__main__':
    unittest.main()
