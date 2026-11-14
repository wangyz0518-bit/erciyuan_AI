// Package Cubism Editor exports; this script never synthesizes or edits MOC3.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const root = __dirname, name = 'dragon-four-layers';
const src = path.join(root, 'build'), dst = path.join(root, 'runtime');
fs.mkdirSync(dst, {recursive:true});
fs.mkdirSync(path.join(root,'source'), {recursive:true});
const moc = fs.readFileSync(path.join(src,name+'.moc3'));
assert.equal(moc.subarray(0,4).toString(),'MOC3','Expected real Cubism export');
const model = JSON.parse(fs.readFileSync(path.join(src,name+'.model3.json'),'utf8'));
const display = JSON.parse(fs.readFileSync(path.join(src,model.FileReferences.DisplayInfo),'utf8'));
assert(display.Parameters.some(p=>p.Id==='ParamAppendageSway'));
for (const f of [model.FileReferences.Moc, model.FileReferences.DisplayInfo, ...model.FileReferences.Textures]) {
  assert(!path.isAbsolute(f) && !f.split(/[\\/]/).includes('..'));
  fs.mkdirSync(path.dirname(path.join(dst,f)),{recursive:true});
  fs.copyFileSync(path.join(src,f),path.join(dst,f));
}
fs.copyFileSync(path.join(src,name+'.cmo3'),path.join(root,'source',name+'.cmo3'));
// Hand-authored six-second periodic cubic curve, not a CAN3 export.
// The value and first derivative agree at the loop boundary.
const motion = {
  Version:3,
  Meta:{Duration:6,Fps:30,Loop:true,AreBeziersRestricted:true,CurveCount:1,
    TotalSegmentCount:4,TotalPointCount:13,UserDataCount:0,TotalUserDataSize:0},
  FadeInTime:0.4,FadeOutTime:0.4,
  Curves:[{Target:'Parameter',Id:'ParamAppendageSway',Segments:[
    0,0,
    1,0.5,15.708,1,30,1.5,30,
    1,2,30,2.5,15.708,3,0,
    1,3.5,-15.708,4,-30,4.5,-30,
    1,5,-30,5.5,-15.708,6,0
  ]}],
  UserData:[]
};
fs.mkdirSync(path.join(dst,'motions'),{recursive:true});
fs.writeFileSync(path.join(dst,'motions','idle.motion3.json'),JSON.stringify(motion,null,2)+'\n');
model.FileReferences.Motions={Idle:[{File:'motions/idle.motion3.json',FadeInTime:0.4,FadeOutTime:0.4}]};
fs.writeFileSync(path.join(dst,name+'.model3.json'),JSON.stringify(model,null,2)+'\n');
console.log(JSON.stringify({mocBytes:moc.length,mocSha256:crypto.createHash('sha256').update(moc).digest('hex'),
  parameter:'ParamAppendageSway',motionSeconds:6,source:'Cubism Editor 5.3.00; export SDK 5.0',
  motionSource:'hand-authored motion3.json; no CAN3'},null,2));
