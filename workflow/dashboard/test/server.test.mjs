import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, appendFile, rm } from 'node:fs/promises';
import { symlink } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { createHash } from 'node:crypto';
import { createDashboard } from '../server.mjs';

async function fixture(t) {
  const root=await mkdtemp(path.join(os.tmpdir(),'agentworkflow-dashboard-'));
  await mkdir(path.join(root,'workflow/tasks'),{recursive:true});
  await mkdir(path.join(root,'workflow/runs/run-01/verification'),{recursive:true});
  await writeFile(path.join(root,'workflow/PROGRESS.md'),'# Progress\n\n## Next\n- Review actual implementation\n');
  const metadata={runId:'run-01',taskId:'TASK-001',status:'running',outcome:'running',conversationId:'conversation-01',outputFormat:'stream-json',startedUtc:'2026-10-09T00:00:00Z',verification:'pending'};
  await writeFile(path.join(root,'workflow/runs/run-01/metadata.json'),JSON.stringify(metadata));
  await writeFile(path.join(root,'workflow/runs/run-01/prompt.txt'),'Exact prompt: inspect <script>alert(1)</script>');
  await writeFile(path.join(root,'workflow/tasks/TASK-001.md'),`<!-- workflow-task\n${JSON.stringify({schemaVersion:1,taskId:'TASK-001',status:'in-progress',dependencies:[],attempts:[{runId:'run-01'}],history:[]})}\n-->\n# TASK-001: Implement a real change\n`);
  const dashboard=await createDashboard({projectRoot:root,intervalMs:20});
  const url=await dashboard.listen(0);
  t.after(async()=>{await dashboard.close();assert.ok(path.resolve(root).startsWith(path.resolve(os.tmpdir())+path.sep));assert.match(path.basename(root),/^agentworkflow-dashboard-/);await rm(root,{recursive:true,force:true});});
  return {root,url,dashboard,metadata,async write(relative,value){await writeFile(path.join(root,relative),typeof value==='string'?value:JSON.stringify(value));}};
}
async function events(url,{lastId,until}={}) {
  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),4000);
  const response=await fetch(url,{signal:controller.signal,headers:lastId?{'Last-Event-ID':String(lastId)}:{}});
  assert.equal(response.status,200);
  assert.match(response.headers.get('content-type'),/text\/event-stream/);
  const reader=response.body.getReader(),decoder=new TextDecoder();let buffer='',result=[];
  try {
    while(true){const {value,done}=await reader.read();if(done)break;buffer+=decoder.decode(value,{stream:true});let end;while((end=buffer.indexOf('\n\n'))!==-1){const record=buffer.slice(0,end);buffer=buffer.slice(end+2);if(record.startsWith(':'))continue;const fields=Object.fromEntries(record.split('\n').map(line=>{const index=line.indexOf(':');return [line.slice(0,index),line.slice(index+1).trimStart()];}));if(fields.data){result.push({...fields,data:JSON.parse(fields.data)});if(until?.(result)){return result;}}}}
  }finally{clearTimeout(timer);controller.abort();await reader.cancel().catch(()=>{});}
  return result;
}
test('overview reports real project tasks and preserves execution versus verification',async t=>{
  const f=await fixture(t);const p=await fetch(f.url+'/api/project').then(r=>r.json());
  assert.equal(p.summary.total,1);assert.equal(p.summary.active,1);assert.equal(p.summary.verified,0);
  assert.equal(p.runs[0].conversationId,'conversation-01');assert.match(p.documents['PROGRESS.md'],/Review actual/);
  const detail=await fetch(f.url+'/api/runs/run-01').then(r=>r.json());assert.equal(detail.metadata.verification,'pending');assert.match(detail.prompt,/<script>/);
  assert.equal((await fetch(f.url+'/api/project',{method:'POST'})).status,405);
  assert.equal((await fetch(f.url+'/api/project',{headers:{Origin:'https://example.com'}})).status,403);
  assert.equal((await fetch(f.url+'/api/runs/%2e%2e%2fsecret')).status,400);
  assert.equal((await fetch(f.url+'/api/events?runId=../secret')).status,400);
  assert.equal((await fetch(f.url+'/api/events?runId=missing')).status,404);
  assert.equal((await fetch(f.url+'/api/events?runId=run-01',{headers:{'Last-Event-ID':'bad'}})).status,400);
  const page=await fetch(f.url).then(r=>r.text());assert.match(page,/Project overview/);
  const response=await fetch(f.url);assert.match(response.headers.get('content-security-policy'),/frame-ancestors 'none'/);
  const status=await new Promise(resolve=>http.get(f.url+'/api/project',{headers:{Host:'evil.example:4317'}},res=>{res.resume();resolve(res.statusCode);}));assert.equal(status,403);
});
test('SSE sends complete events only and replays after Last-Event-ID',async t=>{
  const f=await fixture(t);const file=path.join(f.root,'workflow/runs/run-01/events.ndjson');
  await writeFile(file,JSON.stringify({event:'init',conversation_id:'conversation-01'})+'\n{"event":"step_update",');
  const pending=events(f.url+'/api/events?runId=run-01',{until:values=>values.filter(item=>item.event==='cli').length===2});
  const timer=setTimeout(()=>appendFile(file,'"step_update":{"step_index":1,"step_type":"agent_response","text_delta":"Hello 🌍"}}\n'),80);t.after(()=>clearTimeout(timer));
  const received=(await pending).filter(item=>item.event==='cli');assert.deepEqual(received.map(item=>item.id),['1','2']);assert.equal(received[1].data.step_update.text_delta,'Hello 🌍');
  const replay=(await events(f.url+'/api/events?runId=run-01',{lastId:1,until:values=>values.some(item=>item.event==='cli')})).filter(item=>item.event==='cli');assert.equal(replay.length,1);assert.equal(replay[0].id,'2');
  await appendFile(file,'invalid-json\n'+JSON.stringify({event:'result',result:{status:'SUCCESS',response:'Hello 🌍'}})+'\n');
  const final=await events(f.url+'/api/events?runId=run-01',{lastId:2,until:values=>values.some(item=>item.event==='cli'&&item.data.event==='result')});assert.equal(final.find(item=>item.event==='warning').id,'3');assert.equal(final.find(item=>item.event==='cli').id,'4');
});
test('multiple SSE viewers receive the same history and project updates',async t=>{
  const f=await fixture(t);await f.write('workflow/runs/run-01/events.ndjson','{"event":"init","conversation_id":"conversation-01"}\n');
  const both=await Promise.all([1,2].map(()=>events(f.url+'/api/events?runId=run-01',{until:values=>values.some(item=>item.event==='cli')})));assert.equal(both[0].find(item=>item.event==='cli').id,both[1].find(item=>item.event==='cli').id);
  const pending=events(f.url+'/api/events',{until:values=>values.filter(item=>item.event==='project').length===2});
  const timer=setTimeout(()=>f.write('workflow/PROGRESS.md','# Progress\n## Next\n- Updated milestone\n'),80);t.after(()=>clearTimeout(timer));
  const updates=(await pending).filter(item=>item.event==='project');assert.match(updates[1].data.documents['PROGRESS.md'],/Updated milestone/);
});
test('legacy JSON responses and verification evidence remain visible',async t=>{
  const f=await fixture(t);await f.write('workflow/runs/run-01/metadata.json',{...f.metadata,status:'SUCCESS',outcome:'ready-for-verification',outputFormat:'json'});await f.write('workflow/runs/run-01/stdout.json',{status:'SUCCESS',response:'Recorded final response'});await f.write('workflow/runs/run-01/changes.json',{changes:[{path:'app.txt',kind:'modified'}]});await f.write('workflow/runs/run-01/verification/check.json',{verdict:'needs-fix',checks:[{name:'Actual test',status:'failed',evidence:'assertion failed'}]});
  const detail=await f.dashboard.runDetails('run-01');assert.equal(detail.response.response,'Recorded final response');assert.equal(detail.changes[0].path,'app.txt');assert.equal(detail.verification[0].checks[0].status,'failed');
});
test('verified progress becomes stale after source edits',async t=>{
  const f=await fixture(t);await f.write('app.txt','verified source');const content='# TASK-001: Checked\n';const scopeHash=createHash('sha256').update(content).digest('hex').toUpperCase();const task={taskId:'TASK-001',status:'verified',dependencies:[],attempts:[],history:[],verification:{verdict:'verified',taskScopeHash:scopeHash,files:{'app.txt':createHash('sha256').update('verified source').digest('hex').toUpperCase()}}};
  await f.write('workflow/tasks/TASK-001.md',`<!-- workflow-task\n${JSON.stringify(task)}\n-->\n${content}`);assert.equal((await f.dashboard.project()).summary.verified,1);await f.write('app.txt','modified source');const changed=await f.dashboard.project();assert.equal(changed.summary.verified,0);assert.equal(changed.tasks[0].verificationCurrent,false);
});
test('malformed task headers are visible without breaking the overview',async t=>{
  const f=await fixture(t);
  await f.write('workflow/tasks/broken.md','<!-- workflow-task\nnull\n-->\n# Broken task\n');
  const p=await f.dashboard.project();assert.equal(p.tasks.find(task=>task.file.endsWith('broken.md')).status,'invalid');assert.equal(p.summary.active,1);
});
test('SSE bounds oversized events and preserves subsequent event IDs',async t=>{
  const f=await fixture(t);
  await f.write('workflow/runs/run-01/events.ndjson','x'.repeat(2*1024*1024+100)+'\n{"event":"result","result":{"status":"SUCCESS","response":"small final"}}\n');
  const received=await events(f.url+'/api/events?runId=run-01',{until:values=>values.some(item=>item.event==='cli')});
  assert.match(received.find(item=>item.event==='warning').data.message,/Oversized/);assert.equal(received.find(item=>item.event==='cli').id,'2');
});
test('run symlinks cannot expose files outside the selected project',async t=>{
  const f=await fixture(t),outside=await mkdtemp(path.join(os.tmpdir(),'agentworkflow-dashboard-outside-'));
  t.after(async()=>{assert.ok(path.resolve(outside).startsWith(path.resolve(os.tmpdir())+path.sep));assert.match(path.basename(outside),/^agentworkflow-dashboard-outside-/);await rm(outside,{recursive:true,force:true});});
  await writeFile(path.join(outside,'metadata.json'),JSON.stringify({secret:'must not be exposed'}));
  try{await symlink(outside,path.join(f.root,'workflow/runs/escape'),process.platform==='win32'?'junction':'dir');}
  catch(error){if(error.code==='EPERM'){t.skip('Symlink creation unavailable');return;}throw error;}
  const response=await fetch(f.url+'/api/runs/escape');assert.equal(response.status,500);assert.doesNotMatch(await response.text(),/must not be exposed/);
});
