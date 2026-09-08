import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdir, mkdtemp, rm, symlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

import { createLabServer } from '../server.mjs';

async function withLab(run) {
  const testRoot = fileURLToPath(new URL('../../.artifacts/backend-tests/', import.meta.url));
  await mkdir(testRoot, { recursive: true });
  const root = await mkdtemp(path.join(testRoot, 'fixtures-'));
  const webRoot = path.join(root, 'dist');
  const logs = [];
  const lab = createLabServer({
    host: '127.0.0.1',
    webPort: 0,
    apiPort: 0,
    webRoot,
    log: (line) => logs.push(line),
  });

  try {
    const addresses = await lab.start();
    await run({ ...addresses, lab, logs, root, webRoot });
  } finally {
    await lab.close();
    await rm(root, { recursive: true, force: true });
  }
}

function rawRequest(url, requestPath) {
  return new Promise((resolve, reject) => {
    const target = new URL(url);
    const request = http.request({
      host: target.hostname,
      port: target.port,
      method: 'GET',
      path: requestPath,
    }, (response) => {
      const chunks = [];
      response.on('data', (chunk) => chunks.push(chunk));
      response.on('end', () => resolve({
        status: response.statusCode,
        body: Buffer.concat(chunks).toString('utf8'),
      }));
    });
    request.once('error', reject);
    request.end();
  });
}

test('serves deterministic catalog data from an isolated API listener', async () => {
  await withLab(async ({ apiUrl }) => {
    const response = await fetch(`${apiUrl}/api/catalog?category=books`, {
      headers: { accept: 'application/json', 'x-lab-tag': 'scenario-a' },
    });

    assert.equal(response.status, 200);
    assert.equal(response.headers.get('content-type'), 'application/json; charset=utf-8');
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal(response.headers.get('access-control-allow-origin'), null);
    assert.deepEqual(await response.json(), {
      items: [{ sku: 'notebook', title: 'Notebook' }],
      total: 1,
    });
  });
});

test('reports listener health independently from web asset availability', async () => {
  await withLab(async ({ webUrl, apiUrl }) => {
    const webHealth = await fetch(`${webUrl}/healthz`);
    const apiHealth = await fetch(`${apiUrl}/healthz`);
    const missingAssets = await fetch(`${webUrl}/`);

    assert.deepEqual(await webHealth.json(), { service: 'web', protocol: 1 });
    assert.deepEqual(await apiHealth.json(), { service: 'api', protocol: 1 });
    assert.equal(missingAssets.status, 503);
    assert.equal(missingAssets.headers.get('cache-control'), 'no-store');
    assert.match(missingAssets.headers.get('content-security-policy'), /connect-src 'none'/);
  });
});

test('serves current static files with safe paths, MIME types, and CSP', async () => {
  await withLab(async ({ webUrl, root, webRoot }) => {
    await mkdir(webRoot);
    await writeFile(path.join(webRoot, 'index.html'), '<h1>variant A</h1>');
    await writeFile(path.join(webRoot, 'app.js'), 'document.title = "lab";');
    await writeFile(path.join(root, 'outside.txt'), 'outside-secret');
    await symlink(path.join(root, 'outside.txt'), path.join(webRoot, 'escape.txt'));

    const first = await fetch(`${webUrl}/`);
    assert.equal(first.status, 200);
    assert.equal(first.headers.get('content-type'), 'text/html; charset=utf-8');
    assert.equal(await first.text(), '<h1>variant A</h1>');

    await writeFile(path.join(webRoot, 'index.html'), '<h1>variant B</h1>');
    const replaced = await fetch(`${webUrl}/`);
    assert.equal(await replaced.text(), '<h1>variant B</h1>');

    const javascript = await fetch(`${webUrl}/app.js`);
    assert.equal(javascript.headers.get('content-type'), 'text/javascript; charset=utf-8');

    const traversal = await rawRequest(webUrl, '/%2e%2e/outside.txt');
    assert.notEqual(traversal.status, 200);
    assert.doesNotMatch(traversal.body, /outside-secret/);

    const escaped = await fetch(`${webUrl}/escape.txt`);
    assert.notEqual(escaped.status, 200);
    assert.match(escaped.headers.get('content-security-policy'), /default-src 'none'/);
    assert.doesNotMatch(await escaped.text(), /outside-secret/);

    const missing = await fetch(`${webUrl}/missing.txt`);
    assert.equal(missing.status, 404);
    assert.match(missing.headers.get('content-security-policy'), /default-src 'none'/);
  });
});

test('implements catalog and quote success and validation contracts', async () => {
  await withLab(async ({ apiUrl }) => {
    const empty = await fetch(`${apiUrl}/api/catalog?category=music`);
    assert.deepEqual(await empty.json(), { items: [], total: 0 });

    const quote = await fetch(`${apiUrl}/api/quote`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ sku: 'notebook', quantity: 2 }),
    });
    assert.equal(quote.status, 200);
    assert.deepEqual(await quote.json(), {
      quote: {
        sku: 'notebook',
        quantity: 2,
        totalMinor: 1200,
        currency: 'USD',
      },
    });

    for (const body of [
      JSON.stringify({ sku: 'unknown', quantity: 2 }),
      JSON.stringify({ sku: 'notebook', quantity: 0 }),
      JSON.stringify({ sku: 'notebook', quantity: 6 }),
      JSON.stringify({ sku: 'notebook', quantity: 1.5 }),
      JSON.stringify({ sku: 'notebook' }),
    ]) {
      const invalid = await fetch(`${apiUrl}/api/quote`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body,
      });
      assert.equal(invalid.status, 422, `quote body ${body}`);
      assert.deepEqual(await invalid.json(), {
        error: {
          code: 'INVALID_QUANTITY',
          message: 'Quantity must be 1 to 5',
        },
      });
    }

    const malformed = await fetch(`${apiUrl}/api/quote`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{',
    });
    assert.equal(malformed.status, 400);
  });
});

test('returns exact echo, HTTP, business, and malformed JSON fixtures', async () => {
  await withLab(async ({ apiUrl }) => {
    const echoText = 'opaque <text> — unchanged';
    const echo = await fetch(`${apiUrl}/fixtures/echo`, {
      method: 'POST',
      headers: { 'content-type': 'text/plain' },
      body: echoText,
    });
    assert.equal(echo.status, 200);
    assert.equal(echo.headers.get('content-type'), 'text/plain; charset=utf-8');
    assert.equal(await echo.text(), echoText);

    const httpError = await fetch(`${apiUrl}/fixtures/http-error`);
    assert.equal(httpError.status, 503);
    assert.deepEqual(await httpError.json(), {
      error: { code: 'UNAVAILABLE', message: 'Try later' },
    });

    const businessError = await fetch(`${apiUrl}/fixtures/business-error`);
    assert.equal(businessError.status, 200);
    assert.deepEqual(await businessError.json(), {
      error: { code: 'OUT_OF_STOCK', message: 'Not available' },
    });

    const malformed = await fetch(`${apiUrl}/fixtures/malformed-json`);
    assert.equal(malformed.status, 200);
    assert.equal(await malformed.text(), '{"broken":');
  });
});

test('bounds request bodies and distinguishes unknown routes from wrong methods', async () => {
  await withLab(async ({ apiUrl }) => {
    const exactLimit = await fetch(`${apiUrl}/fixtures/echo`, {
      method: 'POST',
      headers: { 'content-type': 'text/plain' },
      body: 'x'.repeat(65_536),
    });
    assert.equal(exactLimit.status, 200);
    assert.equal((await exactLimit.text()).length, 65_536);

    const tooLarge = await fetch(`${apiUrl}/fixtures/echo`, {
      method: 'POST',
      headers: { 'content-type': 'text/plain' },
      body: 'x'.repeat(65_537),
    });
    assert.equal(tooLarge.status, 413);

    const wrongMethod = await fetch(`${apiUrl}/api/catalog`, { method: 'POST', body: '' });
    assert.equal(wrongMethod.status, 405);
    const unknown = await fetch(`${apiUrl}/does-not-exist`);
    assert.equal(unknown.status, 404);
  });
});

test('validates delay input and clears delayed work when the client cancels', async () => {
  await withLab(async ({ apiUrl, logs }) => {
    const delayed = await fetch(`${apiUrl}/fixtures/delay?ms=5&label=slow`, {
      headers: { 'x-lab-tag': 'delay-case' },
    });
    assert.deepEqual(await delayed.json(), { label: 'slow', delayedMs: 5 });

    for (const query of ['ms=-1&label=slow', 'ms=30001&label=slow', 'ms=1&label=', 'ms=1&label=%C3%A9']) {
      const invalid = await fetch(`${apiUrl}/fixtures/delay?${query}`);
      assert.equal(invalid.status, 400, `delay query ${query}`);
    }

    const controller = new AbortController();
    const pending = fetch(`${apiUrl}/fixtures/delay?ms=30000&label=private-query`, {
      signal: controller.signal,
    });
    setTimeout(() => controller.abort(), 20);
    await assert.rejects(pending, { name: 'AbortError' });
    await new Promise((resolve) => setTimeout(resolve, 30));

    assert.ok(logs.some((line) => line.includes('GET /fixtures/delay 200 tag=delay-case')));
    assert.ok(logs.some((line) => line.includes('GET /fixtures/delay connection-close')));
    assert.ok(logs.every((line) => !line.includes('private-query')));
  });
});

test('returns redirect fixtures without following them server-side', async () => {
  await withLab(async ({ apiUrl, webPort }) => {
    const same = await fetch(`${apiUrl}/fixtures/redirect-same`, { redirect: 'manual' });
    assert.equal(same.status, 302);
    assert.equal(same.headers.get('location'), '/api/catalog?category=books');

    const cross = await fetch(`${apiUrl}/fixtures/redirect-cross`, { redirect: 'manual' });
    assert.equal(cross.status, 302);
    assert.equal(cross.headers.get('location'), `http://127.0.0.1:${webPort}/healthz`);

    const loop = await fetch(`${apiUrl}/fixtures/redirect-loop`, { redirect: 'manual' });
    assert.equal(loop.status, 307);
    assert.equal(loop.headers.get('location'), '/fixtures/redirect-loop');
  });
});

test('streams bounded large fixture without Content-Length', async () => {
  await withLab(async ({ apiUrl }) => {
    const response = await fetch(`${apiUrl}/fixtures/large?bytes=1048577`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('content-length'), null);
    assert.equal((await response.arrayBuffer()).byteLength, 1_048_577);

    for (const value of ['-1', '1048578', '1.5', 'abc']) {
      const invalid = await fetch(`${apiUrl}/fixtures/large?bytes=${value}`);
      assert.equal(invalid.status, 400, `large bytes ${value}`);
    }
  });
});

test('returns invalid UTF-8, binary, and filtered-header test inputs exactly', async () => {
  await withLab(async ({ apiUrl }) => {
    const invalidUtf8 = await fetch(`${apiUrl}/fixtures/invalid-utf8`);
    assert.deepEqual(Buffer.from(await invalidUtf8.arrayBuffer()), Buffer.from([0xc3, 0x28]));

    const binary = await fetch(`${apiUrl}/fixtures/binary`);
    assert.equal(binary.headers.get('content-type'), 'application/octet-stream');
    assert.deepEqual(Buffer.from(await binary.arrayBuffer()), Buffer.from([0x00, 0x01]));

    const headers = await fetch(`${apiUrl}/fixtures/headers`);
    assert.equal(await headers.text(), 'headers');
    assert.equal(headers.headers.get('x-lab-tag'), 'fixture');
    assert.equal(headers.headers.get('set-cookie'), 'synthetic=1');
    assert.equal(headers.headers.get('x-private'), 'synthetic');
  });
});

test('echoes only valid x-lab-tag values and never grants CORS', async () => {
  await withLab(async ({ apiUrl }) => {
    const valid = await fetch(`${apiUrl}/api/catalog?category=books`, {
      headers: { 'x-lab-tag': 'printable-tag' },
    });
    assert.equal(valid.headers.get('x-lab-tag'), 'printable-tag');
    assert.equal(valid.headers.get('access-control-allow-origin'), null);

    const invalid = await fetch(`${apiUrl}/api/catalog?category=books`, {
      headers: { 'x-lab-tag': 'x'.repeat(129) },
    });
    assert.equal(invalid.headers.get('x-lab-tag'), null);
  });
});
