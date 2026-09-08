#!/usr/bin/env node

import { createReadStream } from 'node:fs';
import { realpath, stat } from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const BODY_LIMIT = 65_536;
const LARGE_FIXTURE_LIMIT = 1_048_577;
const HOST = '127.0.0.1';
const CSP = "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'";
const KNOWN_API_PATHS = new Set([
  '/healthz',
  '/api/catalog',
  '/api/quote',
  '/fixtures/echo',
  '/fixtures/http-error',
  '/fixtures/malformed-json',
  '/fixtures/business-error',
  '/fixtures/delay',
  '/fixtures/redirect-same',
  '/fixtures/redirect-cross',
  '/fixtures/redirect-loop',
  '/fixtures/large',
  '/fixtures/invalid-utf8',
  '/fixtures/binary',
  '/fixtures/headers',
]);

const MIME_TYPES = new Map([
  ['.css', 'text/css; charset=utf-8'],
  ['.html', 'text/html; charset=utf-8'],
  ['.ico', 'image/x-icon'],
  ['.jpeg', 'image/jpeg'],
  ['.jpg', 'image/jpeg'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.map', 'application/json; charset=utf-8'],
  ['.png', 'image/png'],
  ['.svg', 'image/svg+xml'],
  ['.txt', 'text/plain; charset=utf-8'],
  ['.webp', 'image/webp'],
]);

function validLabTag(value) {
  return typeof value === 'string' && /^[\x20-\x7e]{1,128}$/.test(value);
}

function responseHeaders(request, contentType, extra = {}) {
  const headers = {
    'cache-control': 'no-store',
    ...(contentType ? { 'content-type': contentType } : {}),
    ...extra,
  };
  if (validLabTag(request.headers['x-lab-tag']) && !('x-lab-tag' in headers)) {
    headers['x-lab-tag'] = request.headers['x-lab-tag'];
  }
  return headers;
}

function logResult(log, request, url, outcome) {
  const tag = validLabTag(request.headers['x-lab-tag'])
    ? request.headers['x-lab-tag']
    : '-';
  log(`${request.method ?? 'UNKNOWN'} ${url.pathname} ${outcome} tag=${tag}`);
}

function send(request, response, url, log, status, body, contentType, extra = {}) {
  response.writeHead(status, responseHeaders(request, contentType, extra));
  response.end(body);
  logResult(log, request, url, status);
}

function sendJson(request, response, url, log, status, value, extra = {}) {
  send(
    request,
    response,
    url,
    log,
    status,
    JSON.stringify(value),
    'application/json; charset=utf-8',
    extra,
  );
}

function sendError(request, response, url, log, status, code, message) {
  sendJson(request, response, url, log, status, { error: { code, message } });
}

function sendWebError(request, response, url, log, status, code, message) {
  sendJson(request, response, url, log, status, { error: { code, message } }, {
    'content-security-policy': CSP,
  });
}

function listen(server, host, port) {
  return new Promise((resolve, reject) => {
    const onError = (error) => {
      server.off('listening', onListening);
      reject(error);
    };
    const onListening = () => {
      server.off('error', onError);
      resolve();
    };
    server.once('error', onError);
    server.once('listening', onListening);
    server.listen(port, host);
  });
}

function closeServer(server) {
  return new Promise((resolve, reject) => {
    if (!server.listening) {
      resolve();
      return;
    }
    server.close((error) => (error ? reject(error) : resolve()));
    server.closeAllConnections();
  });
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    let bytes = 0;
    let tooLarge = false;
    const chunks = [];
    request.on('data', (chunk) => {
      bytes += chunk.length;
      if (bytes > BODY_LIMIT) {
        tooLarge = true;
        return;
      }
      chunks.push(chunk);
    });
    request.once('aborted', () => reject(new Error('request aborted')));
    request.once('error', reject);
    request.once('end', () => resolve({
      tooLarge,
      body: tooLarge ? null : Buffer.concat(chunks).toString('utf8'),
    }));
  });
}

function parseBoundedInteger(value, maximum) {
  if (typeof value !== 'string' || !/^(0|[1-9]\d*)$/.test(value)) return null;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed <= maximum ? parsed : null;
}

function isValidDelayLabel(value) {
  return typeof value === 'string' && /^[\x20-\x7e]{1,32}$/.test(value);
}

function streamLarge(request, response, url, log, bytes) {
  response.writeHead(200, responseHeaders(request, 'text/plain; charset=utf-8'));
  let remaining = bytes;
  const writeChunk = () => {
    while (remaining > 0) {
      const size = Math.min(65_536, remaining);
      remaining -= size;
      if (!response.write('x'.repeat(size))) {
        response.once('drain', writeChunk);
        return;
      }
    }
    response.end();
    logResult(log, request, url, 200);
  };
  writeChunk();
}

async function handleApi(request, response, webPort, log, delayTimers) {
  let url;
  try {
    url = new URL(request.url ?? '/', `http://${HOST}`);
  } catch {
    url = new URL('/', `http://${HOST}`);
    sendError(request, response, url, log, 400, 'BAD_REQUEST', 'Invalid request target');
    return;
  }

  if (!KNOWN_API_PATHS.has(url.pathname)) {
    sendError(request, response, url, log, 404, 'NOT_FOUND', 'Not found');
    return;
  }

  const postOnly = url.pathname === '/api/quote' || url.pathname === '/fixtures/echo';
  if ((postOnly && request.method !== 'POST') || (!postOnly && request.method !== 'GET')) {
    sendError(request, response, url, log, 405, 'METHOD_NOT_ALLOWED', 'Method not allowed');
    return;
  }

  if (url.pathname === '/healthz') {
    sendJson(request, response, url, log, 200, { service: 'api', protocol: 1 });
    return;
  }

  if (url.pathname === '/api/catalog') {
    const books = url.searchParams.get('category') === 'books';
    sendJson(request, response, url, log, 200, {
      items: books ? [{ sku: 'notebook', title: 'Notebook' }] : [],
      total: books ? 1 : 0,
    });
    return;
  }

  if (url.pathname === '/api/quote') {
    const { tooLarge, body } = await readBody(request);
    if (tooLarge) {
      sendError(request, response, url, log, 413, 'REQUEST_TOO_LARGE', 'Request body too large');
      return;
    }
    let input;
    try {
      input = JSON.parse(body);
    } catch {
      sendError(request, response, url, log, 400, 'BAD_JSON', 'Malformed JSON');
      return;
    }
    const valid = input
      && typeof input === 'object'
      && !Array.isArray(input)
      && Object.keys(input).length === 2
      && input.sku === 'notebook'
      && Number.isInteger(input.quantity)
      && input.quantity >= 1
      && input.quantity <= 5;
    if (!valid) {
      sendError(
        request,
        response,
        url,
        log,
        422,
        'INVALID_QUANTITY',
        'Quantity must be 1 to 5',
      );
      return;
    }
    sendJson(request, response, url, log, 200, {
      quote: {
        sku: 'notebook',
        quantity: input.quantity,
        totalMinor: input.quantity * 600,
        currency: 'USD',
      },
    });
    return;
  }

  if (url.pathname === '/fixtures/echo') {
    const { tooLarge, body } = await readBody(request);
    if (tooLarge) {
      sendError(request, response, url, log, 413, 'REQUEST_TOO_LARGE', 'Request body too large');
      return;
    }
    send(request, response, url, log, 200, body, 'text/plain; charset=utf-8');
    return;
  }

  if (url.pathname === '/fixtures/http-error') {
    sendError(request, response, url, log, 503, 'UNAVAILABLE', 'Try later');
    return;
  }
  if (url.pathname === '/fixtures/malformed-json') {
    send(request, response, url, log, 200, '{"broken":', 'application/json; charset=utf-8');
    return;
  }
  if (url.pathname === '/fixtures/business-error') {
    sendError(request, response, url, log, 200, 'OUT_OF_STOCK', 'Not available');
    return;
  }
  if (url.pathname === '/fixtures/delay') {
    const milliseconds = parseBoundedInteger(url.searchParams.get('ms'), 30_000);
    const label = url.searchParams.get('label');
    if (milliseconds === null || !isValidDelayLabel(label)) {
      sendError(request, response, url, log, 400, 'INVALID_DELAY', 'Invalid delay query');
      return;
    }
    let settled = false;
    const timer = setTimeout(() => {
      settled = true;
      delayTimers.delete(timer);
      sendJson(request, response, url, log, 200, { label, delayedMs: milliseconds });
    }, milliseconds);
    delayTimers.add(timer);
    response.once('close', () => {
      if (!settled) {
        clearTimeout(timer);
        delayTimers.delete(timer);
        logResult(log, request, url, 'connection-close');
      }
    });
    return;
  }
  if (url.pathname === '/fixtures/redirect-same') {
    send(request, response, url, log, 302, '', null, {
      location: '/api/catalog?category=books',
    });
    return;
  }
  if (url.pathname === '/fixtures/redirect-cross') {
    send(request, response, url, log, 302, '', null, {
      location: `http://${HOST}:${webPort}/healthz`,
    });
    return;
  }
  if (url.pathname === '/fixtures/redirect-loop') {
    send(request, response, url, log, 307, '', null, {
      location: '/fixtures/redirect-loop',
    });
    return;
  }
  if (url.pathname === '/fixtures/large') {
    const bytes = parseBoundedInteger(url.searchParams.get('bytes'), LARGE_FIXTURE_LIMIT);
    if (bytes === null) {
      sendError(request, response, url, log, 400, 'INVALID_SIZE', 'Invalid size query');
      return;
    }
    streamLarge(request, response, url, log, bytes);
    return;
  }
  if (url.pathname === '/fixtures/invalid-utf8') {
    send(request, response, url, log, 200, Buffer.from([0xc3, 0x28]), 'text/plain');
    return;
  }
  if (url.pathname === '/fixtures/binary') {
    send(request, response, url, log, 200, Buffer.from([0x00, 0x01]), 'application/octet-stream');
    return;
  }
  if (url.pathname === '/fixtures/headers') {
    send(request, response, url, log, 200, 'headers', 'text/plain; charset=utf-8', {
      'x-lab-tag': 'fixture',
      'set-cookie': 'synthetic=1',
      'x-private': 'synthetic',
    });
  }
}

function pathInside(root, candidate) {
  return candidate === root || candidate.startsWith(`${root}${path.sep}`);
}

async function handleWeb(request, response, webRoot, log) {
  let url;
  try {
    url = new URL(request.url ?? '/', `http://${HOST}`);
  } catch {
    url = new URL('/', `http://${HOST}`);
    sendWebError(request, response, url, log, 400, 'BAD_REQUEST', 'Invalid request target');
    return;
  }

  if (request.method !== 'GET' && request.method !== 'HEAD') {
    sendWebError(request, response, url, log, 405, 'METHOD_NOT_ALLOWED', 'Method not allowed');
    return;
  }
  if (url.pathname === '/healthz') {
    sendJson(request, response, url, log, 200, { service: 'web', protocol: 1 }, {
      'content-security-policy': CSP,
    });
    return;
  }

  let root;
  try {
    root = await realpath(webRoot);
    const rootStats = await stat(root);
    if (!rootStats.isDirectory()) throw new Error('not a directory');
  } catch {
    sendJson(
      request,
      response,
      url,
      log,
      503,
      { error: { code: 'ASSETS_UNAVAILABLE', message: 'Web assets are unavailable' } },
      { 'content-security-policy': CSP },
    );
    return;
  }

  let decodedPath;
  try {
    const rawPath = (request.url ?? '/').split('?', 1)[0];
    decodedPath = decodeURIComponent(rawPath);
    if (decodedPath.includes('\0') || decodedPath.includes('\\')) throw new Error('unsafe path');
    if (decodedPath.split('/').includes('..')) throw new Error('unsafe path');
  } catch {
    sendWebError(request, response, url, log, 400, 'BAD_PATH', 'Invalid asset path');
    return;
  }

  let candidate = path.resolve(root, `.${decodedPath}`);
  if (!pathInside(root, candidate)) {
    sendWebError(request, response, url, log, 403, 'PATH_DENIED', 'Asset path denied');
    return;
  }
  try {
    let candidateStats = await stat(candidate);
    if (candidateStats.isDirectory()) {
      candidate = path.join(candidate, 'index.html');
      candidateStats = await stat(candidate);
    }
    const resolved = await realpath(candidate);
    if (!pathInside(root, resolved) || !candidateStats.isFile()) {
      sendWebError(request, response, url, log, 403, 'PATH_DENIED', 'Asset path denied');
      return;
    }
    // The response may close while the asynchronous path checks are in flight.
    if (response.destroyed) return;
    const contentType = MIME_TYPES.get(path.extname(resolved).toLowerCase()) ?? 'application/octet-stream';
    response.writeHead(200, responseHeaders(request, contentType, {
      'content-security-policy': CSP,
    }));
    if (request.method === 'HEAD') {
      response.end();
      logResult(log, request, url, 200);
      return;
    }
    const stream = createReadStream(resolved);
    const destroySource = () => stream.destroy();
    response.once('close', destroySource);
    response.once('error', destroySource);
    const sourceClosed = new Promise((resolve) => stream.once('close', () => {
      response.off('close', destroySource);
      response.off('error', destroySource);
      resolve();
    }));
    stream.once('error', () => {
      if (!response.headersSent) {
        sendWebError(request, response, url, log, 500, 'ASSET_READ_FAILED', 'Asset read failed');
      } else {
        response.destroy();
      }
    });
    stream.once('end', () => logResult(log, request, url, 200));
    stream.pipe(response);
    await sourceClosed;
  } catch {
    sendWebError(request, response, url, log, 404, 'NOT_FOUND', 'Asset not found');
  }
}

export function createLabServer({
  host = HOST,
  webPort = 8787,
  apiPort = 8788,
  webRoot,
  log = () => {},
}) {
  if (host !== HOST) throw new Error(`host must be ${HOST}`);
  const delayTimers = new Set();
  const webHandlers = new Set();
  let actualWebPort = webPort;
  const webServer = http.createServer((request, response) => {
    const handler = handleWeb(request, response, webRoot, log).catch((error) => {
      log(`web handler error: ${error.message}`);
      response.destroy();
    });
    webHandlers.add(handler);
    handler.finally(() => webHandlers.delete(handler));
  });
  const apiServer = http.createServer((request, response) => {
    handleApi(request, response, actualWebPort, log, delayTimers).catch((error) => {
      log(`api handler error: ${error.message}`);
      response.destroy();
    });
  });

  return {
    async start() {
      await listen(webServer, host, webPort);
      actualWebPort = webServer.address().port;
      try {
        await listen(apiServer, host, apiPort);
      } catch (error) {
        await closeServer(webServer);
        throw error;
      }
      const webAddress = webServer.address();
      const apiAddress = apiServer.address();
      return {
        webPort: webAddress.port,
        apiPort: apiAddress.port,
        webUrl: `http://${host}:${webAddress.port}`,
        apiUrl: `http://${host}:${apiAddress.port}`,
      };
    },
    async close() {
      for (const timer of delayTimers) clearTimeout(timer);
      delayTimers.clear();
      await Promise.all([closeServer(webServer), closeServer(apiServer)]);
      // Socket closure initiates source destruction; wait for filesystem closure too.
      await Promise.all(webHandlers);
    },
  };
}

function parseServerArguments(argv) {
  const options = {};
  const allowed = new Set(['api-port', 'repo-root', 'state-dir', 'token', 'web-port', 'web-root']);
  for (let index = 0; index < argv.length; index += 2) {
    const name = argv[index];
    const value = argv[index + 1];
    if (!name?.startsWith('--') || value === undefined) throw new Error('invalid server arguments');
    const key = name.slice(2);
    if (!allowed.has(key) || key in options) throw new Error('invalid server arguments');
    options[key] = value;
  }
  const webPort = Number(options['web-port']);
  const apiPort = Number(options['api-port']);
  const portsValid = [webPort, apiPort].every((port) => (
    Number.isInteger(port) && port >= 1 && port <= 65_535
  ));
  if (!portsValid || webPort === apiPort) throw new Error('invalid ports');
  if (!path.isAbsolute(options['web-root'] ?? '')) throw new Error('web root must be absolute');
  if (!path.isAbsolute(options['state-dir'] ?? '')) throw new Error('state dir must be absolute');
  if (!/^[a-f0-9]{32}$/.test(options.token ?? '')) throw new Error('invalid ownership token');
  const expectedRepoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  if (options['repo-root'] !== expectedRepoRoot) throw new Error('invalid repository root');
  return { webPort, apiPort, webRoot: options['web-root'] };
}

async function runServer() {
  const options = parseServerArguments(process.argv.slice(2));
  const lab = createLabServer({ ...options, log: (line) => console.log(line) });
  let stopping = false;
  const stop = async () => {
    if (stopping) return;
    stopping = true;
    await lab.close();
    process.exit(0);
  };
  process.once('SIGTERM', stop);
  process.once('SIGINT', stop);
  const addresses = await lab.start();
  console.log(`ready web=${addresses.webPort} api=${addresses.apiPort}`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  runServer().catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}