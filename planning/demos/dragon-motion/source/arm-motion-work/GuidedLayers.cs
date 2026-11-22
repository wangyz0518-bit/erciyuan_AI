using System;
using System.IO;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Globalization;
class Guided {
 struct P {
  public double x,y;
  public P(double x,double y){this.x=x;this.y=y;}
  public static P operator +(P a,P b){return new P(a.x+b.x,a.y+b.y);}
  public static P operator -(P a,P b){return new P(a.x-b.x,a.y-b.y);}
  public static P operator *(P a,double t){return new P(a.x*t,a.y*t);}
  public double sq{get{return x*x+y*y;}}
 }
 static P[] Bones(string name,bool left){
  string spec; if(left){
   switch(name){
    case "V":spec="244 258 204 389 240 430 277 450 311 483";break;
    case "M":spec="246 258 229 398 304 427 347 439 386 465";break;
    case "H":spec="248 267 233 408 318 438 359 443 399 457";break;
    default:spec="250 262 222 393 180 517 168 559 171 611";break;
   }
  }else{
   switch(name){
    case "I":case "B":spec="386 258 422 389 467 534 476 567 469 611";break;
    case "A":spec="386 256 454 369 420 483 422 525 421 564";break;
    case "J":spec="387 255 451 376 429 411 414 445 394 471";break;
    case "L":spec="386 269 432 386 379 412 347 422 309 431";break;
    case "C":spec="388 255 439 388 375 365 344 348 310 326";break;
    case "K":spec="386 254 429 374 390 291 362 268 329 258";break;
    case "T":spec="387 258 408 383 369 254 353 233 334 214";break;
    case "F":spec="386 253 403 381 448 292 437 267 412 240";break;
    case "U":spec="387 255 395 384 442 284 468 261 493 238";break;
    case "G":spec="387 254 407 399 483 361 516 362 556 349";break;
    case "S":case "O":spec="387 258 410 400 499 329 539 334 590 329";break;
    case "V":spec="386 255 436 381 389 296 350 277 309 282";break;
    case "M":spec="386 258 424 386 380 288 353 267 323 249";break;
    case "H":spec="394 265 423 395 390 299 352 280 314 266";break;
    default:throw new Exception(name);
   }
  }
  var raw=spec.Split(' ');var p=new P[5];for(int i=0;i<5;i++)p[i]=new P(-16+int.Parse(raw[2*i])*632.0/626,89+int.Parse(raw[2*i+1])*632.0/626);return p;
 }
 static double Dot(P a,P b){return a.x*b.x+a.y*b.y;}
 static P Mix(P a,P b,double t){return a*(1-t)+b*t;}
 static P[] Knots(P[] a,P[] b,double t){
  P[] v=new P[5];v[0]=Mix(a[0],b[0],t);
  for(int i=1;i<5;i++){P e=a[i]-a[i-1],f=b[i]-b[i-1];
   double an=Math.Atan2(e.y,e.x),dn=Math.Atan2(f.y,f.x)-an;
   while(dn>Math.PI)dn-=2*Math.PI;while(dn< -Math.PI)dn+=2*Math.PI; double len=Math.Sqrt(e.sq)*(1-t)+Math.Sqrt(f.sq)*t;
   v[i]=v[i-1]+new P(Math.Cos(an+dn*t),Math.Sin(an+dn*t))*len;}
  return v;
 }
 static List<P> Rails(P[] p){
  var l=new List<P>();double[] radius={13,10,7,5};
  foreach(P v in p)l.Add(v);
  for(int j=0;j<4;j++){
   var e=p[j+1]-p[j];double length=Math.Sqrt(e.sq);
   P n=new P(-e.y/length,e.x/length);
   foreach(double f in new double[]{.26,.72}){P c=Mix(p[j],p[j+1],f);l.Add(c);l.Add(c+n*radius[j]);l.Add(c-n*radius[j]);}
  }
  return l;
 }
 static double Dist(P v,P[] p){
  double m=1e9;
  for(int i=0;i<4;i++){P e=p[i+1]-p[i];double u=Math.Max(0,Math.Min(1,Dot(v-p[i],e)/e.sq));m=Math.Min(m,(v-(p[i]+e*u)).sq);}
  return Math.Sqrt(m);
 }
 static P MLS(P v,List<P> from,List<P> to){
  double sw=0,sx=0,sy=0,tx=0,ty=0,spp=0,sdot=0,scross=0;
  for(int i=0;i<from.Count;i++){
   P p=from[i],q=to[i];double d=(p-v).sq+4;double w=1/(d*d);
   sw+=w;sx+=w*p.x;sy+=w*p.y;tx+=w*q.x;ty+=w*q.y;spp+=w*(p.x*p.x+p.y*p.y);sdot+=w*(p.x*q.x+p.y*q.y);scross+=w*(p.x*q.y-p.y*q.x);
  }
  double px=sx/sw,py=sy/sw,qx=tx/sw,qy=ty/sw,den=spp-(sx*px+sy*py);
  double aa=(sdot-sx*qx-sy*qy)/Math.Max(1e-14,den),bb=(scross-sx*qy+sy*qx)/Math.Max(1e-14,den);
  return new P(qx+aa*(v.x-px)-bb*(v.y-py),qy+bb*(v.x-px)+aa*(v.y-py));
 }
 const int W=600,H=720,k=5;
 static byte[] Raw(string p){
  using(var b=new Bitmap(p)){byte[] buf=new byte[W*H*3];var l=b.LockBits(new Rectangle(0,0,W,H),ImageLockMode.ReadOnly,PixelFormat.Format24bppRgb);Marshal.Copy(l.Scan0,buf,0,buf.Length);b.UnlockBits(l);return buf;}
 }
 static void Write(string p,byte[] buf){using(var b=new Bitmap(W,H,PixelFormat.Format24bppRgb)){var l=b.LockBits(new Rectangle(0,0,W,H),ImageLockMode.WriteOnly,PixelFormat.Format24bppRgb);Marshal.Copy(buf,0,l.Scan0,buf.Length);b.UnlockBits(l);b.Save(p,ImageFormat.Png);}}
 static string folder;
 static Dictionary<string,byte[]> imBank=new Dictionary<string,byte[]>(),masks=new Dictionary<string,byte[]>(),cleans=new Dictionary<string,byte[]>();
 static byte[] Img(string n){if(!imBank.ContainsKey(n))imBank[n]=Raw(Path.Combine(folder,"plates",n+".png"));return imBank[n];}
 static byte[] Mask(string s){if(!masks.ContainsKey(s))masks[s]=File.ReadAllBytes(Path.Combine(folder,"masks",s+".raw"));return masks[s];}
 static byte[] Clean(string n,bool r,bool l){
  string key=n+(r?"r":"")+(l?"l":"");if(cleans.ContainsKey(key))return cleans[key];var orig=Img(n);byte[] result=(byte[])orig.Clone();
  var mr=Mask(n+"R-clear");var ml=Mask(n+"L-clear");
  string order=("IAJ".Contains(n)?"SGUCKTFMLV":"IAJUGCKFTSMVL");var ds=new List<byte[]>();var rs=new List<byte[]>();var ls=new List<byte[]>();
  foreach(char ch in order){string p=ch.ToString();if(p==n)continue;ds.Add(Img(p));rs.Add(Mask(p+"R-clear"));ls.Add(Mask(p+"L-clear"));}
  for(int i=0;i<W*H;i++){int amount=Math.Max(r?mr[i]:0,l?ml[i]:0);if(amount==0)continue;
   for(int j=0;j<ds.Count;j++){if(rs[j][i]>12||ls[j][i]>12)continue;int of=i*3;for(int k=0;k<3;k++)result[of+k]=(byte)((ds[j][of+k]*amount+orig[of+k]*(255-amount)+127)/255);break;}
  }
  cleans[key]=result;return result;
 }
 static readonly double[] loWidth={28,24,17,21},hiWidth={25,17,23,13}; static double Tube(P v,P[] p){
  double m=1e5;double[] a=loWidth,b=hiWidth;
  for(int i=0;i<4;i++){var e=p[i+1]-p[i];double u=Math.Max(0,Math.Min(1,Dot(v-p[i],e)/e.sq));
   m=Math.Min(m,Math.Sqrt((v-(p[i]+e*u)).sq)/(a[i]+u*(b[i]-a[i])));}
  return m;
 }
 static void Warp(string path,byte[] src,string a,string b,double t,bool end){
  bool hasL=false, hasR=false;var pa=new List<P>();var pb=new List<P>();var mid=new List<P>();var chains=new List<P[]>();var curr=new List<P[]>();
  foreach(bool left in new bool[]{false,true}){
   var p=Bones(a,left);var q=Bones(b,left);double moved=0;for(int j=0;j<5;j++)moved=Math.Max(moved,(p[j]-q[j]).sq);
   if(moved<90)continue;if(left)hasL=true;else hasR=true;var m=Knots(p,q,t);chains.Add(p);chains.Add(q);chains.Add(m);curr.Add(m);pa.AddRange(Rails(p));pb.AddRange(Rails(q));mid.AddRange(Rails(m));}
  List<P> srcKnots=end?pb:pa;
  for(int yy=0;yy<=H+25;yy+=34)for(int xx=0;xx<=W+25;xx+=34){
   P v=new P(xx,yy);double d=9999;foreach(var z in chains)d=Math.Min(d,Dist(v,z));
   if(d<46)continue;mid.Add(v);srcKnots.Add(v);
  }
  int cols=W/k+1,rows=H/k+1;P[] grid=new P[cols*rows];
  Parallel.For(0,rows,j=>{for(int i=0;i<cols;i++){P v=new P(i*k,j*k);double dist=1e5;foreach(var z in chains)dist=Math.Min(dist,Dist(v,z));
    if(dist>88){grid[j*cols+i]=v;continue;}P outv=MLS(v,mid,srcKnots);double f=Math.Max(0,Math.Min(1,(88-dist)/29));f=f*f*(3-2*f);grid[j*cols+i]=Mix(v,outv,f);
  }});
  string sourceKey=end?b:a;var clean=Clean(sourceKey,hasR,hasL);var maskR=Mask(sourceKey+"R");var maskL=Mask(sourceKey+"L");byte[] dst=(byte[])clean.Clone();
  Parallel.For(0,H,y=>{double v=(y%k)/(double)k;for(int x=0;x<W;x++){int ix=(y/k)*cols+x/k;double u=(x%k)/(double)k;
   P where=new P(x,y);double cover=999;foreach(var line in curr)cover=Math.Min(cover,Tube(where,line));if(cover>=1.53)continue;double bound=Math.Min(1,(1.53-cover)/.22);P ps=Mix(Mix(grid[ix],grid[ix+1],u),Mix(grid[ix+cols],grid[ix+cols+1],u),v);
   double xx=Math.Max(0,Math.Min(W-1.001,ps.x)),yy=Math.Max(0,Math.Min(H-1.001,ps.y));int x0=(int)xx,y0=(int)yy,off=(y0*W+x0)*3,di=(y*W+x)*3;double fu=xx-x0,fv=yy-y0;
   int idx=y0*W+x0;double aa0=Math.Max(hasR?maskR[idx]:0,hasL?maskL[idx]:0),aa1=Math.Max(hasR?maskR[idx+1]:0,hasL?maskL[idx+1]:0),aa2=Math.Max(hasR?maskR[idx+W]:0,hasL?maskL[idx+W]:0),aa3=Math.Max(hasR?maskR[idx+W+1]:0,hasL?maskL[idx+W+1]:0);double alpha=((aa0*(1-fu)+aa1*fu)*(1-fv)+(aa2*(1-fu)+aa3*fu)*fv)*bound/255;if(alpha<=0)continue;for(int j=0;j<3;j++){double p0=src[off+j]+fu*(src[off+3+j]-src[off+j]);int of2=off+W*3;double p1=src[of2+j]+fu*(src[of2+3+j]-src[of2+j]);double vcol=p0+(p1-p0)*fv;dst[di+j]=(byte)Math.Round(dst[di+j]+alpha*(vcol-dst[di+j]));}
  }});
  Write(path,dst);
 }
 static void Main(string[] args){
  string work=args[0];folder=work;string[] pairs=args[1].Split(',');
  foreach(string pair in pairs){string a=pair.Substring(0,1),b=pair.Substring(1,1);
   var im0=Raw(Path.Combine(work,"plates",a+".png"));var im1=Raw(Path.Combine(work,"plates",b+".png"));
   string dir=Path.Combine(work,"aligned",pair);Directory.CreateDirectory(dir);
   for(int i=1;i<=7;i++){double t=i/8.0;Warp(Path.Combine(dir,"a"+i+".png"),im0,a,b,t,false);Warp(Path.Combine(dir,"b"+i+".png"),im1,a,b,t,true);}
  }
 }
}
