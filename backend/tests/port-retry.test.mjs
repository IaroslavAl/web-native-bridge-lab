import assert from 'node:assert/strict';
import http from 'node:http';
import test from 'node:test';
import { retryBindConflicts } from './support/port-retry.mjs';

function listen(server, port = 0) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', () => resolve(server.address().port));
  });
}
const close = (server) => new Promise((resolve) => server.close(resolve));

test('bind retry allocates fresh listeners and preserves a forced foreign collision', async () => {
  const foreign = http.createServer((_request, response) => response.end('foreign-alive'));
  const occupied = await listen(foreign);
  const attempts = [];
  try {
    await retryBindConflicts(async (attempt) => {
      attempts.push(attempt);
      const server = http.createServer((_request, response) => response.end('owned'));
      try {
        const port = await listen(server, attempt === 1 ? occupied : 0);
        assert.notEqual(port, occupied, 'retry gets a new isolated port');
        assert.equal(await (await fetch(`http://127.0.0.1:${port}`)).text(), 'owned');
      } finally {
        if (server.listening) await close(server);
      }
    });
    assert.deepEqual(attempts, [1, 2]);
    assert.equal(await (await fetch(`http://127.0.0.1:${occupied}`)).text(), 'foreign-alive');
  } finally {
    await close(foreign);
  }
});

test('bind retry exhaustion is bounded and preserves its bind error cause', async () => {
  const foreign = http.createServer();
  const occupied = await listen(foreign);
  let attempts = 0;
  try {
    await assert.rejects(retryBindConflicts(async () => {
      attempts += 1;
      await listen(http.createServer(), occupied);
    }), (error) => {
      assert.match(error.message, /bind conflicts exhausted after 3 attempts/);
      assert.equal(error.cause.code, 'EADDRINUSE');
      return true;
    });
    assert.equal(attempts, 3);
    assert.equal(foreign.listening, true);
  } finally {
    await close(foreign);
  }
});

test('bind retry does not repeat assertion or ownership failures', async () => {
  for (const failure of [new assert.AssertionError({ message: 'EADDRINUSE assertion' }), new Error('ownership mismatch')]) {
    let attempts = 0;
    await assert.rejects(retryBindConflicts(async () => {
      attempts += 1;
      throw failure;
    }), (error) => error === failure);
    assert.equal(attempts, 1);
  }
});
