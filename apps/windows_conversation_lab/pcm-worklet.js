// Audio callback owns playback progress. No network/UI waits on this thread.
class PCMOutput extends AudioWorkletProcessor {
  constructor(){
    super(); this.reset(null);
    this.port.onmessage=({data:m})=>{
      if(m.type==='start')this.reset(m.id);
      if(m.type==='stop'){this.reset(null);return;}
      if(m.id!==this.id)return;
      if(m.type==='pause')this.paused=m.value;
      if(m.type==='append'){
        if(this.written+m.samples.length-this.read>24000*60){this.port.postMessage({type:'overflow',id:this.id});this.reset(null);return;}
        this.queue.push(m.samples);this.written+=m.samples.length;
      }
      if(m.type==='end')this.eof=true;
    };
  }
  reset(id){this.id=id;this.queue=[];this.index=0;this.read=0;this.written=0;this.phase=0;this.sample=0;this.eof=false;this.paused=false;this.started=false;this.reported=0;this.done=false;this.underruns=0;}
  next(){
    while(this.queue.length&&this.index>=this.queue[0].length){this.queue.shift();this.index=0;}
    if(!this.queue.length)return null;
    this.read++;return this.queue[0][this.index++];
  }
  process(inputs,outputs){
    const out=outputs[0][0];out.fill(0);
    if(!this.id||this.paused||this.done)return true;
    if(!this.started){
      if(this.written<24000*.18&&!this.eof)return true;
      if(!this.written)return true;
      this.started=true;this.phase=1;
      this.port.postMessage({type:'started',id:this.id,time:currentTime});
    }
    for(let i=0;i<out.length;i++){
      if(this.phase>=1){
        const value=this.next();
        if(value===null){
          if(this.eof){this.done=true;this.port.postMessage({type:'ended',id:this.id,frames:this.read,underruns:this.underruns});}
          else this.underruns++;
          break;
        }
        this.sample=value;this.phase-=1;
      }
      out[i]=this.sample;this.phase+=24000/sampleRate;
    }
    if(this.read-this.reported>=2400){this.reported=this.read;this.port.postMessage({type:'progress',id:this.id,frames:this.read});}
    return true;
  }
}
registerProcessor('pcm-output',PCMOutput);
