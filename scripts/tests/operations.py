#!/usr/bin/env python3
"""Opt-in, serialized real runner interruption gate; never invoked by unit discovery."""
import json
import os
from pathlib import Path
import runpy
import signal
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
helpers = runpy.run_path(str(ROOT / 'scripts/verify'))
Run, save, free_ports = (helpers[name] for name in ('Run', 'save', 'require_free_ports'))


def wait_for(check, child, label, timeout=180):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        assert child.poll() is None, f'{label}: runner exited early {child.returncode}'
        time.sleep(0.05)
    raise AssertionError(f'{label}: deadline')


def run_gate():
    free_ports()
    run = Run('stage5-operations')
    observations = []
    for name, mode, signum in (
        ('interrupt-before-services', 'simulator-stage1', signal.SIGINT),
        ('terminate-with-services', 'simulator-stage4-webkit-privacy', signal.SIGTERM),
        ('command-failure-with-services', 'simulator-stage4-webkit-privacy', None),
    ):
        env = run.env.copy()
        if signum is None:
            # Real failing executable at the command boundary, not fabricated Xcode output.
            shims = run.out / 'fail-bin'
            shims.mkdir()
            shim = shims / 'xcodebuild'
            shim.write_text('#!/bin/sh\nprintf "intentional Stage5 command failure\\n" >&2\nexit 7\n')
            shim.chmod(0o755)
            env['PATH'] = str(shims) + os.pathsep + env['PATH']
        log_path = run.out / (name + '.log')
        with log_path.open('w') as log:
            child = run.spawn([sys.executable, str(ROOT / 'scripts/verify'), mode], log, env=env)
        output = None
        try:
            line = wait_for(lambda: next((s for s in log_path.read_text().splitlines() if s.startswith('Evidence: ')), None), child, name)
            output = Path(line.removeprefix('Evidence: '))
            simulator_path = output / 'simulator.json'
            wait_for(simulator_path.exists, child, name + ' owns simulator')
            if signum is not None:
                wait_for(lambda: 'RUN boot-ready' in log_path.read_text(), child, name + ' boot ownership')
                child.send_signal(signum)  # exact Popen handle, never a PID-only scan
            code = child.wait(timeout=180)
            assert code == 1, f'{name}: exit_code={code}'
            failure = json.loads((output / 'failure.json').read_text())
            assert (failure['type'] == 'KeyboardInterrupt') if signum else ('exit 7' in failure['error']), failure
            cleanup = json.loads((output / 'cleanup.json').read_text())
            assert cleanup['errors'] == [], f'{name}: cleanup={cleanup}'
            simulator = json.loads((output / 'simulator.json').read_text())
            states = json.loads(run.capture(['xcrun', 'simctl', 'list', 'devices', '-j']))['devices']
            assert all(d['udid'] != simulator['udid'] for group in states.values() for d in group), f'{name}: device survives'
            free_ports()
            observations.append({'name': name, 'runner_pid': child.pid, 'signal': signum,
                                 'exit_code': code, 'failure': failure, 'cleanup': cleanup,
                                 'simulator': simulator, 'ports_released': True, 'evidence': str(output)})
        finally:
            run.stop_child(child)
        save(run.out / 'observations.json', observations)

    # Real lab service signals with active HTTP work, then idempotent stale cleanup.
    for signum in (signal.SIGINT, signal.SIGTERM):
        lab = ['node', str(ROOT / 'scripts/lab')]
        options = ['--state-dir', str(run.out / ('lab-' + str(signum))),
                   '--web-root', str(run.out / 'unused-web')]
        run.command('lab-start-' + str(signum), lab + ['start'] + options)
        try:
            run.command('lab-repeat-start-' + str(signum), lab + ['start'] + options)
            state = json.loads(run.capture(lab + ['status'] + options))
            owned = state['processes'][0]
            assert owned['repoRoot'] == str(ROOT) and owned['scriptPath'] == str(ROOT / 'backend/server.mjs'), 'lab ownership binding'
            with socket.create_connection(('127.0.0.1', 8788), timeout=3) as active:
                active.sendall(b'GET /fixtures/delay?ms=30000&label=stage5 HTTP/1.1\r\nHost: 127.0.0.1:8788\r\n\r\n')
                # Reverify the canonical lab identity immediately before this test's signal.
                assert json.loads(run.capture(lab + ['status'] + options))['processes'] == [owned], 'lab identity changed'
                os.kill(owned['pid'], signum)
                assert active.recv(100) == b'', 'active delay socket not closed by service signal'
            run.command('lab-stop-' + str(signum), lab + ['stop'] + options)
            run.command('lab-repeat-stop-' + str(signum), lab + ['stop'] + options)
            run.command('lab-stopped-' + str(signum), lab + ['status'] + options, allowed=(1,))
            stopped = json.loads((run.out / ('lab-stopped-' + str(signum) + '.log')).read_text())
            assert stopped['state'] == 'stopped' and stopped['processes'] == [], stopped
            free_ports()
            observations.append({'name': 'lab-service-signal', 'signal': signum, 'pid': owned['pid'],
                                 'active_socket_closed': True, 'repeat_start_stop': True, 'stopped': stopped})
        finally:
            run.command('lab-final-stop-' + str(signum), lab + ['stop'] + options)
    # Synthetic foreign listener: the runner must refuse BEFORE owning a device.
    record = run.out / 'foreign.json'
    with (run.out / 'foreign.log').open('w') as log:
        foreign = run.spawn([sys.executable, str(ROOT / 'scripts/tests/process_fixture.py'),
                             'foreign', str(record)], log)
    try:
        wait_for(record.exists, foreign, 'foreign listener')
        identity = run.capture(['/bin/ps', '-p', str(foreign.pid), '-o', 'lstart=,command='])
        for mode in ('simulator-stage1', 'simulator-stage4-webkit-privacy'):
            run.command('foreign-' + mode, [sys.executable, ROOT / 'scripts/verify', mode], allowed=(1,))
            text = (run.out / ('foreign-' + mode + '.log')).read_text()
            assert 'port 8787 unavailable; foreign listeners untouched' in text, text
            output = Path(next(s[10:] for s in text.splitlines() if s.startswith('Evidence: ')))
            assert not (output / 'simulator.json').exists(), 'foreign conflict created device'
            assert foreign.poll() is None, 'foreign process died'
            assert identity == run.capture(['/bin/ps', '-p', str(foreign.pid), '-o', 'lstart=,command=']), 'foreign identity changed'
            with socket.create_connection(('127.0.0.1', 8787), timeout=2) as connection:
                assert connection.recv(100) == b'PER85-synthetic-foreign\n', 'foreign response changed'
        observations.append({'name': 'foreign-port-preservation', 'pid': foreign.pid,
                             'same_identity': True, 'same_response': True, 'no_device_created': True})
    finally:
        run.stop_child(foreign)
        free_ports()
    save(run.out / 'result.json', {'stage5_operations': 'PASS', 'observations': observations,
                                  'final_acceptance': False})
    print(f'PASS Stage5 operations; evidence: {run.out}')


if __name__ == '__main__':
    run_gate()
