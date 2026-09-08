import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir, mkdtemp, realpath, rm, writeFile } from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';
import { promisify } from 'node:util';
import { createLabServer } from '../server.mjs';

const execFileAsync = promisify(execFile);
async function descriptors(file) {
  const { stdout } = await execFileAsync('/usr/sbin/lsof', ['-p', String(process.pid), '-Fn']);
  return stdout.split('\n').filter((line) => line === `n${file}`).length;
}

for (const mode of ['client abort', 'server shutdown']) {
  test(`static source descriptor closes after ${mode}`, { timeout: 15_000 }, async () => {
    const base = fileURLToPath(new URL('../../.artifacts/backend-tests/', import.meta.url));
    await mkdir(base, { recursive: true });
    const root = await mkdtemp(path.join(base, 'static-'));
    const file = path.join(await realpath(root), 'large.txt');
    const bytes = 16 * 1024 * 1024;
    await writeFile(file, Buffer.alloc(bytes, 'x'));
    const lab = createLabServer({ webPort: 0, apiPort: 0, webRoot: root });
    let client;
    try {
      const { webUrl } = await lab.start();
      assert.equal(await descriptors(file), 0, 'baseline source descriptors');
      const full = await fetch(`${webUrl}/large.txt`);
      assert.equal((await full.arrayBuffer()).byteLength, bytes, 'full download byte count');
      assert.equal(await descriptors(file), 0, 'full download closes source');
      for (let index = 0; index < (mode === 'client abort' ? 5 : 1); index += 1) {
        client = await new Promise((resolve, reject) => {
          const request = http.get(`${webUrl}/large.txt`, (response) => {
            response.on('error', () => {});
            response.once('data', () => {
              response.pause();
              resolve(response);
            });
          });
          request.once('error', reject);
        });
        if (mode === 'client abort') client.destroy();
      }
      if (mode === 'server shutdown') {
        assert.equal(await descriptors(file), 1, 'paused download has an active source');
        await lab.close();
      }
      let count;
      for (let attempt = 0; attempt < 10; attempt += 1) {
        count = await descriptors(file);
        if (count === 0) break;
        await delay(20);
      }
      assert.equal(count, 0, `${mode} must close actual source descriptors`);
      await lab.close();
      assert.equal(await descriptors(file), 0, 'no source remains after close resolves');
    } finally {
      client?.destroy();
      await lab.close();
      await rm(root, { recursive: true, force: true });
    }
  });
}
