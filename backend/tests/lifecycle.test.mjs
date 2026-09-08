import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import http from 'node:http';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { promisify } from 'node:util';

import { createLabServer } from '../server.mjs';

const execFileAsync = promisify(execFile);
const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const LAB_SCRIPT = path.join(REPO_ROOT, 'scripts/lab');
const SERVER_SCRIPT = path.join(REPO_ROOT, 'backend', 'server.mjs');
const TEST_ROOT = path.join(REPO_ROOT, '.artifacts', 'backend-tests');
await mkdir(TEST_ROOT, { recursive: true });

async function runLab(command, options) {
  const args = [
    command,
    '--state-dir', options.stateDir,
    '--web-port', String(options.webPort),
    '--api-port', String(options.apiPort),
    '--web-root', options.webRoot,
  ];
  try {
    const result = await execFileAsync(LAB_SCRIPT, args, {
      cwd: options.cwd,
      timeout: 15_000,
    });
    return { code: 0, ...result };
  } catch (error) {
    return {
      code: error.code,
      stdout: error.stdout ?? '',
      stderr: error.stderr ?? error.message,
    };
  }
}

function listen(server, port = 0) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', () => resolve(server.address().port));
  });
}

function close(server) {
  return new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
}

async function getFreePort() {
  const server = net.createServer();
  const port = await listen(server);
  await close(server);
  return port;
}

async function portIsFree(port) {
  const server = net.createServer();
  try {
    await listen(server, port);
    return true;
  } catch {
    return false;
  } finally {
    if (server.listening) await close(server);
  }
}

async function isolatedOptions(root) {
  let webPort = await getFreePort();
  let apiPort = await getFreePort();
  while (apiPort === webPort) apiPort = await getFreePort();
  return {
    stateDir: path.join(root, 'state'),
    webRoot: path.join(root, 'dist'),
    webPort,
    apiPort,
    cwd: os.tmpdir(),
  };
}

test('status from another cwd reports stopped state as JSON', async () => {
  const root = await mkdtemp(path.join(TEST_ROOT, 'lifecycle-'));
  const options = await isolatedOptions(root);

  try {
    const status = await runLab('status', options);
    assert.equal(status.code, 1);
    assert.equal(status.stderr, '');
    assert.deepEqual(JSON.parse(status.stdout), {
      state: 'stopped',
      webPort: options.webPort,
      apiPort: options.apiPort,
      assetsAvailable: false,
      processes: [],
    });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('start, status, and stop are idempotent and stop active delayed work', async () => {
  const root = await mkdtemp(path.join(TEST_ROOT, 'lifecycle-'));
  const options = await isolatedOptions(root);
  await mkdir(options.webRoot);
  await writeFile(path.join(options.webRoot, 'index.html'), '<h1>lab</h1>');

  try {
    const started = await runLab('start', options);
    assert.equal(started.code, 0, `start stderr: ${started.stderr}`);
    const repeatedStart = await runLab('start', options);
    assert.equal(repeatedStart.code, 0, `repeated start stderr: ${repeatedStart.stderr}`);

    const status = await runLab('status', options);
    assert.equal(status.code, 0, `status stderr: ${status.stderr}`);
    const state = JSON.parse(status.stdout);
    assert.equal(state.state, 'running', 'status.state');
    assert.equal(state.webPort, options.webPort, 'status.webPort');
    assert.equal(state.apiPort, options.apiPort, 'status.apiPort');
    assert.equal(state.assetsAvailable, true, 'status.assetsAvailable');
    assert.equal(state.processes.length, 1, 'status.processes.length');
    assert.equal(Number.isInteger(state.processes[0].pid), true, 'process.pid');
    assert.equal(typeof state.processes[0].startIdentity, 'string', 'process.startIdentity');
    assert.equal(state.processes[0].scriptPath, path.join(REPO_ROOT, 'backend', 'server.mjs'), 'process.scriptPath');
    assert.equal(state.processes[0].repoRoot, REPO_ROOT, 'process.repoRoot');

    const health = await fetch(`http://127.0.0.1:${options.apiPort}/healthz`);
    assert.deepEqual(await health.json(), { service: 'api', protocol: 1 });

    const delayed = fetch(`http://127.0.0.1:${options.apiPort}/fixtures/delay?ms=30000&label=shutdown`)
      .then(() => null, (error) => error);
    await new Promise((resolve) => setTimeout(resolve, 30));
    const stopped = await runLab('stop', options);
    assert.equal(stopped.code, 0, `stop stderr: ${stopped.stderr}`);
    assert.ok(await delayed instanceof Error, 'active delayed request connection closed');
    assert.equal(await portIsFree(options.webPort), true, 'web port released');
    assert.equal(await portIsFree(options.apiPort), true, 'API port released');
    assert.throws(() => process.kill(state.processes[0].pid, 0), { code: 'ESRCH' }, 'owned child exited');

    const repeatedStop = await runLab('stop', options);
    assert.equal(repeatedStop.code, 0, `repeated stop stderr: ${repeatedStop.stderr}`);
  } finally {
    await runLab('stop', options);
    await rm(root, { recursive: true, force: true });
  }
});

test('concurrent lifecycle calls serialize and preserve an unrelated listener', async () => {
  const root = await mkdtemp(path.join(TEST_ROOT, 'lifecycle-'));
  const options = await isolatedOptions(root);
  const foreign = http.createServer((_request, response) => response.end('foreign-alive'));
  const foreignPort = await listen(foreign);

  try {
    const starts = await Promise.all([runLab('start', options), runLab('start', options)]);
    assert.deepEqual(starts.map((result) => result.code), [0, 0], 'concurrent start exit codes');

    const status = await runLab('status', options);
    assert.equal(JSON.parse(status.stdout).processes.length, 1, 'single owned process');

    const stops = await Promise.all([runLab('stop', options), runLab('stop', options)]);
    assert.deepEqual(stops.map((result) => result.code), [0, 0], 'concurrent stop exit codes');

    const foreignResponse = await fetch(`http://127.0.0.1:${foreignPort}/`);
    assert.equal(await foreignResponse.text(), 'foreign-alive');
  } finally {
    await runLab('stop', options);
    await close(foreign);
    await rm(root, { recursive: true, force: true });
  }
});

test('foreign port conflict fails without signalling the foreign process', async () => {
  const root = await mkdtemp(path.join(TEST_ROOT, 'lifecycle-'));
  const options = await isolatedOptions(root);
  const foreign = http.createServer((_request, response) => response.end('still-owned-elsewhere'));
  await listen(foreign, options.webPort);

  try {
    const start = await runLab('start', options);
    assert.equal(start.code, 1, `start conflict exit code; stderr: ${start.stderr}`);
    assert.match(start.stderr, /web port.*occupied/i);
    assert.equal(await portIsFree(options.apiPort), true, 'API port remains free');

    const status = await runLab('status', options);
    assert.equal(status.code, 1);
    assert.equal(JSON.parse(status.stdout).state, 'conflict', 'status.state');

    const stop = await runLab('stop', options);
    assert.equal(stop.code, 1, 'foreign stop exit code');
    assert.match(stop.stderr, /without verified lab ownership/i);

    const response = await fetch(`http://127.0.0.1:${options.webPort}/`);
    assert.equal(await response.text(), 'still-owned-elsewhere');
  } finally {
    await close(foreign);
    await rm(root, { recursive: true, force: true });
  }
});

test('stale PID-reuse state is never treated as owned or signalled', async () => {
  const root = await mkdtemp(path.join(TEST_ROOT, 'lifecycle-'));
  const options = await isolatedOptions(root);

  try {
    const start = await runLab('start', options);
    assert.equal(start.code, 0, `start stderr: ${start.stderr}`);
    const statePath = path.join(options.stateDir, 'state.json');
    const previous = JSON.parse(await readFile(statePath, 'utf8'));
    const stopped = await runLab('stop', options);
    assert.equal(stopped.code, 0, `stop stderr: ${stopped.stderr}`);

    await mkdir(options.stateDir, { recursive: true });
    await writeFile(statePath, `${JSON.stringify({
      ...previous,
      pid: process.pid,
      startIdentity: 'definitely-not-this-process',
    })}\n`);

    const status = await runLab('status', options);
    assert.equal(status.code, 1);
    const stale = JSON.parse(status.stdout);
    assert.equal(stale.state, 'stale', 'status.state');
    assert.deepEqual(stale.processes, [], 'status.processes');

    const staleStop = await runLab('stop', options);
    assert.equal(staleStop.code, 0, `stale stop stderr: ${staleStop.stderr}`);
    await assert.rejects(readFile(statePath, 'utf8'), { code: 'ENOENT' });
  } finally {
    await runLab('stop', options);
    await rm(root, { recursive: true, force: true });
  }
});

test('direct server startup rolls back its first listener when the second bind fails', async () => {
  const root = await mkdtemp(path.join(TEST_ROOT, 'lifecycle-'));
  const webPort = await getFreePort();
  const occupiedApi = http.createServer((_request, response) => response.end('foreign-api'));
  const apiPort = await listen(occupiedApi);
  const lab = createLabServer({
    webPort,
    apiPort,
    webRoot: path.join(root, 'dist'),
  });

  try {
    await assert.rejects(lab.start(), { code: 'EADDRINUSE' });
    assert.equal(await portIsFree(webPort), true, 'partially started web listener released');
    const response = await fetch(`http://127.0.0.1:${apiPort}/`);
    assert.equal(await response.text(), 'foreign-api');
  } finally {
    await lab.close();
    await close(occupiedApi);
    await rm(root, { recursive: true, force: true });
  }
});

test('direct server startup rejects invalid lifecycle ownership arguments', async () => {
  const root = await mkdtemp(path.join(TEST_ROOT, 'lifecycle-'));
  const webPort = await getFreePort();
  let apiPort = await getFreePort();
  while (apiPort === webPort) apiPort = await getFreePort();

  try {
    await assert.rejects(
      execFileAsync(process.execPath, [
        SERVER_SCRIPT,
        '--web-port', String(webPort),
        '--api-port', String(apiPort),
        '--web-root', path.join(root, 'dist'),
        '--state-dir', path.join(root, 'state'),
        '--token', 'not-a-token',
        '--repo-root', REPO_ROOT,
      ], { timeout: 1_000 }),
      (error) => {
        assert.equal(error.code, 1);
        assert.match(error.stderr, /invalid ownership token/i);
        return true;
      },
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('ownership requires an exact token, command and start identity, not a PID or substring', async () => {
  const root = await mkdtemp(path.join(TEST_ROOT, 'lifecycle-'));
  const options = await isolatedOptions(root);
  const statePath = path.join(options.stateDir, 'state.json');
  let original;
  try {
    const started = await runLab('start', options);
    assert.equal(started.code, 0, started.stderr);
    original = await readFile(statePath, 'utf8');
    const state = JSON.parse(original);
    const { stdout } = await execFileAsync('/bin/ps', ['-o', 'lstart=', '-p', String(process.pid)]);
    for (const change of [
      { token: state.token.slice(0, -1) },
      { token: '' },
      { startIdentity: 'reused-pid-start' },
      { pid: process.pid, startIdentity: stdout.trim() },
    ]) {
      await writeFile(statePath, JSON.stringify({ ...state, ...change }));
      const status = await runLab('status', options);
      assert.equal(status.code, 1, `tampered ${Object.keys(change)}: status exit`);
      assert.deepEqual(JSON.parse(status.stdout).processes, [], 'unverified process not claimed');
      const stop = await runLab('stop', options);
      assert.equal(stop.code, 1, 'unverified occupied service cannot be stopped');
      const health = await fetch(`http://127.0.0.1:${options.apiPort}/healthz`);
      assert.equal(health.status, 200, 'original child remains alive');
    }
  } finally {
    if (original) await writeFile(statePath, original);
    const stop = await runLab('stop', options);
    assert.equal(stop.code, 0, stop.stderr);
    await rm(root, { recursive: true, force: true });
  }
});

test('stale files recover and a live configuration mismatch fails safely', async () => {
  const root = await mkdtemp(path.join(TEST_ROOT, 'lifecycle-'));
  const options = await isolatedOptions(root);
  try {
    await mkdir(path.join(options.stateDir, '.lock'), { recursive: true });
    await writeFile(path.join(options.stateDir, '.lock/owner.json'), JSON.stringify({ pid: process.pid, startIdentity: 'stale' }));
    await writeFile(path.join(options.stateDir, 'state.json'), '{malformed');
    const start = await runLab('start', options);
    assert.equal(start.code, 0, start.stderr);
    const mismatch = { ...options, webRoot: path.join(root, 'different-dist') };
    for (const command of ['start', 'status', 'stop']) {
      const result = await runLab(command, mismatch);
      assert.equal(result.code, 1, `mismatched ${command} exit code`);
    }
    assert.equal((await runLab('status', options)).code, 0, 'original configuration stays healthy');
  } finally {
    assert.equal((await runLab('stop', options)).code, 0, 'cleanup stop');
    assert.equal(await portIsFree(options.webPort), true, 'cleanup web port');
    assert.equal(await portIsFree(options.apiPort), true, 'cleanup API port');
    await rm(root, { recursive: true, force: true });
  }
});
