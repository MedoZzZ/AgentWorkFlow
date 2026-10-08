import http from 'node:http';
import { readFile, readdir, stat, realpath, open } from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const assets = path.join(path.dirname(fileURLToPath(import.meta.url)), 'public');
const runPattern = /^[A-Za-z0-9_-]+$/;
const documents = ['PROGRESS.md', 'PROJECT-SPEC.md', 'USE-CASES.md', 'DESIGN.md', 'ARCHITECTURE.md', 'CI.md'];
const limit = 2 * 1024 * 1024;
const hash = text => createHash('sha256').update(text).digest('hex').toUpperCase();
const inside = (root, target) => { const relative = path.relative(root, target); return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative)); };

export async function createDashboard({ projectRoot, intervalMs = 1000 } = {}) {
  const root = await realpath(projectRoot || path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..'));
  const clients = new Set();
  async function safePath(relative) {
    const target = path.resolve(root, relative);
    if (!inside(root, target)) throw new Error('Path outside project');
    try { if (!inside(root, await realpath(target))) throw new Error('Symbolic link outside project'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    return target;
  }
  async function text(relative, { tail = false } = {}) {
    try {
      const file = await safePath(relative);
      const info = await stat(file);
      if (!info.isFile()) return null;
      if (info.size > limit) {
        if (!tail) return `[File exceeds ${limit} bytes; inspect the local evidence file.]`;
        const handle = await open(file, 'r');
        try { const buffer = Buffer.alloc(limit); const { bytesRead } = await handle.read(buffer, 0, limit, info.size - limit); return `[Earlier output omitted]\n${buffer.subarray(0, bytesRead).toString('utf8')}`; }
        finally { await handle.close(); }
      }
      return await readFile(file, 'utf8');
    } catch (error) { if (error.code === 'ENOENT') return null; throw error; }
  }
  async function json(relative) {
    const value = await text(relative);
    if (!value) return null;
    try { return JSON.parse(value.replace(/^\uFEFF/, '')); } catch { return { parseError: 'Invalid JSON evidence', file: relative }; }
  }
  async function entries(relative) {
    try { return await readdir(await safePath(relative), { withFileTypes: true }); }
    catch (error) { if (error.code === 'ENOENT') return []; throw error; }
  }
  async function tasks() {
    const result = [];
    async function walk(relative) {
      for (const entry of await entries(relative)) {
        const file = `${relative}/${entry.name}`;
        if (entry.isDirectory()) await walk(file);
        else if (entry.isFile() && entry.name.endsWith('.md')) {
          const content = await text(file);
          const header = content?.match(/^<!-- workflow-task\r?\n([\s\S]*?)\r?\n-->\r?\n/);
          let task;
          try {
            task = header ? JSON.parse(header[1]) : { taskId: entry.name.replace(/\.md$/, ''), status: 'unmanaged', dependencies: [], attempts: [], history: [] };
            if (!task || typeof task !== 'object' || typeof task.taskId !== 'string' || typeof task.status !== 'string') throw new Error('Invalid task identity');
          }
          catch { task = { taskId: entry.name, status: 'invalid', parseError: 'Malformed task header' }; }
          if (!Array.isArray(task.dependencies)) task.dependencies = [];
          if (!Array.isArray(task.attempts)) task.attempts = [];
          if (!Array.isArray(task.history)) task.history = [];
          let verificationCurrent = null;
          if (task.status === 'verified') {
            verificationCurrent = Boolean(task.verification?.files && task.verification?.verdict === 'verified');
            for (const [filePath, expected] of Object.entries(task.verification?.files || {})) {
              try {
                const actual = await readFile(await safePath(filePath));
                if (hash(actual) !== expected) verificationCurrent = false;
              } catch (error) { if (error.code !== 'ENOENT' || expected !== null) verificationCurrent = false; }
            }
            const scope = content.replace(/^<!-- workflow-task\r?\n[\s\S]*?\r?\n-->\r?\n/, '').replace(/^Status: .*\r?\n/gm, '').split(/^## Executor result/m)[0];
            if (hash(scope) !== task.verification?.taskScopeHash) verificationCurrent = false;
          }
          result.push({ ...task, file, title: content?.match(/^# (.+)$/m)?.[1] || task.taskId, content, verificationCurrent });
        }
      }
    }
    await walk('workflow/tasks');
    const byId = new Map(result.map(task => [task.taskId, task]));
    for (const task of result) task.pendingDependencies = task.dependencies.filter(id => byId.get(id)?.status !== 'verified' || !byId.get(id)?.verificationCurrent);
    return result.sort((a, b) => a.taskId.localeCompare(b.taskId));
  }
  async function runs() {
    const result = [];
    for (const entry of await entries('workflow/runs')) {
      if (!entry.isDirectory() || !runPattern.test(entry.name)) continue;
      const metadata = await json(`workflow/runs/${entry.name}/metadata.json`);
      if (metadata) result.push({ ...metadata, runId: entry.name });
    }
    return result.sort((a, b) => (b.startedUtc || '').localeCompare(a.startedUtc || ''));
  }
  async function project() {
    const [taskList, runList, docs] = await Promise.all([tasks(), runs(), Promise.all(documents.map(async name => [name, await text(`workflow/${name}`)]))]);
    return { name: path.basename(root), root, tasks: taskList, runs: runList, documents: Object.fromEntries(docs), summary: {
      total: taskList.filter(task => task.status !== 'unmanaged').length,
      verified: taskList.filter(task => task.status === 'verified' && task.verificationCurrent).length,
      active: taskList.filter(task => task.status === 'in-progress').length,
      review: taskList.filter(task => task.status === 'ready-for-verification').length,
      blocked: taskList.filter(task => ['blocked', 'failed', 'interrupted', 'needs-fix'].includes(task.status) || task.pendingDependencies.length).length,
    } };
  }
  async function runDetails(id) {
    if (!runPattern.test(id)) throw new Error('Invalid Run ID');
    const base = `workflow/runs/${id}`;
    const metadata = await json(`${base}/metadata.json`);
    if (!metadata) return null;
    const verification = [];
    for (const entry of await entries(`${base}/verification`)) if (entry.isFile() && entry.name.endsWith('.json')) verification.push(await json(`${base}/verification/${entry.name}`));
    const [prompt, response, diagnostics, changes, task] = await Promise.all([text(`${base}/prompt.txt`), json(`${base}/stdout.json`), text(`${base}/stderr.log`, { tail: true }), json(`${base}/changes.json`), text(`${base}/task-at-dispatch.md`)]);
    return { metadata, prompt, response, diagnostics, changes: changes?.changes || [], verification, task };
  }
  function sendJson(res, code, value) { res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); res.end(JSON.stringify(value)); }

  const server = http.createServer(async (req, res) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'");
    const host = req.headers.host;
    if (!host || !/^127\.0\.0\.1:\d+$/.test(host) || (req.headers.origin && req.headers.origin !== `http://${host}`)) return sendJson(res, 403, { error: 'Local same-origin access only' });
    if (req.method !== 'GET') return sendJson(res, 405, { error: 'Read-only dashboard' });
    try {
      const url = new URL(req.url, `http://${host}`);
      if (url.pathname === '/api/project') return sendJson(res, 200, await project());
      if (url.pathname.startsWith('/api/runs/')) {
        const id = decodeURIComponent(url.pathname.slice('/api/runs/'.length));
        if (!runPattern.test(id)) return sendJson(res, 400, { error: 'Invalid Run ID' });
        const detail = await runDetails(id);
        return sendJson(res, detail ? 200 : 404, detail || { error: 'Run not found' });
      }
      if (url.pathname === '/api/events') {
        const id = url.searchParams.get('runId');
        if (id && !runPattern.test(id)) return sendJson(res, 400, { error: 'Invalid Run ID' });
        if (id && !await runDetails(id)) return sendJson(res, 404, { error: 'Run not found' });
        const lastId = req.headers['last-event-id'] || url.searchParams.get('after') || '0';
        if (!/^\d+$/.test(lastId) || !Number.isSafeInteger(Number(lastId))) return sendJson(res, 400, { error: 'Invalid event cursor' });
        res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache, no-transform', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
        res.write(': connected\n\n');
        let closed = false, busy = false, offset = 0, buffer = Buffer.alloc(0), sequence = 0, skip = Number(lastId), lastSnapshot = '', oversized = false;
        const send = (event, data, eventId) => {
          if (closed) return;
          if (res.writableLength > limit) { res.destroy(); return; }
          res.write(`${eventId === undefined ? '' : `id: ${eventId}\n`}event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
        };
        const tick = async () => {
          if (closed || busy) return;
          busy = true;
          try {
            if (!id) {
              const snapshot = await project();
              const serialized = JSON.stringify(snapshot);
              if (serialized !== lastSnapshot) { send('project', snapshot); lastSnapshot = serialized; }
            } else {
              const detail = await runDetails(id);
              const serialized = JSON.stringify(detail);
              if (serialized !== lastSnapshot) { send('run', detail); lastSnapshot = serialized; }
              try {
                const file = await safePath(`workflow/runs/${id}/events.ndjson`);
                const info = await stat(file);
                if (info.size < offset) { offset=0; buffer=Buffer.alloc(0); sequence=0; skip=0; oversized=false; send('reset', {}); }
                const handle = await open(file, 'r');
                try {
                  // Bound IO per tick; read earlier lines to recreate stable sequence IDs on reconnect.
                  for (let block=0; block<16 && offset<info.size && !closed; block++) {
                    const chunk = Buffer.alloc(Math.min(65536, info.size-offset));
                    const { bytesRead } = await handle.read(chunk, 0, chunk.length, offset);
                    if (!bytesRead) break;
                    offset += bytesRead;
                    buffer = Buffer.concat([buffer, chunk.subarray(0, bytesRead)]);
                    let end;
                    while ((end=buffer.indexOf(10)) !== -1) {
                      const line = buffer.subarray(0,end); buffer=buffer.subarray(end+1); sequence++;
                      if (sequence <= skip) { oversized=false; continue; }
                      if (oversized || line.length>limit) { send('warning', { message:'Oversized event omitted' }, sequence); oversized=false; continue; }
                      if (!line.toString('utf8').trim()) { send('warning', { message:'Empty event line' }, sequence); continue; }
                      try { const event=JSON.parse(line.toString('utf8')); if (!event || typeof event !== 'object' || !event.event) throw new Error(); send('cli', event, sequence); }
                      catch { send('warning', { message:'Malformed CLI event; raw evidence preserved' }, sequence); }
                    }
                    if (buffer.length>limit) { buffer=Buffer.alloc(0); oversized=true; }
                  }
                } finally { await handle.close(); }
              } catch (error) { if (error.code !== 'ENOENT') throw error; }
            }
            res.write(': heartbeat\n\n');
          } catch { send('warning', { message:'Evidence temporarily unavailable; retrying' }); }
          finally { busy=false; }
        };
        const timer=setInterval(tick, intervalMs); clients.add(res);
        res.on('close', () => { closed=true; clearInterval(timer); clients.delete(res); });
        void tick();
        return;
      }
      const asset = { '/':'index.html', '/app.js':'app.js', '/style.css':'style.css' }[url.pathname];
      if (!asset) return sendJson(res,404,{error:'Not found'});
      const content=await readFile(path.join(assets,asset));
      res.writeHead(200,{'Content-Type':asset.endsWith('.css')?'text/css':asset.endsWith('.js')?'text/javascript':'text/html','Cache-Control':'no-store'}); res.end(content);
    } catch { if (!res.headersSent) sendJson(res,500,{error:'Unable to read project evidence'}); else res.destroy(); }
  });
  return { server, project, runDetails, async listen(port=4317) { await new Promise((resolve,reject)=>{ server.once('error',reject); server.listen(port,'127.0.0.1',resolve); }); return `http://127.0.0.1:${server.address().port}`; }, async close() { for(const client of clients) client.destroy(); await new Promise(resolve=>server.close(resolve)); } };
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args=process.argv.slice(2); let projectRoot,port=4317;
  for(let i=0;i<args.length;i++) { if(args[i]==='--project-root') projectRoot=args[++i]; else if(args[i]==='--port') port=Number(args[++i]); else throw new Error(`Unknown argument: ${args[i]}`); }
  if(!Number.isInteger(port)||port<0||port>65535) throw new Error('Invalid port');
  const dashboard=await createDashboard({projectRoot});
  console.log(`AgentWorkFlow dashboard: ${await dashboard.listen(port)}`);
  for(const signal of ['SIGINT','SIGTERM']) process.on(signal,async()=>{ await dashboard.close(); process.exit(0); });
}
