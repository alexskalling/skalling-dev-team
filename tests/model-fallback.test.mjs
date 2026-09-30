import test from 'node:test';
import assert from 'node:assert/strict';
import { setupModelFallback, validatePolicy } from '../plugins/lib/model-fallback.mjs';

function runtime(policy = {Teo:{models:['other/backup','other/last']}}, available = true) {
  const hooks = {}, calls = [], notices = [];
  const ctx = {app:{version:'2.0.18'}, session:{
    hook:async (name, cb)=>{hooks[name]=cb;},
    switchModel:async input=>{calls.push(input);},
  }, provider:{transform:async cb=>cb({list:()=>[],update:()=>{}})},
  model:{list:async ()=> ({data: available ? ['backup','last'].map(id=>({providerID:'other',id})) : []})}};
  return {ctx,hooks,calls,notices,setup:async()=>{await setupModelFallback(ctx,()=>policy,n=>notices.push(n));await hooks.context({sessionID:"s1",agent:"Teo",model:{providerID:"primary",id:"main"}});}};
}
const failure = (type='provider.transport', attempt=2, id='main') => ({
  sessionID:'s1',agent:'Teo',model:{providerID:'primary',id},
  error:{type,message:'private provider payload'},attempt,decision:{retry:true,delay:30000},
});

test('provider failures switch the same session before retry; no new prompt or tool invocation', async()=>{
  const r=runtime(); await r.setup(); const e=failure(); await r.hooks.retry(e);
  assert.deepEqual(r.calls,[{sessionID:'s1',model:{providerID:'other',id:'backup'}}]);
  assert.deepEqual(e.decision,{retry:true,delay:0});
  assert.equal(JSON.stringify(r.notices).includes('private provider payload'),false);
});
for (const type of ['provider.timeout','provider.internal','provider.invalid-output','provider.auth','provider.no-route']) {
  test(`recovers ${type}`,async()=>{const r=runtime();await r.setup();const e=failure(type);await r.hooks.retry(e);assert.equal(r.calls.length,1);});
}
for (const type of ['aborted','permission.rejected','tool.execution','provider.content-filter','provider.invalid-request']) {
  test(`does not reroute ${type}`,async()=>{const r=runtime();await r.setup();const e=failure(type);await r.hooks.retry(e);assert.equal(r.calls.length,0);});
}
test('bounded unique chain and independent sessions',async()=>{
  const r=runtime();await r.setup();
  for(let attempt=2;attempt<=4;attempt++) {const e=failure('provider.timeout',attempt);await r.hooks.retry(e);if(attempt===4)assert.equal(e.decision.retry,false);}
  assert.equal(r.calls.length,2);
  const e={...failure(),sessionID:'s2'};await r.hooks.context(e);await r.hooks.retry(e);assert.equal(r.calls.length,3);
});
test('unconfigured roles keep native retry policy; unavailable backup is skipped',async()=>{
  const r=runtime(undefined,false);await r.setup();const e=failure();await r.hooks.retry(e);assert.equal(r.calls.length,0);assert.equal(e.decision.retry,false);
  const other={...failure(),agent:'Luz'};await r.hooks.retry(other);assert.equal(other.decision.delay,30000);
});
test('configuration rejects duplicates, injection, excessive chains and invalid deadlines',()=>{
  for(const p of [{Teo:{models:['x/y','x/y']}},{Teo:{models:['x/y\npermission: allow']}},{Teo:{models:[]}},{Teo:{models:['x/y'],timeoutMs:0}},{Unknown:{models:['x/y']}}])assert.throws(()=>validatePolicy(p));
});
test('unsupported runtime fails explicitly only when fallback is configured',async()=>{
  await setupModelFallback({},()=>({}));
  await assert.rejects(setupModelFallback({},()=>({Teo:{models:['x/y']}})),/2.0.18/);
});

import { guardEmptyResponse, outputInspector } from '../plugins/lib/model-fallback.mjs';
test('empty SSE is a transport failure, text and tool calls pass through unchanged',async()=>{
  const chunk = data => 'data: '+JSON.stringify(data)+'\n\n';
  const finish=chunk({choices:[{delta:{},finish_reason:'stop'}]});
  const response = body => new Response(body,{headers:{'content-type':'text/event-stream'}});
  await assert.rejects(guardEmptyResponse(response(finish)).text(),/sin texto/);
  for (const delta of [{content:'OK'},{tool_calls:[{id:'call-1',function:{name:'edit'}}]},{refusal:'No'}]) {
    const body=chunk({choices:[{delta}]})+finish;
    assert.equal(await guardEmptyResponse(response(body)).text(),body);
  }
  const unknown='data: {"unknown":"format"}\n\n';
  assert.equal(await guardEmptyResponse(response(unknown)).text(),unknown);
});
test('empty Responses/Anthropic/Gemini outputs fail; reasoning is not a final answer',()=>{
  for(const frame of [{type:'response.completed',response:{output:[]}},{type:'message_delta',delta:{stop_reason:'end_turn'}},{candidates:[{finishReason:'STOP',content:{parts:[{thought:true,text:'thinking'}]}}]}])assert.throws(()=>outputInspector()(frame),/sin texto/);
});
test('auxiliary requests do not change the session model',async()=>{
  const r=runtime();await r.setup();await r.hooks.compaction({sessionID:'s1'});
  await r.hooks.retry(failure());assert.equal(r.calls.length,0);
});

test('native deadlines are bounded and retain stricter provider settings',async()=>{
  const r=runtime({Teo:{models:['other/backup'],timeoutMs:9000,chunkTimeoutMs:3000}});
  const draft={settings:{timeout:5000,chunkTimeout:1000,apiKey:'preserved'}};
  r.ctx.provider.transform=async cb=>cb({list:()=>[{provider:{id:'primary'}}],update:(_,update)=>update(draft)});
  await r.setup();assert.deepEqual(draft.settings,{timeout:5000,chunkTimeout:1000,apiKey:'preserved'});
});
test('a failed switch cannot leave a retry scheduled for the broken model',async()=>{
  const r=runtime();await r.setup();r.ctx.session.switchModel=async()=>{throw new Error('session closed');};
  const e=failure();await assert.rejects(r.hooks.retry(e),/session closed/);assert.equal(e.decision.retry,false);
});
test('SSE survives chunk boundaries and does not treat refusal as empty',async()=>{
  const body='data: {"choices":[{"delta":{"content":"ó"}}]}\n\ndata: {"choices":[{"finish_reason":"stop"}]}\n\n';
  const bytes=new TextEncoder().encode(body);
  const stream=new ReadableStream({start(c){for(const b of bytes)c.enqueue(new Uint8Array([b]));c.close();}});
  assert.equal(await guardEmptyResponse(new Response(stream,{headers:{'content-type':'text/event-stream'}})).text(),body);
  const inspect=outputInspector();assert.doesNotThrow(()=>inspect({choices:[{finish_reason:'content_filter'}]}));
});
