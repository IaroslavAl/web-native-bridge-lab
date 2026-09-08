// Opt-in component-test fixture, NOT the production lab. No CSP so WebKit frames
// can reach the unchanged adapter. Only presence flags, never credential values,
// are retained. Owned by scripts/verify simulator-stage4-webkit-privacy.
import http from 'node:http';
import { writeFileSync } from 'node:fs';
import { gzipSync } from 'node:zlib';

const events = [];
const sockets = new Set();
const timers = new Set();
const output = process.argv[2];
if (!output) throw new Error('evidence output path required');
const page = `<!doctype html><title>Stage4 component</title><script>
window.results=[]; window.frameResults=[];
window.bridge = value => window.webkit.messageHandlers.nativeHTTP.postMessage(JSON.stringify(value));
window.addEventListener('message', async e => {
 if (e.data?.kind === 'probe' && window !== parent) {
  window.webkit.messageHandlers.observed.postMessage('frame');
  const hello = await bridge({v:1,type:'hello'});
  const request = await bridge({v:1,type:'request',session:e.data.session,id:99,method:'GET',url:'http://127.0.0.1:8788/forbidden-frame',headers:{},body:null,timeoutMs:5000});
  parent.postMessage({kind:'frame-result',hello,request},'http://127.0.0.1:8787');
 }
 if (e.data?.kind === 'frame-result' && window === parent) frameResults.push(e.data);
});
</script><p>Actual WebKit component fixture</p>`;
function record(event) {
  events.push(event);
  if (events.length > 2000) throw new Error('bounded fixture event limit');
  writeFileSync(output, JSON.stringify(events, null, 2) + '\n');
}
function handle(req, res) {
  const url = new URL(req.url, 'http://127.0.0.1');
  if (url.pathname === '/__state') {
    res.writeHead(200, {'content-type':'application/json', 'cache-control':'no-store'});
    res.end(JSON.stringify({fixture:'PER85-Stage4', events})); return;
  }
  const tag = url.searchParams.get('tag') || '-';
  const base = {port:req.socket.localPort, path:url.pathname, tag};
  record({...base, event:'request', cookie:!!req.headers.cookie, authorization:!!req.headers.authorization});
  res.on('close', () => record({...base, event:res.writableFinished ? 'finished' : 'connection-close'}));
  if (url.pathname.startsWith('/vectors/redirect/')) {
    const [, , , status, location] = url.pathname.split('/');
    const headers = location === 'missing' ? {} : {location: location === 'malformed' ? 'http://[' : '/forbidden-redirect-destination'};
    res.writeHead(Number(status), headers); res.end(); return;
  }
  if (url.pathname === '/vectors/empty') { res.writeHead(204); res.end(); return; }
  if (url.pathname.startsWith('/vectors/headers-')) {
    const extra = url.pathname.endsWith('-over') ? 1 : 0;
    res.writeHead(204, {'x-lab-tag':'a'.repeat(8192 - Buffer.byteLength('x-lab-tag') + extra), 'x-private':'b'.repeat(9000)});
    res.end(); return;
  }
  if (url.pathname.startsWith('/vectors/gzip-')) {
    const bytes = 1048576 + (url.pathname.endsWith('-over') ? 1 : 0);
    const compressed = gzipSync(Buffer.alloc(bytes, 'x'));
    record({...base, event:'gzip', decodedBytes:bytes, wireBytes:compressed.length});
    res.writeHead(200, {'content-type':'text/plain', 'content-encoding':'gzip'});
    res.end(compressed); return;
  }
  if (url.pathname === '/vectors/escaped') {
    res.writeHead(200, {'content-type':'text/plain'}); res.end('"\\\n'.repeat(50000)); return;
  }
  if (url.pathname === '/vectors/trickle') {
    res.writeHead(200, {'content-type':'text/plain'}); res.flushHeaders();
    let chunks = 0;
    const timer = setInterval(() => {
      res.write('x'); record({...base, event:'chunk'});
      if (++chunks === 100) { clearInterval(timer); timers.delete(timer); res.end(); }
    }, 50);
    timers.add(timer);
    res.on('close', () => { clearInterval(timer); timers.delete(timer); });
    return;
  }
  if (url.pathname === '/abort') { res.destroy(); return; }
  if (url.pathname === '/delay') {
    const timer = setTimeout(() => {
      timers.delete(timer);
      if (!res.destroyed) { res.writeHead(200, {'content-type':'text/plain'}); res.end('late:' + tag); }
    }, 1500);
    timers.add(timer);
    res.on('close', () => {clearTimeout(timer); timers.delete(timer);});
    return;
  }
  if (url.pathname === '/challenge') {
    res.writeHead(401, {'www-authenticate':'Basic realm="PER85Synthetic"', 'content-type':'text/plain'});
    res.end('synthetic challenge'); return;
  }
  if (url.pathname === '/inspect' || url.pathname === '/cache') {
    res.writeHead(200, {'content-type':'application/json', 'set-cookie':'per85_response=synthetic; Path=/',
      'x-private':'synthetic', 'cache-control':'public, max-age=3600'});
    res.end(JSON.stringify({cookie:!!req.headers.cookie, authorization:!!req.headers.authorization, source:'network'})); return;
  }
  if (url.pathname === '/fresh') {
    res.writeHead(200, {'content-type':'text/plain', 'cache-control':'no-store'}); res.end('fresh:' + tag); return;
  }
  res.writeHead(200, {'content-type':'text/html', 'cache-control':'no-store'}); res.end(page);
}
const servers = [8787,8788].map(() => http.createServer(handle));
for (const server of servers) server.on('connection', socket => {sockets.add(socket); socket.on('close',()=>sockets.delete(socket));});
async function stop() {
  for (const timer of timers) clearTimeout(timer);
  for (const socket of sockets) socket.destroy();
  await Promise.all(servers.map(server => new Promise(resolve => server.close(resolve))));
}
for (const sig of ['SIGTERM','SIGINT']) process.once(sig, () => {stop().then(()=>process.exit(0));});
try {
  for (const [i,server] of servers.entries()) await new Promise((resolve,reject) => {
    server.once('error',reject); server.listen(8787+i,'127.0.0.1',resolve);
  });
  console.log('PER85 Stage4 fixture ready');
} catch (error) { await stop(); console.error(error.code); process.exitCode=1; }
