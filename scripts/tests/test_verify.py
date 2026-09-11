"""Tests for fail-closed same-installed-app evidence helpers (no Simulator mocks)."""
import ast
import hashlib
import re
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

    def test_stage4_excludes_explain_layout_suite_and_keeps_56_test_contract(self):
        selection = self.helper('stage4_test_selection')()
        self.assertEqual(selection, ('-skip-testing:BridgeLabTests/ExplainLayoutTests',))
        self.assertIn("*stage4_test_selection(),", SCRIPT.read_text())
        self.assertIn("summary['passedTests'] == 56", SCRIPT.read_text())

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

    def test_tracked_dist_is_current_variant_b_explain_default(self):
        dist = ROOT / 'web' / 'dist'
        index = (dist / 'index.html').read_text()
        entries = list((dist / 'assets').glob('index-*.js'))

        self.assertIn('<title>Как это работает — Bridge Lab</title>', index)
        self.assertNotIn('<title>Web–Native Bridge Lab</title>', index)
        self.assertEqual(len(entries), 1, f'tracked JavaScript entries: {entries}')
        self.assertIn(f'/assets/{entries[0].name}', index)
        javascript = entries[0].read_text()
        for marker in ('Как это работает', 'Рассчитать заказ',
                       'Этот экран умеет рассчитать заказ из двух блокнотов'):
            self.assertIn(marker, javascript)

    def test_missing_javascript_fallback_names_native_reload_control(self):
        native_source = (ROOT / 'ios' / 'Sources' / 'BridgeLabApp' / 'BridgeScreen.swift').read_text()
        reload_control = re.search(
            r'Button\("([^"]+)"\)\s*\{\s*model\.reload\(\)\s*\}.*?'
            r'\.accessibilityIdentifier\("lab\.reload"\)',
            native_source,
            re.DOTALL,
        )
        if reload_control is None:
            self.fail('native reload control not found')
        native_label = reload_control.group(1)
        self.assertEqual(native_label, 'Обновить')

        fallback = (ROOT / 'web' / 'index.html').read_text()
        self.assertIn(f'Используйте «{native_label}» в установленном приложении.', fallback)

    def test_response_direction_does_not_depend_on_localized_title_prefix(self):
        source = (ROOT / 'web' / 'src' / 'App.tsx').read_text()
        self.assertNotIn('title.startsWith("Ответ получен")', source)

    def test_readme_acceptance_paragraph_is_commit_neutral(self):
        readme = (ROOT / 'README.md').read_text()
        stable = (
            'The linked evidence documents preserve revision-scoped historical runs and their explicit limits. '
            'Any later candidate must be evaluated from its own recorded source revision; this README neither '
            'designates a final candidate nor carries prior acceptance onto changed production, test, runner, '
            'specification, or operational-contract content. Independent technical review and owner '
            'product/aesthetic acceptance remain separate.'
        )
        self.assertIn(stable, ' '.join(readme.splitlines()))
        paragraph = next(block for block in readme.split('\n\n') if 'The linked evidence documents' in block)
        self.assertNotRegex(paragraph, r'\b[0-9a-f]{40}\b')
        self.assertNotRegex(paragraph.lower(), r'current exact head|final sha')

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
        self.assertFalse(ownership.get('created', False))

    def test_static_start_marks_cleanup_ownership_before_interruptible_spawn(self):
        run = self.helper('Run')('unit-static-start-ownership')
        ownership = {'running': False, 'start_attempted': False}

        def interrupted(args, log, env=None):
            self.assertEqual(args, ['ignored'])
            self.assertTrue(ownership['start_attempted'])
            raise KeyboardInterrupt('before static spawn returns')

        run.spawn = interrupted
        with self.assertRaises(KeyboardInterrupt):
            run.spawn_owned_service(['ignored'], None, ownership)
        self.assertTrue(ownership['start_attempted'])
        self.assertFalse(ownership.get('created', False))

    def test_cleanup_port_helper_is_once_only_applicable_and_fail_closed(self):
        verify = self.helper('verify_released_ports')
        errors = []
        calls = []

        self.assertIsNone(verify(False, errors, lambda: calls.append('unused')))
        self.assertEqual(calls, [])
        self.assertTrue(verify(True, errors, lambda: calls.append('checked')))
        self.assertEqual(calls, ['checked'])
        self.assertEqual(errors, [])

        def occupied():
            calls.append('occupied')
            raise RuntimeError('loopback port 8787 unavailable; foreign listeners untouched')

        self.assertFalse(verify(True, errors, occupied))
        self.assertEqual(calls, ['checked', 'occupied'])
        self.assertEqual(errors, [
            'fixed-port release check failed: loopback port 8787 unavailable; foreign listeners untouched'
        ])

    def test_simulator_finally_verifies_ports_after_service_cleanup_branches(self):
        source = SCRIPT.read_text()
        tree = ast.parse(source)
        run_class = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == 'Run')
        simulator = next(node for node in run_class.body if isinstance(node, ast.FunctionDef) and node.name == 'simulator')
        cleanup = next(node.finalbody for node in simulator.body if isinstance(node, ast.Try) and node.finalbody)
        snippets = [ast.get_source_segment(source, node) or '' for node in cleanup]
        static_index = next(index for index, text in enumerate(snippets) if text.startswith('if static_web is not None:'))
        lab_index = next(index for index, text in enumerate(snippets) if text.startswith("if lab_ownership['running']:"))
        port_indices = [
            index for index, node in enumerate(cleanup)
            if isinstance(node, ast.Assign)
            and any(isinstance(target, ast.Name) and target.id == 'ports_released' for target in node.targets)
            and isinstance(node.value, ast.Call)
            and isinstance(node.value.func, ast.Name)
            and node.value.func.id == 'verify_released_ports'
        ]
        self.assertEqual(len(port_indices), 1, 'one top-level final cleanup port verification required')
        port_index = port_indices[0]
        self.assertGreater(port_index, static_index)
        self.assertGreater(port_index, lab_index)

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
