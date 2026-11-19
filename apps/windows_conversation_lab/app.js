const $=id=>document.getElementById(id);
const state={socket:null,connected:false,connectionError:null,role:'xing',session:null,rows:new Map(),
  reply:null,input:null,pending:null,ignored:new Set(),mic:null,micPreparing:null,stream:null,context:null,player:null,
  audioPreparing:null,replay:null,replayUrl:null,replayButton:null,replayEpoch:0,heartbeat:null,cancelMic:null,connectionEpoch:0,submitting:false,
  calling:false,muted:false,holding:false,cancelHold:false,holdY:0,ring:[],micEpoch:0,
  played:0,seq:0,offset:0,metrics:{},voiceRevision:0};
const initialToken=new URLSearchParams(location.hash.slice(1)).get('token');
if(initialToken)$('token').value=initialToken;
history.replaceState(null,'',location.pathname);
function status(text){$('status').textContent=text;}
function metrics(){ $('metrics').textContent=JSON.stringify(state.metrics,null,2); }
function send(packet){
  if(!state.connected||state.socket?.readyState!==WebSocket.OPEN)throw new Error('连接已断开，请重新连接。');
  state.socket.send(JSON.stringify(packet));
}
function trySend(packet){
  // A closing transport must never prevent local stop/cleanup. New user
  // submissions still use send() so delivery failures remain visible.
  if(!state.connected||state.socket?.readyState!==WebSocket.OPEN)return false;
  try{send(packet);return true;}catch{return false;}
}
async function request(path,options={}){
  const r=await fetch(path,{...options,headers:{Authorization:'Bearer '+$('token').value,...options.headers}});
  if(!r.ok)throw new Error((await r.json()).error?.code||'请求失败');
  return r;
}
function stopReplay(){
  state.replayEpoch++;
  state.replay?.pause();state.replay=null;
  if(state.replayButton)state.replayButton.textContent='回听语音';state.replayButton=null;
  if(state.replayUrl)URL.revokeObjectURL(state.replayUrl);state.replayUrl=null;
}
// All times are observed on the same browser clock. Historical turns have no samples.
const timings=new Map();
function mark(id,key){
  const t=timings.get(id);
  if(t && t[key]==null)t[key]=performance.now();
}
function showLatency(box,row){
  const t=timings.get(row.id);if(!t)return;
  const duration=(a,b)=>((b-a)/1000).toFixed(2)+' 秒';
  const parts=[];
  const add=(label,a,b)=>{if(a!=null&&b!=null)parts.push(label+' '+duration(a,b));};
  if(row.kind==='call')add('等待断句',t.end,t.endpoint);
  if(t.endpoint!=null&&t.commit-t.endpoint>=10)add('等待发送',t.endpoint,t.commit);
  add('确认转写',t.commit,t.final);
  add('等待首字',t.final??t.sent,t.first);
  add('首字到播放',t.first,t.play);
  const origin=t.end??t.sent;
  const from={text:'发送',hold:'松手',call:'说完'}[row.kind];
  const summary=document.createElement('summary');
  const terminal=row.state==='interrupted'||row.state==='failed'||row.audio_state==='failed'||row.audio_state==='interrupted';
  if(t.play!=null)summary.textContent=from+'到开始播放 '+duration(origin,t.play);
  else if(t.first!=null)summary.textContent=from+'到首字 '+duration(origin,t.first);
  else summary.textContent=terminal?'本轮未收到首字':'等待首字…';
  const details=document.createElement('details');details.className='latency';details.open=!!t.expanded;
  details.ontoggle=()=>{if(details.isConnected)t.expanded=details.open;};
  const breakdown=document.createElement('div');breakdown.textContent=parts.join(' · ');
  details.append(summary,breakdown);box.append(details);
}
function render(){
  stopReplay();
  const container=$('messages');container.replaceChildren();
  for(const row of state.rows.values()){
    const box=document.createElement('article');box.className='turn';
    const user=document.createElement('div');user.className='user';user.textContent='你 · '+row.prompt;box.append(user);
    if(row.has_recording){
      const play=document.createElement('button');play.textContent='回听语音';
      play.onclick=async()=>{
        let epoch,audio;
        try{
          if(state.replayButton===play){stopReplay();return;}
          if(state.calling||state.holding)throw new Error('请先结束通话或录音。');
          interrupt();
          epoch=state.replayEpoch;
          const blob=await (await request('/v3/recordings/'+encodeURIComponent(row.id))).blob();
          if(epoch!==state.replayEpoch||state.calling||state.holding)return;
          const url=URL.createObjectURL(blob);audio=document.createElement('audio');audio.src=url;
          state.replay=audio;state.replayUrl=url;state.replayButton=play;play.textContent='停止回听';
          audio.onended=()=>{if(state.replay===audio)stopReplay();};await audio.play();
        }catch(e){
          if(epoch!==undefined&&epoch!==state.replayEpoch)return;
          if(audio&&state.replay===audio)stopReplay();status(e.message);
        }
      };box.append(play);
    }
    const reply=document.createElement('div');reply.className='assistant';reply.textContent=(state.role==='xing'?'小星':'小月')+' · '+(row.reply||(row.state==='interrupted'?'已打断':row.state==='failed'?'回复失败':'正在想…'));box.append(reply);
    const badge=document.createElement('div');badge.className='badge';
    badge.textContent=({text:'打字',hold:'语音消息',call:'通话'}[row.kind]||'')+' · '+
      ({running:'正在回复',complete:'文字已保存',interrupted:'已打断',failed:'回复失败'}[row.state]||row.state)+
      (row.audio_state==='interrupted'?' · 播报已打断':'')+(row.code?' · '+row.code:'');
    box.append(badge);showLatency(box,row);container.append(box);
  }
  container.scrollTop=container.scrollHeight;
}
function pauseOutput(value){if(state.reply)state.player?.port.postMessage({type:'pause',id:state.reply,value});}
function stopLocal(){
  stopReplay();
  state.player?.port.postMessage({type:'stop'});
  state.metrics.localStopRequested=performance.now();metrics();
}
function interrupt(){
  const rid=state.reply;stopLocal();
  if(rid){
    state.ignored.add(rid);state.reply=null;
    trySend({command:'playback.progress',reply_id:rid,frames:state.played});
    trySend({command:'turn.interrupt',reply_id:rid});
    const row=state.rows.get(rid);if(row){row.audio_state='interrupted';if(row.state==='running')row.state='interrupted';render();}
  }
}
function abortInput(){
  const id=state.input?.id||state.pending;
  state.input=null;state.pending=null;
  if(id){state.ignored.add(id);trySend({command:'input.abort',input_id:id});}
  $('transcript').textContent='';
}
function beginInput(kind,id=crypto.randomUUID()){
  send({command:'input.start',input_id:id,kind});
  state.input={id,seq:0,samples:0,kind};
}
function pushAudio(frame){
  const input=state.input;if(!input)return;
  if(!state.connected||state.socket?.readyState!==WebSocket.OPEN){captureFailed();return;}
  if(input.samples+frame.length>16000*30){
    commitInput();status('本段已达 30 秒，正在识别。请稍后继续。');return;
  }
  if(state.socket.bufferedAmount>96000){abortInput();status('网络发送积压，本段未发送，请重试。');return;}
  const header=new TextEncoder().encode(JSON.stringify({input_id:input.id,seq:input.seq++}));
  const bytes=new ArrayBuffer(4+header.length+frame.length*2),view=new DataView(bytes);
  view.setUint32(0,header.length);new Uint8Array(bytes,4,header.length).set(header);
  for(let i=0;i<frame.length;i++)view.setInt16(4+header.length+i*2,Math.round(Math.max(-1,Math.min(1,frame[i]))*32767),true);
  try{state.socket.send(bytes);input.samples+=frame.length;}catch{captureFailed();}
}
function captureFailed(){
  endCall().then(()=>status('连接已断开，录音和播放已停止。本段未自动重发。')).catch(e=>status(e.message));
}
function commitInput(){
  const input=state.input;if(!input)return;
  if(!state.connected||state.socket?.readyState!==WebSocket.OPEN){captureFailed();return;}
  if(input.samples<3200){abortInput();status('录音太短，请再说一次。');return;}
  const now=performance.now();
  if(input.kind==='hold')timings.set(input.id,{end:now});
  mark(input.id,'commit');
  state.input=null;state.pending=input.id;
  try{send({command:'input.commit',input_id:input.id});status('正在确认你说的话…');}catch{captureFailed();}
}
async function setupAudio(){
  if(state.context){await state.context.resume();return;}
  if(state.audioPreparing)return state.audioPreparing;
  state.audioPreparing=createAudio();
  try{await state.audioPreparing;}finally{state.audioPreparing=null;}
}
async function createAudio(){
  const context=new AudioContext({latencyHint:'interactive'});
  if(context.sampleRate<24000){await context.close();throw new Error('当前声音设备采样率不受支持。');}
  try{await context.audioWorklet.addModule('/conversation-lab/pcm-worklet.js');}catch(e){await context.close();throw e;}
  const player=new AudioWorkletNode(context,'pcm-output',{numberOfInputs:0,numberOfOutputs:1,outputChannelCount:[1]});
  player.connect(context.destination);
  state.context=context;state.player=player;
  player.port.onmessage=({data:m})=>{
    if(m.id!==state.reply)return;
    if(m.type==='started'){mark(m.id,'play');render();state.metrics.firstRenderMs=performance.now()-state.metrics.replyStarted;metrics();status(state.calling?'正在说话，你可以直接插话。':'正在朗读…');}
    if(m.type==='progress'){state.played=m.frames;trySend({command:'playback.progress',reply_id:m.id,frames:m.frames});}
    if(m.type==='ended'){
      state.played=m.frames;state.metrics.underruns=m.underruns;metrics();
      // Render progress is an estimate of device output, not evidence of hearing.
      setTimeout(()=>{if(m.id===state.reply)trySend({command:'playback.progress',reply_id:m.id,frames:m.frames,complete:true});},(context.baseLatency+(context.outputLatency||0))*1000);
    }
    if(m.type==='overflow'){interrupt();status('播放缓冲已满，已停止本轮，请重试。');}
  };
  await context.resume();
}
async function microphone(){
  if(state.micPreparing)return state.micPreparing;
  if(state.mic)return true;
  if(!state.connected)throw new Error('请先连接服务。');
  if(!globalThis.vad)throw new Error('语音检测资源未安装，请运行启动脚本。');
  let timer;
  const cancelled=new Promise(resolve=>{state.cancelMic=()=>resolve(false);});
  state.micPreparing=Promise.race([prepareMic(),cancelled,new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('麦克风准备超时，请在 Edge/Chrome 中检查麦克风权限与输入设备。')),25000);})]);
  try{return await state.micPreparing;}catch(e){await releaseMic();throw e;}finally{clearTimeout(timer);state.micPreparing=null;state.cancelMic=null;}
}
// A single upstream recognizer accepts PCM until commit. Keep later utterances
// locally, in order, until the preceding turn is saved or its recognition fails.
const callQueue=[];
let capturing=null, drainTimer;
const MAX_SEGMENT=16000*30;
function clearCallQueue(){
  clearTimeout(drainTimer);drainTimer=null;capturing=null;callQueue.length=0;
}
function newSegment(frames,confirmed){
  if(callQueue.length>=5){
    status('待识别语音已满，当前新片段未收录，请稍后再说。');
    return;
  }
  const id=crypto.randomUUID();
  capturing={id,frames:[...frames],samples:frames.reduce((n,f)=>n+f.length,0),
    confirmed,closed:false,lastSpeech:performance.now()};
  callQueue.push(capturing);
}
function closeSegment(){
  if(!capturing)return;
  capturing.closed=true;
  timings.set(capturing.id,{end:capturing.lastSpeech,endpoint:performance.now()});
  capturing=null;
}
function drainCall(){
  const next=callQueue[0];
  if(!next?.confirmed||state.pending||!state.calling||state.muted)return;
  try{
    if(!state.input)beginInput('call',next.id);
    if(state.input.id!==next.id)return;
    while(next.frames.length){
      if(state.socket.bufferedAmount>64000){
        if(!drainTimer)drainTimer=setTimeout(()=>{drainTimer=null;drainCall();},25);
        return;
      }
      pushAudio(next.frames.shift());
      if(!state.input)return;
    }
    if(next.closed){callQueue.shift();commitInput();}
  }catch{captureFailed();}
}
function discardSegment(id){
  if(capturing?.id===id)capturing=null;
  const index=callQueue.findIndex(s=>s.id===id);
  if(index>=0)callQueue.splice(index,1);
}
function callFrame(prob,frame){
  if(!capturing)return;
  if(capturing.samples+frame.length>MAX_SEGMENT){
    closeSegment();newSegment([],true);
    if(!capturing)return;
  }
  capturing.frames.push(frame.slice());capturing.samples+=frame.length;
  if(prob.isSpeech>=.35)capturing.lastSpeech=performance.now();
  drainCall();
}
async function prepareMic(){
  const epoch=++state.micEpoch;$('microphone').textContent='取消麦克风准备';status('正在准备麦克风和本地语音检测…');
  await setupAudio();
  ort.env.wasm.numThreads=1;
  let stream;
  const capture=async()=>{
    const next=await navigator.mediaDevices.getUserMedia({audio:{channelCount:1,echoCancellation:true,noiseSuppression:true,autoGainControl:true}});
    if(epoch!==state.micEpoch){next.getTracks().forEach(t=>t.stop());throw new Error('麦克风准备已取消。');}
    stream=next;state.stream=next;const settings=next.getAudioTracks()[0].getSettings();
    state.metrics.microphone={echoCancellation:settings.echoCancellation,noiseSuppression:settings.noiseSuppression,sampleRate:settings.sampleRate};metrics();return next;
  };
  const stopStream=async current=>{current?.getTracks().forEach(t=>t.stop());if(state.stream===current)state.stream=null;};
  let mic;
  try{
  mic=await vad.MicVAD.new({model:'v5',startOnLoad:false,audioContext:state.context,
    baseAssetPath:'/conversation-assets/vad/',onnxWASMBasePath:'/conversation-assets/ort/',
    positiveSpeechThreshold:.65,negativeSpeechThreshold:.35,minSpeechMs:160,redemptionMs:2560,preSpeechPadMs:320,
    submitUserSpeechOnPause:false,
    getStream:capture,resumeStream:capture,pauseStream:stopStream,
    onFrameProcessed:(prob,frame)=>{
      if(epoch!==state.micEpoch||state.muted)return;
      if(state.calling)callFrame(prob,frame);
      else if(state.input)pushAudio(frame);
      state.ring.push(frame.slice());if(state.ring.length>10)state.ring.shift();
    },
    onSpeechStart:()=>{
      if(epoch!==state.micEpoch||!state.calling||state.muted)return;
      newSegment(state.ring,false);if(capturing){pauseOutput(true);status('在听，请继续…');}
    },
    onSpeechRealStart:()=>{if(epoch===state.micEpoch&&state.calling&&!state.muted&&capturing){capturing.confirmed=true;interrupt();drainCall();status('在听，请继续…');}},
    onVADMisfire:()=>{if(epoch===state.micEpoch&&state.calling&&capturing&&!capturing.confirmed){discardSegment(capturing.id);pauseOutput(false);status('继续聆听…');}},
    onSpeechEnd:()=>{if(epoch===state.micEpoch&&state.calling&&!state.muted){closeSegment();drainCall();}},
  });
  if(epoch!==state.micEpoch){await mic.destroy();await stopStream(stream);return false;}
  await mic.start();
  if(epoch!==state.micEpoch){await mic.destroy();await stopStream(stream);return false;}
  state.mic=mic;$('microphone').textContent='麦克风已就绪';status('麦克风已就绪。可按住说话，或开始连续通话。');return true;
  }catch(e){await stopStream(stream);if(mic)await mic.destroy();throw e;}
}
async function releaseMic(){
  ++state.micEpoch;const mic=state.mic;state.mic=null;
  state.cancelMic?.();state.cancelMic=null;
  state.stream?.getTracks().forEach(t=>t.stop());state.stream=null;state.ring=[];
  if(mic)await mic.destroy();$('microphone').textContent='启用麦克风';
}
async function endCall(release=true,announce=true){
  state.calling=false;state.holding=false;state.muted=false;
  clearCallQueue();abortInput();interrupt();$('hold').classList.remove('recording');$('call').textContent='连续通话';$('mute').disabled=true;$('mute').textContent='静音麦克风';
  if(release)await releaseMic();if(announce)status('已结束通话。');
}
async function disconnect(){
  clearInterval(state.heartbeat);state.heartbeat=null;
  await endCall();const socket=state.socket;
  if(!socket)return;
  const closed=new Promise((resolve,reject)=>{
    if(socket.readyState===WebSocket.CLOSED){resolve();return;}
    const timer=setTimeout(()=>{socket.close();reject(new Error('旧连接尚未释放，请稍后重试。'));},5000);
    socket.addEventListener('close',()=>{clearTimeout(timer);resolve();},{once:true});
  });
  if(state.connected&&socket.readyState===WebSocket.OPEN)send({command:'session.end'});else socket.close();
  await closed;
  if(state.socket===socket)state.socket=null;
  state.connected=false;
}
async function connect(){
  const epoch=++state.connectionEpoch;
  if(state.socket)await disconnect();
  if(epoch!==state.connectionEpoch)return;
  state.connected=false;state.connectionError=null;state.session=null;state.reply=null;state.ignored.clear();
  if($('token').value.length<24)throw new Error('请通过启动脚本打开，或填写本机访问令牌。');
  const socket=new WebSocket(`${location.protocol==='https:'?'wss':'ws'}://${location.host}/v3/conversations/${state.role}/stream`);
  socket.binaryType='arraybuffer';state.socket=socket;
  socket.onopen=()=>{if(socket===state.socket&&socket.readyState===WebSocket.OPEN)socket.send(JSON.stringify({command:'session.start',token:$('token').value}));};
  socket.onmessage=({data})=>{if(socket!==state.socket)return;try{receive(data);}catch(e){state.connectionError=e.message;status(e.message);endCall(true,false).catch(()=>{});socket.close();}};
  socket.onclose=()=>{
    if(socket!==state.socket)return;
    clearInterval(state.heartbeat);state.heartbeat=null;state.connected=false;
    const message=state.connectionError||'连接已断开，录音与播放已停止。没有自动重发。';
    $('connection').textContent='已断开';status(message);
    return endCall(true,false).catch(e=>{if(socket===state.socket)status(message+' '+e.message);});
  };
  socket.onerror=()=>{if(socket===state.socket)status('无法连接本机服务，请检查启动窗口。');};
}
function receive(data){
  if(data instanceof ArrayBuffer){
    if(data.byteLength<5)throw new Error('无效音频帧');
    const view=new DataView(data),size=view.getUint32(0);
    if(size>4096||size+4>=data.byteLength||(data.byteLength-size-4)%2)throw new Error('无效音频帧');
    const m=JSON.parse(new TextDecoder().decode(new Uint8Array(data,4,size)));
    if(m.session_id!==state.session||m.reply_id!==state.reply||state.ignored.has(m.reply_id))return;
    if(m.seq!==state.seq||m.offset!==state.offset)throw new Error('音频顺序异常，已停止播放。');
    const samples=new Float32Array((data.byteLength-size-4)/2);
    for(let i=0;i<samples.length;i++)samples[i]=view.getInt16(size+4+i*2,true)/32768;
    state.seq++;state.offset+=samples.length*2;
    state.player.port.postMessage({type:'append',id:m.reply_id,samples},[samples.buffer]);return;
  }
  const m=JSON.parse(data);
  if(m.event==='session.ready'){
    state.connected=true;state.session=m.session_id;state.rows=new Map(m.history.map(r=>[r.id,r]));render();
    $('connection').textContent=m.mode==='live'?'已连接 · 真实模型':'已连接 · 模拟模式（不能识别真实语音）';
    clearInterval(state.heartbeat);state.heartbeat=setInterval(()=>trySend({command:'session.ping'}),30000);
    status('可以打字聊天；启用麦克风后可使用语音。');loadVoices().catch(e=>status(e.message));return;
  }
  if(m.event==='session.failed'){
    state.connectionError=({SESSION_BUSY:'另一个聊天页面正在使用服务。请关闭旧页面，再点击连接。',UNAUTHORIZED:'本机访问令牌无效，请关闭此页面并通过启动脚本重新打开。'}[m.code]||'连接未建立：'+m.code);
    status(state.connectionError);return;
  }
  if(m.session_id!==state.session)return;
  if(m.reply_id&&state.ignored.has(m.reply_id))return;
  if(m.input_id&&state.ignored.has(m.input_id))return;
  if(m.turn&&state.ignored.has(m.turn.id))return;
  switch(m.event){
    case 'input.ready':break;
    case 'transcript.partial':if(m.input_id===(state.input?.id||state.pending))$('transcript').textContent=m.text;break;
    case 'transcript.final':if(m.input_id===state.pending){mark(m.input_id,'final');$('transcript').textContent=m.text;}break;
    case 'turn.saved':
      if(m.turn.id===state.pending)state.pending=null;
      state.rows.set(m.turn.id,m.turn);state.reply=m.turn.id;state.played=0;state.metrics.replyStarted=performance.now();
      render();status('正在想…');
      if(callQueue.some(s=>s.confirmed))interrupt();
      drainCall();break;
    case 'reply.delta':{const row=state.rows.get(m.reply_id);if(row){if(m.delta)mark(m.reply_id,'first');row.reply+=m.delta;render();}break;}
    case 'reply.saved':{const row=state.rows.get(m.reply_id);if(row){row.reply=m.text;row.state='complete';render();}break;}
    case 'audio.started':
      if(m.format!=='pcm_s16le'||m.sample_rate!==24000||m.channels!==1||!state.player)throw new Error('播放设备尚未准备好。');
      state.reply=m.reply_id;state.played=0;state.seq=0;state.offset=0;state.player.port.postMessage({type:'start',id:m.reply_id});if(capturing)pauseOutput(true);break;
    case 'audio.completed':
      if(m.total_frames*2!==state.offset||m.chunks!==state.seq)throw new Error('音频不完整，已停止播放。');
      state.player?.port.postMessage({type:'end',id:m.reply_id});break;
    case 'turn.completed':{const row=state.rows.get(m.reply_id);if(row){row.audio_state=$('speak').checked||row.kind!=='text'?'played':'disabled';render();}if(state.reply===m.reply_id)state.reply=null;status(state.calling?'继续聆听，你可以接着说。':'回复完成。');break;}
    case 'turn.failed':{const row=state.rows.get(m.reply_id);if(row){row.code=m.code;row.audio_state='failed';if(row.state!=='complete')row.state='failed';render();}stopLocal();state.reply=null;status('本轮未完成：'+m.code+'。可重新发送。');break;}
    case 'input.failed':if(m.input_id===(state.input?.id||state.pending)){state.input=null;state.pending=null;discardSegment(m.input_id);pauseOutput(false);status('语音识别未完成：'+m.code+'。请重新说话。');drainCall();}break;
    case 'request.failed':
      if(m.input_id&&m.input_id===(state.input?.id||state.pending)){discardSegment(m.input_id);abortInput();pauseOutput(false);drainCall();}
      if(m.request_id===state.reply){stopLocal();state.ignored.add(state.reply);state.reply=null;}
      status('请求未完成：'+m.code);break;
  }
}
async function loadVoices(){
  const role=state.role,session=state.session;
  const [catalog,binding]=await Promise.all([request('/v1/voice-profiles').then(r=>r.json()),request('/v1/characters/'+role+'/voice-binding').then(r=>r.json())]);
  if(role!==state.role||session!==state.session)return;
  state.voiceRevision=binding.revision;const select=$('voice');select.replaceChildren(new Option('默认声音',''));
  for(const p of catalog.items)if(p.status==='ready')select.add(new Option(p.name,p.id));
  select.value=binding.profile_id||'';$('voiceStatus').textContent=binding.name||'默认声音';
}
function run(fn){return (...args)=>Promise.resolve().then(()=>fn(...args)).catch(e=>status(e.message));}
$('connect').onclick=run(connect);
$('microphone').onclick=run(async()=>{
  if(state.micPreparing||state.mic){await endCall();status('麦克风已关闭。');return;}
  await microphone();
});
$('send').onclick=run(async()=>{
  if(state.submitting)return;
  if(state.calling||state.holding)throw new Error('请先结束当前录音或通话，再打字发送。');
  const text=$('text').value.trim();if(!text)return;
  state.submitting=true;
  try{
  if($('speak').checked)await setupAudio();interrupt();abortInput();
  const id=crypto.randomUUID();state.reply=id;state.played=0;
  timings.set(id,{sent:performance.now()});
  send({command:'chat.send',request_id:id,text,speak:$('speak').checked});$('text').value='';
  }finally{state.submitting=false;}
});
$('text').onkeydown=e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.isComposing){e.preventDefault();$('send').click();}};
$('hold').onpointerdown=e=>{
  if(!state.mic||!state.connected||state.calling){status('请先启用麦克风，并结束连续通话。');return;}
  e.preventDefault();$('hold').setPointerCapture(e.pointerId);interrupt();
  try{
    if(state.pending||state.input)abortInput();
    beginInput('hold');state.holding=true;state.cancelHold=false;state.holdY=e.clientY;$('hold').classList.add('recording');status('正在录音，松开发送，向上拖动取消。');
  }catch{captureFailed();}
};
$('hold').onpointermove=e=>{if(state.holding){state.cancelHold=e.clientY<state.holdY-55;status(state.cancelHold?'松开取消发送':'正在录音，松开发送。');}};
function releaseHold(cancel=false){if(!state.holding)return;state.holding=false;$('hold').classList.remove('recording');if(cancel||state.cancelHold){abortInput();status('已取消录音。');}else commitInput();}
$('hold').onpointerup=()=>releaseHold();$('hold').onpointercancel=()=>releaseHold(true);
$('call').onclick=run(async()=>{
  if(state.calling){await endCall();return;}
  if(state.holding)return;if(!await microphone()||!state.connected)return;interrupt();abortInput();
  state.calling=true;state.muted=false;state.ring=[];$('call').textContent='结束通话';$('mute').disabled=false;status('正在聆听，直接说话即可。');
});
$('mute').onclick=run(async()=>{
  if(!state.calling||!state.mic)return;
  const mic=state.mic,epoch=state.micEpoch;$('mute').disabled=true;
  state.muted=!state.muted;clearCallQueue();abortInput();state.ring=[];
  try{if(state.muted)await mic.pause();else await mic.start();}
  catch(e){await endCall();throw e;}
  finally{if(state.calling)$('mute').disabled=false;}
  if(epoch!==state.micEpoch){await mic.destroy();return;}
  $('mute').textContent=state.muted?'恢复麦克风':'静音麦克风';status(state.muted?'麦克风已静音。':'继续聆听…');
});
$('stop').onclick=()=>{interrupt();status('已停止朗读。');};
$('character').onchange=run(async()=>{await endCall();state.role=$('character').value;await connect();});
$('applyVoice').onclick=run(async()=>{
  if(state.calling||state.input||state.pending||state.reply)throw new Error('请等待当前回复结束，再切换声音。');
  const role=state.role,epoch=state.connectionEpoch,profile=$('voice').value||null,revision=state.voiceRevision;
  // Release the session lease while changing the shared voice binding.
  await disconnect();
  if(role!==state.role||epoch!==state.connectionEpoch)return;
  await request('/v1/characters/'+role+'/voice-binding',{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({profile_id:profile,revision})});
  if(role===state.role&&epoch===state.connectionEpoch)await connect();
});
document.addEventListener('visibilitychange',()=>{if(document.hidden){endCall();state.socket?.close();}});
window.addEventListener('pagehide',()=>{state.stream?.getTracks().forEach(t=>t.stop());state.socket?.close();});
if(initialToken)connect().catch(e=>status(e.message));
