const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
function page(){
  const nodes=new Map(),sent=[],tracks=[],created=[];let options;
  const node=kind=>({kind,value:'',textContent:'',checked:true,classList:{add(){},remove(){}},replaceChildren(){},replaceWith(){},append(){},add(){},async play(){this.played=true},pause(){this.paused=true}});
  const sandbox={console,URLSearchParams,location:{hash:'',pathname:'/'},history:{replaceState(){}},
    document:{getElementById:id=>{if(!nodes.has(id))nodes.set(id,node());return nodes.get(id)},createElement:kind=>{const n=node(kind);created.push(n);return n},addEventListener(){}},
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
  return {run:code=>vm.runInContext(code,context),sandbox,sent,tracks,nodes,created,get options(){return options}};
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
test('hangup releases microphone even before a closing socket fires onclose',async()=>{
  const p=page();await p.run('microphone()');
  p.run("state.calling=true;state.input={id:'active-input-00001'};state.reply='active-reply-00001';state.socket.readyState=2");
  await p.run('endCall()');
  assert(p.tracks.every(t=>t.stopped));assert.equal(p.run('state.input'),null);
  assert.equal(p.run('state.reply'),null);assert.equal(p.run('state.calling'),false);
});
test('late playback progress on a closing socket never throws',async()=>{
  const p=page();await p.run('setupAudio()');
  p.run("state.reply='active-reply-00001';state.socket.readyState=2");
  assert.doesNotThrow(()=>p.run("state.player.port.onmessage({data:{type:'progress',id:'active-reply-00001',frames:2400}})"));
});
test('a delayed recording download cannot start playing after hangup',async()=>{
  const p=page();let resolve,urls=0;
  p.sandbox.URL={createObjectURL:()=>{urls++;return 'blob:test'},revokeObjectURL(){}};
  p.sandbox.fetch=()=>new Promise(r=>resolve=r);
  p.run("state.rows.set('recording-00000001',{id:'recording-00000001',prompt:'test',has_recording:true,reply:'reply',kind:'hold',state:'complete'});render()");
  const play=p.created.find(n=>n.kind==='button');
  const pending=play.onclick();await p.run('endCall()');
  resolve({ok:true,blob:async()=>({})});await pending;
  assert.equal(urls,0);assert.equal(p.run('state.replay'),null);
});
test('recording replay can be stopped and replayed without leaving an unmanaged player',async()=>{
  const p=page();let revoked=0;
  p.sandbox.URL={createObjectURL:()=> 'blob:test',revokeObjectURL(){revoked++}};
  p.sandbox.fetch=async()=>({ok:true,blob:async()=>({})});
  p.run("state.rows.set('recording-00000001',{id:'recording-00000001',prompt:'test',has_recording:true,reply:'reply',kind:'hold',state:'complete'});render()");
  const play=p.created.find(n=>n.kind==='button');
  await play.onclick();const first=p.run('state.replay');assert(first.played);assert.equal(play.textContent,'停止回听');
  await play.onclick();assert(first.paused);assert.equal(p.run('state.replay'),null);assert.equal(revoked,1);
  await play.onclick();const second=p.run('state.replay');assert(second.played);assert.notEqual(second,first);
  first.onended();assert.equal(p.run('state.replay'),second);
  await p.run('endCall()');assert(second.paused);assert.equal(revoked,2);assert.equal(play.textContent,'回听语音');
});
test('audio callback stops capture if the socket closes before onclose is delivered',async()=>{
  const p=page();await p.run('microphone()');
  p.run("state.calling=true;state.input={id:'active-input-00001',samples:0,seq:0};state.socket.readyState=2");
  assert.doesNotThrow(()=>p.run('pushAudio(new Float32Array(512))'));
  await new Promise(r=>setImmediate(r));
  assert(p.tracks.every(t=>t.stopped));assert.equal(p.run('state.input'),null);
});
test('release-to-send on a closing socket cleans up instead of hanging in recognition',async()=>{
  const p=page();await p.run('microphone()');
  p.run("state.holding=true;state.input={id:'active-input-00001',samples:8000};state.socket.readyState=2");
  assert.doesNotThrow(()=>p.run('commitInput()'));
  await new Promise(r=>setImmediate(r));
  assert(p.tracks.every(t=>t.stopped));assert.equal(p.run('state.pending'),null);
  assert.equal(p.run('state.holding'),false);assert.equal(p.sent.length,0);
});
test('busy-session explanation survives connection-close cleanup',async()=>{
  const p=page();p.sandbox.WebSocket=class{static OPEN=1;constructor(){this.readyState=1}};
  p.run("state.socket=null;$('token').value='local-test-token-0000000001'");
  await p.run('connect()');
  p.run("state.socket.onmessage({data:JSON.stringify({event:'session.failed',code:'SESSION_BUSY'})})");
  await p.run('state.socket.onclose()');
  assert.match(p.nodes.get('status').textContent,/关闭旧页面/);
  assert.equal(p.run('state.connected'),false);
});
