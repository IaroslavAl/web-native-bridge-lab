"""Opt-in real subprocess tree for runner cleanup tests; never invokes a suite."""
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time

if __name__ == '__main__':
    mode, record = sys.argv[1:3]
    if mode == 'foreign':
        with socket.socket() as listener:
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind(('127.0.0.1', 8787))
            listener.listen()
            listener.settimeout(30)
            Path(record).write_text(json.dumps({'pid': os.getpid(), 'port': 8787}))
            for _ in range(10):
                connection, _ = listener.accept()
                with connection:
                    connection.sendall(b'PER85-synthetic-foreign\n')
    elif mode == 'listener':
        signal.signal(signal.SIGTERM, signal.SIG_IGN)  # require bounded escalation
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen()
            Path(record).write_text(json.dumps({'pid': os.getpid(), 'port': listener.getsockname()[1]}))
            time.sleep(30)  # safety bound even on a broken test harness
    else:
        subprocess.Popen([sys.executable, __file__, 'listener', record])
        deadline = time.monotonic() + 5
        while not Path(record).exists():
            if time.monotonic() > deadline:
                sys.exit(9)
            time.sleep(0.01)
        if mode == 'failure':
            sys.exit(7)
        time.sleep(30)
