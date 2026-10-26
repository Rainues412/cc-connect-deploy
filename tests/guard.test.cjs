const { test } = require('node:test');
const assert = require('node:assert/strict');
const { PassThrough } = require('node:stream');
const { containsImage, toolDecision, createBridge, NOTICE } = require('../scripts/claude-image-guard.cjs');
test('nested image and image_url are recognized, plain text is allowed', () => {
  assert.equal(containsImage([{type:'text',text:'image'}]),false);
  assert.equal(containsImage([{type:'image',source:{data:'not printed'}}]),true);
  assert.equal(containsImage({content:[{type:'image_url'}]}),true);
});
test('image Read is denied but text file Read and other tools are unchanged', () => {
  assert.equal(toolDecision({tool_name:'Read',tool_input:{file_path:'D:/x/A.PNG'}}).hookSpecificOutput.permissionDecision,'deny');
  assert.deepEqual(toolDecision({tool_name:'Read',tool_input:{file_path:'D:/x/a.md'}}),{});
  assert.deepEqual(toolDecision({tool_name:'Bash',tool_input:{command:'echo ok'}}),{});
});
test('image before first text does not launch Claude or create an upstream user turn', () => {
  let starts=0, output='';
  const bridge=createBridge({args:[],launch:()=>{starts++;},output:t=>output+=t,errorOutput:()=>{}});
  bridge.accept(JSON.stringify({type:'user',message:{content:[{type:'image',source:{data:'dummy'}}]}}));
  assert.equal(starts,0);assert.equal(JSON.parse(output).result,NOTICE);assert.equal(JSON.parse(output).session_id,'');
});
test('image between text turns preserves backend session and forwards control replies unchanged', async () => {
  let starts=0, output='', upstream='';
  const child={stdin:new PassThrough(),stdout:new PassThrough(),stderr:new PassThrough(),kill(){}};
  child.stdin.on('data',b=>upstream+=b);
  const bridge=createBridge({args:['--resume','existing-session'],launch:()=>{starts++;return child;},output:t=>output+=t,errorOutput:()=>{}});
  const first=JSON.stringify({type:'user',message:{content:'remember marker'}});
  bridge.accept(first);
  child.stdout.write(JSON.stringify({type:'system',session_id:'existing-session'})+'\n');
  bridge.accept(JSON.stringify({type:'user',message:{content:[{type:'image'}]}}));
  const second=JSON.stringify({type:'user',message:{content:'continue marker'}});
  const control=JSON.stringify({type:'control_response',response:{request_id:'r1'}});
  bridge.accept(second);bridge.accept(control);
  await new Promise(r=>setImmediate(r));
  assert.equal(starts,1);assert.equal(upstream,first+'\n'+second+'\n'+control+'\n');
  const result=output.trim().split('\n').map(JSON.parse).find(x=>x.type==='result');
  assert.equal(result.session_id,'existing-session');assert.equal(result.is_error,false);
});
