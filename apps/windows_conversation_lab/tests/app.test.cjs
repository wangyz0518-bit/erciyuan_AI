const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
function page(){
  const nodes=new Map(),sent=[],tracks=[];let options;
  const node=()=>({value:'',textContent:'',checked:true,classList:{add(){},remove(){}},replaceChildren(){},append(){},add(){}});
  const sandbox={console,URLSearchParams,location:{hash:'',pathname:'/'},history:{replaceState(){}},
    document:{getElementById:id=>{if(!nodes.has(id))nodes.set(id,node());return nodes.get(id)},createElement:node,addEventListener(){}},
    window:{addEventListener(){}},performance:{now:()=>0},setTimeout,clearTimeout,setInterval,clearInterval,
    TextEncoder,TextDecoder,ArrayBuffer,DataView,Float32Array,Uint8Array,URL,
    crypto:{randomUUID:()=> 'new-input-000000001'},WebSocket:{OPEN:1},ort:{env:{wasm:{}}},
    navigator:{mediaDevices:{getUserMedia:async()=>{const t={stopped:false,stop(){this.stopped=true},getSettings:()=>({echoCancellation:true,sampleRate:48000})};tracks.push(t);return {getTracks:()=>[t],getAudioTracks:()=>[t]};}}},
    AudioContext:class{constructor(){this.sampleRate=48000;this.audioWorklet={addModule:async()=>{}};}async resume(){}async close(){}},
    AudioWorkletNode:class{constructor(){this.port={postMessage(){}};}connect(){}},
    vad:{MicVAD:{new:async o=>{options=o;let stream;return {start:async()=>{stream=stream?await o.resumeStream(stream):await o.getStream()},pause:async()=>o.pauseStream(stream),destroy:async()=>o.pauseStream(stream)};}}},
  };
  const context=vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(path.join(__dirname,'../app.js'),'utf8'),context);
  sandbox.testSocket={readyState:1,bufferedAmount:0,send:raw=>sent.push(JSON.parse(raw))};
  vm.runInContext("state.connected=true;state.session='test-session';state.socket=testSocket",context);
  return {run:code=>vm.runInContext(code,context),sandbox,sent,tracks,nodes,get options(){return options}};
}
test('late final and saved events after abort never revive output',()=>{
  const p=page();p.run("state.pending='old-input-00000001';abortInput()");
  p.run("receive(JSON.stringify({event:'transcript.final',session_id:'test-session',input_id:'old-input-00000001',text:'late'}))");
  p.run("receive(JSON.stringify({event:'turn.saved',session_id:'test-session',turn:{id:'old-input-00000001',prompt:'late'}}))");
  assert.equal(p.run('state.reply'),null);assert.equal(p.run('state.rows.size'),0);
  assert.equal(p.sent[0].command,'input.abort');
});
test('mute/resume uses new tracked stream and release stops every microphone',async()=>{
  const p=page();assert.equal(await p.run('microphone()'),true);
  await p.run('state.mic.pause()');assert(p.tracks[0].stopped);
  await p.run('state.mic.start()');assert.equal(p.tracks.length,2);
  assert.equal(p.tracks[1].stopped,false);
  await p.run('releaseMic()');assert(p.tracks.every(t=>t.stopped));
  assert.equal(p.run('state.stream'),null);
});
test('late microphone permission after hangup is stopped and cannot enter call',async()=>{
  const p=page();let resolve;
  p.sandbox.navigator.mediaDevices.getUserMedia=()=>new Promise(r=>resolve=r);
  const pending=p.run('microphone()');
  while(!resolve)await new Promise(r=>setImmediate(r));
  await p.run('releaseMic()');
  assert.equal(await pending,false);
  const track={stopped:false,stop(){this.stopped=true}};
  resolve({getTracks:()=>[track]});
  await new Promise(r=>setImmediate(r));
  assert(track.stopped);assert.equal(p.run('state.mic'),null);assert.equal(p.run('state.calling'),false);
});
test('correlated input rejection clears capture and ignores all late results',()=>{
  const p=page();p.run("state.input={id:'bad-input-000000001'}");
  p.run("receive(JSON.stringify({event:'request.failed',session_id:'test-session',input_id:'bad-input-000000001',code:'INPUT_BACKPRESSURE'}))");
  assert.equal(p.run('state.input'),null);assert.equal(p.run("state.ignored.has('bad-input-000000001')"),true);
});
test('overlapping reconnect requests create only the most recent socket',async()=>{
  const p=page();let release;const gate=new Promise(r=>release=r),created=[];
  p.sandbox.testDisconnect=()=>gate;p.run('disconnect=testDisconnect');
  p.sandbox.WebSocket=class{static OPEN=1;constructor(url){created.push(url);}};
  p.run("$('token').value='local-test-token-0000000001'");
  const a=p.run('connect()');const b=p.run('connect()');
  release();await Promise.all([a,b]);assert.equal(created.length,1);
});
test('old voice catalog response cannot overwrite a newly selected role',async()=>{
  const p=page(),resolvers=[];
  p.sandbox.fetch=path=>new Promise(resolve=>resolvers.push(()=>resolve({ok:true,json:async()=>path.includes('voice-binding')?{revision:42,profile_id:'old-profile',name:'old'}:{items:[]}})));
  const pending=p.run('loadVoices()');p.run("state.role='yue';state.session='new-session'");
  resolvers.forEach(resolve=>resolve());await pending;
  assert.equal(p.run('state.voiceRevision'),0);
});
