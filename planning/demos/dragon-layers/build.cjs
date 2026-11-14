// Package generated PNG pixels into PSD layers; no segmentation or repainting here.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const { PNG } = require('pngjs');
const { writePsdBuffer, readPsd, initializeCanvas } = require('ag-psd');
const dir = __dirname;
initializeCanvas(() => { throw Error('Unexpected canvas operation'); },
  (width,height) => ({width,height,data:new Uint8ClampedArray(width*height*4)}));
const order = ['body','tail','wing-right','wing-left']; // PSD order is top to bottom.
const checks = [];
const children = order.map(name => {
  const source = fs.readFileSync(path.join(dir,'assets',name+'.png'));
  const png = PNG.sync.read(source);
  let zero=0, partial=0, opaque=0;
  for(let i=3;i<png.data.length;i+=4) {
    if(png.data[i]===0) zero++; else if(png.data[i]===255) opaque++; else partial++;
  }
  assert(zero>0 && zero<png.width*png.height, name+': transparency or content missing');
  checks.push({name,width:png.width,height:png.height,alpha:{zero,partial,opaque},
    sha256:crypto.createHash('sha256').update(source).digest('hex')});
  return {name,top:0,left:0,opacity:1,blendMode:'normal',
    imageData:{width:png.width,height:png.height,data:new Uint8ClampedArray(png.data)}};
});
const {width,height} = children[0].imageData;
assert(children.every(l=>l.imageData.width===width&&l.imageData.height===height),'Mismatched canvases');
const composite = new Uint8ClampedArray(width*height*4);
for(const layer of [...children].reverse()) {
  const pixels = layer.imageData.data;
  for(let i=0;i<pixels.length;i+=4) {
    const a=pixels[i+3]/255, b=composite[i+3]/255, out=a+b*(1-a);
    for(let c=0;c<3;c++) composite[i+c]=out ? Math.round((pixels[i+c]*a+composite[i+c]*b*(1-a))/out):0;
    composite[i+3]=Math.round(out*255);
  }
}
const psd = writePsdBuffer({width,height,channels:4,bitsPerChannel:8,colorMode:3,
  children,imageData:{width,height,data:composite}}, {trimImageData:false,generateThumbnail:false});
fs.mkdirSync(path.join(dir,'build'),{recursive:true});
fs.writeFileSync(path.join(dir,'build','dragon-four-layers.psd'),psd);
const reopened=readPsd(psd,{useImageData:true,skipThumbnail:true});
assert.equal(reopened.children.length,4);
for(let k=0;k<children.length;k++) {
  const before=children[k],after=reopened.children[k];
  assert.equal(after.name,before.name);
  assert.deepEqual(after.imageData.data,before.imageData.data);
}
const result={date:'2026-11-14',width,height,layerOrder:order,checks,psdBytes:psd.length,
  psdRoundTrip:'four layer names and all RGBA pixels preserved',
  scope:'PSD round-trip only; Cubism/runtime results are recorded separately in README.md'};
fs.writeFileSync(path.join(dir,'build','preflight.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify(result,null,2));
