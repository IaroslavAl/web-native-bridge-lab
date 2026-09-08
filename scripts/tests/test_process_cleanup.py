"""Actual child/grandchild cleanup, isolated ephemeral ports, no Simulator."""
import json
import os
from pathlib import Path
import runpy
import signal
import socket
import subprocess
import sys
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
Run = runpy.run_path(str(ROOT / 'scripts/verify'))['Run']
FIXTURE = ROOT / 'scripts/tests/process_fixture.py'


class ProcessCleanupTests(unittest.TestCase):
    def test_promptly_terminating_owned_groups_are_reaped(self):
        run = Run('prompt-exit-test')
        for index in range(3):
            with (run.out / f'{index}.log').open('w') as log:
                child = run.spawn(['/bin/sleep', '10'], log)
            run.stop_child(child)
            self.assertEqual(child.returncode, -signal.SIGTERM)
        self.assertEqual(run.children, [])

    def test_timeout_and_failed_command_stop_owned_grandchild(self):
        for mode in ('timeout', 'failure'):
            with self.subTest(mode=mode):
                run = Run('process-test-' + mode)
                record = run.out / 'listener.json'
                try:
                    with self.assertRaises((subprocess.TimeoutExpired, RuntimeError)):
                        run.command('tree', [sys.executable, FIXTURE, mode, record], timeout=5)
                    data = json.loads(record.read_text())
                    with socket.socket() as probe:
                        probe.settimeout(0.2)
                        self.assertNotEqual(probe.connect_ex(('127.0.0.1', data['port'])), 0,
                                            'owned grandchild listener survived command cleanup')
                    self.assertEqual(run.children, [])
                finally:
                    # Negative-control cleanup: only this freshly-created fixture's exact argv.
                    if record.exists():
                        data = json.loads(record.read_text())
                        result = subprocess.run(['/bin/ps', '-p', str(data['pid']), '-o', 'command='], capture_output=True, text=True)
                        expected = f'{sys.executable} {FIXTURE} listener {record}'
                        if result.stdout.strip() == expected:
                            os.kill(data['pid'], signal.SIGKILL)
                    time.sleep(0.1)


if __name__ == '__main__':
    unittest.main()
