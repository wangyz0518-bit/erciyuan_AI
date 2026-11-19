const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const path=require('node:path');
function player(rate=48000){
  let Processor;const events=[];
  const sandbox={sampleRate:rate,currentTime:0,AudioWorkletProcessor:class{constructor(){this.port={postMessage:m=>events.push(m)};}},registerProcessor:(_,p)=>Processor=p};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../pcm-worklet.js'),'utf8'),sandbox);
  const p=new Processor();
  return {p,events,send:m=>p.port.onmessage({data:m}),render:()=>{const out=new Float32Array(128);p.process([],[[out]]);return out;}};
}
test('short final audio drains with correct duration at device sample rates',()=>{
  for(const rate of [24000,44100,48000,96000]){
    const x=player(rate);x.send({type:'start',id:'a'});
    x.send({type:'append',id:'a',samples:new Float32Array(2400).fill(.25)});
    assert(x.render().every(v=>v===0));
    x.send({type:'end',id:'a'});
    let count=0;for(let i=0;i<100&&!x.p.done;i++)count+=x.render().filter(v=>v!==0).length;
    assert(Math.abs(count-rate/10)<=1,`${rate}: ${count}`);
    assert.equal(x.events.find(e=>e.type==='ended').frames,2400);
    assert.equal(x.events.find(e=>e.type==='ended').underruns,0);
  }
});
test('pause preserves frames; stop flushes and late old chunks cannot play',()=>{
  const x=player();x.send({type:'start',id:'a'});
  x.send({type:'append',id:'a',samples:new Float32Array(5000).fill(.25)});x.render();
  const before=x.p.read;x.send({type:'pause',id:'a',value:true});
  assert(x.render().every(v=>v===0));assert.equal(x.p.read,before);
  x.send({type:'pause',id:'a',value:false});assert(x.render().some(v=>v!==0));
  x.send({type:'stop'});x.send({type:'append',id:'a',samples:new Float32Array(5000).fill(.5)});
  assert(x.render().every(v=>v===0));assert.equal(x.p.queue.length,0);
  x.send({type:'start',id:'b'});x.send({type:'end',id:'a'});assert.equal(x.p.eof,false);
});
test('bounded output reports overflow instead of accumulating unbounded audio',()=>{
  const x=player();x.send({type:'start',id:'a'});
  x.send({type:'append',id:'a',samples:new Float32Array(24000*60+1)});
  assert.equal(x.events[0].type,'overflow');assert.equal(x.p.id,null);
});
