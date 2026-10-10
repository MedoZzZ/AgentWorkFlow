import http from 'node:http';
import { readFile, readdir, stat, realpath, open } from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const assets = path.join(path.dirname(fileURLToPath(import.meta.url)), 'public');
const runPattern = /^[A-Za-z0-9_-]+$/;
const documents = ['PROGRESS.md', 'PROJECT-SPEC.md', 'USE-CASES.md', 'DESIGN.md', 'ARCHITECTURE.md', 'CI.md', 'ORCHESTRATION.md', 'GOVERNANCE.md', 'LINUX.md'];
const executeFile = promisify(execFile);
const limit = 2 * 1024 * 1024;
const hash = text => createHash('sha256').update(text).digest('hex').toUpperCase();
const inside = (root, target) => { const relative = path.relative(root, target); return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative)); };

export async function createDashboard({ projectRoot, intervalMs = 1000 } = {}) {
  const root = await realpath(projectRoot || path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..'));
  const clients = new Set();
  const readers = new Map();
  let revisionCache = { updated: 0, value: null };
  let revisionPending;
  async function revision() {
    if (Date.now() - revisionCache.updated < intervalMs) return revisionCache.value;
    if (!revisionPending) revisionPending = (async () => {
      let value = null;
      try { value = (await executeFile('git', ['-C', root, 'rev-parse', 'HEAD'], { timeout: 2000, maxBuffer: 4096, windowsHide: true })).stdout.trim(); }
      catch { /* No committed baseline: fingerprints still bind the review. */ }
      revisionCache = { updated: Date.now(), value }; return value;
    })().finally(() => { revisionPending = undefined; });
    return revisionPending;
  }
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
    const currentRevision = await revision();
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
            if (task.verification?.revisionBound && task.verification.testedRevision !== currentRevision) verificationCurrent = false;
            if (task.verification?.revisionBound && JSON.stringify(task.verification.dependencies) !== JSON.stringify(task.dependencies)) verificationCurrent = false;
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
    const [taskList, runList, workflowList, records, docs] = await Promise.all([tasks(), runs(), workflows(), governance(), Promise.all(documents.map(async name => [name, await text(`workflow/${name}`)]))]);
    return { name: path.basename(root), root, revision: await revision(), tasks: taskList, runs: runList, workflows: workflowList, governance: records, documents: Object.fromEntries(docs), summary: {
      total: taskList.filter(task => task.status !== 'unmanaged').length,
      verified: taskList.filter(task => task.status === 'verified' && task.verificationCurrent).length,
      active: taskList.filter(task => task.status === 'in-progress').length,
      review: taskList.filter(task => task.status === 'ready-for-verification').length,
      blocked: taskList.filter(task => ['blocked', 'failed', 'interrupted', 'needs-fix'].includes(task.status) || task.pendingDependencies.length).length,
    } };
  }
  async function governance() {
    async function records(directory, latestOnly = false) {
      const result = [];
      for (const entry of await entries(directory)) {
        if (entry.isFile() && entry.name.endsWith('.json') && !latestOnly) result.push({ file: `${directory}/${entry.name}`, record: await json(`${directory}/${entry.name}`) });
        else if (entry.isDirectory() && latestOnly && runPattern.test(entry.name)) {
          const record = await json(`${directory}/${entry.name}/latest.json`);
          if (record) result.push({ file: `${directory}/${entry.name}/latest.json`, record });
        }
      }
      return result;
    }
    const [decisions, migrations, releases] = await Promise.all([records('workflow/decisions'), records('workflow/migrations'), records('workflow/runs/_releases', true)]);
    // Reports are historical; indicate stale referenced inputs and approvals independently.
    for (const item of releases) item.revisionCurrent = item.record?.reviewedRevision === await revision();
    return { decisions, migrations, releases };
  }
  async function registry() {
    const data = await json('workflow/projects.json');
    if (!data) return [];
    if (data.schemaVersion !== 1 || !Array.isArray(data.projects) || data.projects.length > 50) throw new Error('Invalid project registry');
    const ids = new Set(['local']), paths = new Set();
    return data.projects.map(entry => {
      if (!entry || !runPattern.test(entry.id) || ids.has(entry.id) || typeof entry.name !== 'string' || typeof entry.root !== 'string' || !path.isAbsolute(entry.root) || !['active', 'archived'].includes(entry.status)) throw new Error('Invalid registered project');
      const normalized = process.platform === 'win32' ? path.resolve(entry.root).toLowerCase() : path.resolve(entry.root);
      if (paths.has(normalized)) throw new Error('Duplicate registered project path');
      paths.add(normalized); ids.add(entry.id); return entry;
    });
  }
  async function projectReader(id = 'local') {
    if (id === 'local') return { project, runDetails, workflows, governance };
    if (!runPattern.test(id)) throw new Error('Invalid Project ID');
    const entry = (await registry()).find(item => item.id === id);
    if (!entry) throw new Error('Project is not registered');
    const canonical = await realpath(entry.root);
    const key = `${id}:${canonical}`;
    if (!readers.has(key)) readers.set(key, await createDashboard({ projectRoot: canonical, intervalMs }));
    // Evict obsolete readers after a registry path update, without opening extra listeners.
    for (const [other, reader] of readers) if (other.startsWith(`${id}:`) && other !== key) { await reader.close(); readers.delete(other); }
    return readers.get(key);
  }
  async function portfolio() {
    const entries = [{ id: 'local', name: path.basename(root), root, status: 'active' }, ...await registry()];
    const projects = [];
    for (const entry of entries) {
      try {
        const value = await (await projectReader(entry.id)).project();
        projects.push({ ...entry, root: value.root, summary: value.summary, workflows: value.workflows, releases: value.governance.releases,
          attention: value.tasks.filter(task => ['blocked','failed','interrupted','needs-fix','ready-for-verification','invalid'].includes(task.status) || task.verificationCurrent === false || task.pendingDependencies.length).map(task => ({ taskId: task.taskId, status: task.status, title: task.title, stale: task.verificationCurrent === false })) });
      } catch { projects.push({ ...entry, error: 'Project evidence unavailable; check its registered local path.' }); }
    }
    return { projects };
  }
  async function workflows() {
    const result = [];
    const scopedTasks = await tasks();
    for (const entry of await entries('workflow/runs/_workflows')) {
      if (!entry.isDirectory() || !runPattern.test(entry.name)) continue;
      const state = await json(`workflow/runs/_workflows/${entry.name}/state.json`);
      if (!state) continue;
      if (state.parseError || state.schemaVersion !== 1 || state.workflowId !== entry.name) {
        result.push({ workflowId: entry.name, phase: 'invalid', stopReason: 'Malformed workflow checkpoint', updatedUtc: '' });
        continue;
      }
      const plan = await json(`workflow/runs/_workflows/${entry.name}/approved-plan.json`);
      const ids = Array.isArray(plan?.tasks) ? plan.tasks.map(task => task.taskId) : [];
      // State is a checkpoint, so explicitly flag current verification instead of inventing live execution.
      const currentCompleted = ids.filter(id => scopedTasks.some(task => task.taskId === id && task.verificationCurrent && (!plan.governance?.requireReviewerIdentity || (task.verification?.revisionBound && task.verification.reviewer?.id && task.verification.reviewer?.contextId))));
      const currentPending = ids.filter(id => !currentCompleted.includes(id));
      result.push({ ...state, currentCompleted, currentPending, completionCurrent: state.phase === 'complete' && ids.length > 0 && !currentPending.length,
        elapsedSecondsAtCheckpoint: Math.max(0, Math.floor((Date.parse(state.updatedUtc) - Date.parse(state.startedUtc)) / 1000)) || 0 });
    }
    return result.sort((a, b) => (b.updatedUtc || '').localeCompare(a.updatedUtc || ''));
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
      if (url.pathname === '/api/projects') return sendJson(res, 200, await portfolio());
      const selectedId = url.searchParams.get('projectId') || 'local';
      if (!runPattern.test(selectedId)) return sendJson(res, 400, { error: 'Invalid Project ID' });
      const selected = await projectReader(selectedId);
      if (url.pathname === '/api/project') return sendJson(res, 200, await selected.project());
      if (url.pathname === '/api/workflows') return sendJson(res, 200, await selected.workflows());
      if (url.pathname === '/api/governance') return sendJson(res, 200, await selected.governance());
      if (url.pathname.startsWith('/api/runs/')) {
        const id = decodeURIComponent(url.pathname.slice('/api/runs/'.length));
        if (!runPattern.test(id)) return sendJson(res, 400, { error: 'Invalid Run ID' });
        const detail = await selected.runDetails(id);
        return sendJson(res, detail ? 200 : 404, detail || { error: 'Run not found' });
      }
      if (url.pathname === '/api/events') {
        const id = url.searchParams.get('runId');
        if (id && !runPattern.test(id)) return sendJson(res, 400, { error: 'Invalid Run ID' });
        if (id && !await selected.runDetails(id)) return sendJson(res, 404, { error: 'Run not found' });
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
              const snapshot = url.searchParams.get('portfolio') === '1' ? await portfolio() : await (await projectReader(selectedId)).project();
              const serialized = JSON.stringify(snapshot);
              if (serialized !== lastSnapshot) { send('project', snapshot); lastSnapshot = serialized; }
            } else {
              const reader = await projectReader(selectedId);
              const detail = await reader.runDetails(id);
              const serialized = JSON.stringify(detail);
              if (serialized !== lastSnapshot) { send('run', detail); lastSnapshot = serialized; }
              try {
                const selectedRoot = reader.root || root;
                const file = path.resolve(selectedRoot, `workflow/runs/${id}/events.ndjson`);
                if (!inside(selectedRoot, await realpath(file))) throw new Error('Symbolic link outside project');
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
  return { root, server, project, runDetails, workflows, governance, async listen(port=4317) { await new Promise((resolve,reject)=>{ server.once('error',reject); server.listen(port,'127.0.0.1',resolve); }); return `http://127.0.0.1:${server.address().port}`; }, async close() { for(const client of clients) client.destroy(); for(const reader of readers.values()) await reader.close(); readers.clear(); if(server.listening) await new Promise(resolve=>server.close(resolve)); } };
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args=process.argv.slice(2); let projectRoot,port=4317;
  for(let i=0;i<args.length;i++) { if(args[i]==='--project-root') projectRoot=args[++i]; else if(args[i]==='--port') port=Number(args[++i]); else throw new Error(`Unknown argument: ${args[i]}`); }
  if(!Number.isInteger(port)||port<0||port>65535) throw new Error('Invalid port');
  const dashboard=await createDashboard({projectRoot});
  console.log(`AgentWorkFlow dashboard: ${await dashboard.listen(port)}`);
  for(const signal of ['SIGINT','SIGTERM']) process.on(signal,async()=>{ await dashboard.close(); process.exit(0); });
}
