import io, zipfile, os, sys, urllib.request, pathlib, shutil
url='https://github.com/nihui/rife-ncnn-vulkan/releases/download/20221029/rife-ncnn-vulkan-20221029-windows.zip'
size=431540241
class Remote(io.RawIOBase):
    def __init__(self): self.pos=0; self.cache=None
    def seekable(self): return True
    def tell(self): return self.pos
    def seek(self,n,w=0): self.pos=[n,self.pos+n,size+n][w];return self.pos
    def read(self,n=-1):
        if n<0:n=size-self.pos
        n=min(n,size-self.pos)
        if n<=0:return b''
        if self.cache and self.cache[0]<=self.pos and self.pos+n<=self.cache[0]+len(self.cache[1]):
            off=self.pos-self.cache[0];self.pos+=n;return self.cache[1][off:off+n]
        beg=self.pos;end=min(size-1,max(beg+n-1,beg+524287))
        req=urllib.request.Request(url+'?r='+str(beg),headers={'Range':f'bytes={beg}-{end}','User-Agent':'Codex-render'})
        with urllib.request.urlopen(req,timeout=30) as resp:
            if resp.status!=206:raise ValueError((resp.status,resp.headers.get('Content-Range')))
            data=resp.read()
        self.cache=(beg,data);self.pos+=n;return data[:n]
with zipfile.ZipFile(Remote()) as z:
    for n in z.namelist():
        if n.endswith('/') or not ('rife-v4.6/' in n or n.endswith('rife-ncnn-vulkan.exe') or n.lower().endswith('.dll')):continue
        rel=n.split('/',1)[-1];path=pathlib.Path(sys.argv[1])/rel
        path.parent.mkdir(parents=True,exist_ok=True)
        with z.open(n) as f,path.open('wb') as o: shutil.copyfileobj(f,o,8*1024*1024)
        print(rel,path.stat().st_size,flush=True)
