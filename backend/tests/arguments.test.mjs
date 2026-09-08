import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const script = path.join(repo, 'backend/server.mjs');

async function reservedPort(t) {
  const server = net.createServer();
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const port = server.address().port;
  // Invalid arguments must fail before listening: keep reservations throughout.
  t.after(() => new Promise((resolve) => server.close(resolve)));
  return port;
}

test('server rejects invalid ports and ownership bindings before listening', async (t) => {
  const webPort = await reservedPort(t);
  const apiPort = await reservedPort(t);
  const defaults = {
    '--web-port': String(webPort), '--api-port': String(apiPort),
    '--web-root': path.join(repo, '.artifacts/argument-tests/dist'),
    '--state-dir': path.join(repo, '.artifacts/argument-tests/state'),
    '--repo-root': repo, '--token': 'a'.repeat(32),
  };
  const cases = [
    ...['-1', '65536', '0', '1.5', 'NaN', ''].map((value) => ({
      name: `web port ${JSON.stringify(value)}`, change: { '--web-port': value }, error: /invalid ports/,
    })),
    { name: 'same ports', change: { '--api-port': String(webPort) }, error: /invalid ports/ },
    { name: 'foreign repository', change: { '--repo-root': path.dirname(repo) }, error: /repository root/ },
    { name: 'missing repository', omit: '--repo-root', error: /repository root/ },
    { name: 'invalid token', change: { '--token': 'bad' }, error: /invalid ownership token/ },
    { name: 'relative state', change: { '--state-dir': 'relative' }, error: /state dir must be absolute/ },
    { name: 'relative assets', change: { '--web-root': 'relative' }, error: /web root must be absolute/ },
    { name: 'duplicate option', extra: ['--token', 'b'.repeat(32)], error: /invalid server arguments/ },
    { name: 'unknown option', extra: ['--host', '0.0.0.0'], error: /invalid server arguments/ },
  ];
  for (const item of cases) {
    await t.test(item.name, async () => {
      const options = { ...defaults, ...item.change };
      if (item.omit) delete options[item.omit];
      await assert.rejects(execFileAsync(process.execPath, [script,
        ...Object.entries(options).flat(), ...(item.extra ?? []),
      ], { timeout: 1000 }), (error) => {
        assert.equal(error.code, 1, `${item.name}: exit code; stderr=${error.stderr}`);
        assert.match(error.stderr, item.error, `${item.name}: diagnostic`);
        return true;
      });
    });
  }
});
