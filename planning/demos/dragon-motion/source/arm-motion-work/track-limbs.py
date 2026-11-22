import re,sys, pathlib
w=pathlib.Path(sys.argv[1]);sys.path.insert(0,str(w/'motion-analysis'))
import cv2, numpy as np
cv2.setNumThreads(2)
source=(w/'Guided.cs').read_text('utf-8-sig')
part=source.split('string spec; if(left){')[1].split('var raw=spec.Split')[0]
ls,rs=part.split('}else{')
def get(s,side):
    z={}
    for keys, coords in re.findall(r'((?:case "[^"]+":|default:)+)spec="([^"]+)"',s):
        codes=re.findall(r'"([^"]+)"',keys) or ['default']
        arr=np.array(list(map(float,coords.split()))).reshape(-1,2)
        for key in codes:z[key]=arr*(632/626)+np.array([-16,89])
    return z
bones=[get(rs,'R'),get(ls,'L')]
out=w/'masks';out.mkdir(exist_ok=True)
YY,XX=np.mgrid[:720,:600]
xy=np.stack((XX,YY),axis=-1).astype(float)
for file in (w/'plates').glob('*.png'):
    n=file.stem
    im=cv2.imread(str(file));B,G,R=im[:,:,0].astype(int),im[:,:,1].astype(int),im[:,:,2].astype(int)
    for side,lookup in enumerate(bones):
        pts=lookup.get(n,lookup.get('default')); width=[(26,23),(22,15),(15,22),(20,11)]
        if pts is None: continue
        dist=np.ones((720,600))*10
        for j,(v0,v1) in enumerate(zip(pts,pts[1:])):
            d=v1-v0;u=np.clip(np.sum((xy-v0)*d,axis=2)/np.sum(d*d),0,1)
            rad=width[j][0]*(1-u)+width[j][1]*u
            metric=np.linalg.norm(xy-(v0+u[:,:,None]*d),axis=2)/rad
            dist=np.minimum(dist,metric)
        valid=dist<1.36
        skin=(R-G>8)&(R-B>12)&(R>115)
        prob=np.zeros((720,600),np.uint8)
        prob[valid]=cv2.GC_PR_BGD
        prob[valid & skin & (dist<1.20)]=cv2.GC_PR_FGD
        prob[(dist<.41)&skin]=cv2.GC_FGD
        prob[(dist>1.24)&(~skin)]=cv2.GC_BGD
        ys,xs=np.where(valid); y0=max(0,ys.min()-7); y1=min(720,ys.max()+8);x0=max(0,xs.min()-7); x1=min(600,xs.max()+8)
        roi=prob[y0:y1,x0:x1].copy()
        cv2.grabCut(im[y0:y1,x0:x1].copy(),roi,None,np.zeros((1,65)),np.zeros((1,65)),4,cv2.GC_INIT_WITH_MASK)
        prob[y0:y1,x0:x1]=roi
        mask=np.uint8((prob==1)|(prob==3))*255
        mask=cv2.morphologyEx(mask,cv2.MORPH_CLOSE,np.ones((3,3),np.uint8))
        mask=cv2.GaussianBlur(cv2.dilate(mask,np.ones((2,2),np.uint8)),(3,3),.55)
        mask.tofile(out/(n+('R' if side==0 else 'L')+'.raw'))
    print(n,end=' ',flush=True)
