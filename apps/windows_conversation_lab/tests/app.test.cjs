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
  sandbox.testSocket={readyState:1,bufferedAmount:0,send:raw=>sent.push(typeof raw==='string'?JSON.parse(raw):raw)};
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

async function callingPage(){
  const p=page();
  let id=0,now=0;
  p.sandbox.crypto.randomUUID=()=>'voice-'+(++id);
  p.sandbox.performance.now=()=>now;
  await p.run('microphone()');p.run('state.calling=true');
  p.at=t=>{now=t;};
  p.frames=(n,value,prob=1)=>{
    for(let i=0;i<n;i++){
      now+=32;
      p.options.onFrameProcessed({isSpeech:prob},new Float32Array(512).fill(value));
    }
  };
  p.event=(event,data)=>p.run('receive('+JSON.stringify(JSON.stringify({event,session_id:'test-session',...data}))+')');
  p.speech=(value)=>{
    p.frames(1,value);p.options.onSpeechStart();p.frames(4,value);
    p.options.onSpeechRealStart();p.frames(6,value);
  };
  p.silence=()=>{p.frames(Math.floor(p.options.redemptionMs/32),0,0);p.options.onSpeechEnd();};
  p.save=(id,prompt)=>{
    p.event('transcript.final',{input_id:id,text:prompt});
    p.event('turn.saved',{turn:{id,prompt,kind:'call',state:'running',reply:''}});
  };
  p.samples=id=>p.sent.filter(x=>x instanceof ArrayBuffer).flatMap(x=>{
    const v=new DataView(x),n=v.getUint32(0),h=JSON.parse(new TextDecoder().decode(new Uint8Array(x,4,n)));
    return h.input_id===id?[v.getInt16(4+n,true)]:[];
  });
  return p;
}
test('two phrases with an in-turn pause reach the same ASR stream, with ordered frames and one commit',async()=>{
  const p=await callingPage();
  assert(p.options.redemptionMs>64*32);
  p.speech(.25);p.frames(64,0,0);p.frames(12,.75);p.silence();
  assert.deepEqual(p.sent.filter(x=>x.command).map(x=>x.command),['input.start','input.commit']);
  const samples=p.samples('voice-1');
  assert.deepEqual(samples,[...Array(11).fill(8192),...Array(64).fill(0),...Array(12).fill(24575),...Array(80).fill(0)]);
});
test('finished second utterance waits through late final until first turn is saved, retaining its beginning',async()=>{
  const p=await callingPage();
  p.speech(.25);p.silence();p.speech(.75);
  p.event('transcript.final',{input_id:'voice-1',text:'第一句'});
  p.silence();assert.deepEqual(p.sent.filter(x=>x.command).map(x=>x.command),['input.start','input.commit']);
  p.event('turn.saved',{turn:{id:'voice-1',prompt:'第一句',kind:'call',state:'running',reply:''}});
  p.save('voice-2','第二句');
  assert.deepEqual(Array.from(p.run('state.rows.values()')).map(x=>x.prompt),['第一句','第二句']);
  assert.deepEqual(p.sent.filter(x=>x.command==='input.commit').map(x=>x.input_id),['voice-1','voice-2']);
  assert.equal(p.sent.some(x=>x.command==='input.abort'),false);
  assert.deepEqual(p.samples('voice-2').filter(x=>x!==0),Array(11).fill(24575));
  assert.equal(p.sent.filter(x=>x.command==='turn.interrupt')[0].reply_id,'voice-1');
});
test('a false speech start during pending recognition preserves the first turn',async()=>{
  const p=await callingPage();p.speech(.25);p.silence();
  p.options.onSpeechStart();p.frames(2,.1);p.options.onVADMisfire();p.save('voice-1','第一句');
  assert.equal(p.run("state.rows.get('voice-1').prompt"),'第一句');
  assert.equal(p.sent.filter(x=>x.command==='input.start').length,1);
  assert(!p.sent.some(x=>x.command==='input.abort'||x.command==='turn.interrupt'));
});
test('confirmed barge-in stops playback immediately, before the new utterance ends',async()=>{
  const p=await callingPage();p.speech(.25);p.silence();p.save('voice-1','先讲一个故事');
  const audio=[];p.sandbox.playerMessage=m=>audio.push(m);
  p.run('state.player.port.postMessage=playerMessage');
  p.event('audio.started',{reply_id:'voice-1',format:'pcm_s16le',sample_rate:24000,channels:1});
  p.options.onSpeechStart();
  assert.equal(audio.at(-1).type,'pause');p.options.onSpeechRealStart();
  assert.equal(audio.at(-1).type,'stop');assert(p.sent.some(x=>x.command==='turn.interrupt'&&x.reply_id==='voice-1'));
  assert.equal(p.run("state.input.id"),'voice-2');
});
test('latency starts at last speech and the first rendered audio, even across later deltas',async()=>{
  const p=await callingPage();p.speech(.25);p.silence();
  p.at(3180);p.save('voice-1','第一句');
  p.at(3380);p.event('reply.delta',{reply_id:'voice-1',delta:'你'});
  p.at(3480);p.event('reply.delta',{reply_id:'voice-1',delta:'好'});
  p.at(4280);p.run("state.player.port.onmessage({data:{type:'started',id:'voice-1'}})");
  assert(p.created.some(n=>n.textContent==='说完到开始播放 3.93 秒'));
  assert(p.created.some(n=>n.textContent==='等待断句 2.56 秒 · 确认转写 0.27 秒 · 等待首字 0.20 秒 · 首字到播放 0.90 秒'));
});
test('failed recognition releases queued utterance; hanging up drops its remaining buffered frames',async()=>{
  const p=await callingPage();p.speech(.25);p.silence();p.speech(.75);
  p.event('input.failed',{input_id:'voice-1',code:'ASR_TIMEOUT'});
  assert.equal(p.samples('voice-2').filter(x=>x!==0).length,11);
  p.silence();p.speech(.5);await p.run('endCall()');
  p.save('voice-2','迟到');assert(!p.sent.some(x=>x.input_id==='voice-3'));
});
