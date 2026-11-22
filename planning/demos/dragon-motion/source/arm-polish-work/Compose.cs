using System;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Globalization;
using System.Collections.Generic;
using System.Threading.Tasks;

class AvatarPreview {
  const int W=600,H=720,Fps=30;
  static byte[] clean, face, staged, frame;
  static ArmArt artOpen,artRight,artLeft;
  static double[] volume;
  static string work,ff;
  static float[] rootWeight,ribWeight,tiltX,tiltY;
  static int[] frames={111,120,144,279,192,639};
  static string[] sections={"idle","listening","thinking","talking","smile","continuous"};
  struct Pt {
    public double X,Y;
    public Pt(double x,double y){X=x;Y=y;}
    public static Pt operator +(Pt a,Pt b){return new Pt(a.X+b.X,a.Y+b.Y);}
    public static Pt operator -(Pt a,Pt b){return new Pt(a.X-b.X,a.Y-b.Y);}
    public static Pt operator *(Pt a,double m){return new Pt(a.X*m,a.Y*m);}
    public Pt Unit(){double d=Math.Sqrt(X*X+Y*Y);return d>1e-6?new Pt(X/d,Y/d):new Pt(0,1);}
  }
  static Pt Direction(double a){a*=Math.PI/180;return new Pt(Math.Sin(a),Math.Cos(a));}
  static Pt Normal(Pt d){return new Pt(d.Y,-d.X);}
  static double Clamp(double t){return Math.Max(0,Math.Min(1,t));}
  static double Smooth(double t){t=Clamp(t);return t*t*(3-2*t);}
  static double Lerp(double a,double b,double t){return a+(b-a)*t;}
  static double Bell(double t,double center,double width){double d=(t-center)/width;return Math.Exp(-d*d);}
  static double G(double x,double y,double cx,double cy,double rx,double ry){return Bell(x,cx,rx)*Bell(y,cy,ry);}
  static double Blink(double t,double start){return Smooth((t-start)/.076)*(1-Smooth((t-start-.104)/.115));}
  class Raster {
    public byte[] Pixels;
    public int Width, Height;
    public Raster(string path){
      using(var b=new Bitmap(path)){
        Width=b.Width;Height=b.Height;Pixels=new byte[Width*Height*4];
        var d=b.LockBits(new Rectangle(0,0,Width,Height),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
        for(int y=0;y<Height;y++)Marshal.Copy(new IntPtr(d.Scan0.ToInt64()+(long)y*d.Stride),Pixels,y*Width*4,Width*4);
        b.UnlockBits(d);
      }
    }
    public void Sample(double x,double y,double[] v){
      x=Math.Max(0,Math.Min(Width-1.001,x)); y=Math.Max(0,Math.Min(Height-1.001,y));
      int i=(int)x,j=(int)y,o=(j*Width+i)*4, b=o+Width*4;
      double u=x-i,w=y-j;
      for(int k=0;k<4;k++)v[k]=Lerp(Lerp(Pixels[o+k],Pixels[o+4+k],u),Lerp(Pixels[b+k],Pixels[b+4+k],u),w);
    }
  }
  class ArmArt {
    public Raster Image;public double[] Min,Max,Center;
    public ArmArt(Raster atlas,int col,bool open){
      Image=atlas;Min=new double[724];Max=new double[724];Center=new double[724];
      double wrist=col==0?371:col==1?1043:1673;
      for(int y=0;y<724;y++){
        int l=col*724, r=l+724, xmin=r,xmax=l;
        for(int i=l;i<r;i++)if(atlas.Pixels[(y*atlas.Width+i)*4+3]>=102){xmin=Math.Min(xmin,i);xmax=Math.Max(xmax,i);}
        if(xmin>xmax){xmin=(int)wrist;xmax=xmin+1;}
        Min[y]=xmin-2;Max[y]=xmax+2;double t=Smooth((y-485.0)/43);
        Center[y]=Lerp(.5*(xmin+xmax),wrist,t);
        if(y>527&&open)Center[y]=Lerp(wrist,.67*wrist+.33*(xmin+xmax)/2,Smooth((y-528)/110.0));
      }
    }
  }
  // Each row blends into a rounded elbow or wrist before the texture is sampled.
  class Limb {
    public Pt Root, Elbow, Wrist, E0,E1,W0,W1;
    public Pt Upper, Lower, Fingers;
    public double L1,L2, EL, Bend;
    public Pt Center;
    public Limb(Pt root,double upper,double lower,double hand,double length1,double length2){
      Root=root;L1=length1;L2=length2;Upper=Direction(upper);Lower=Direction(lower);Fingers=Direction(lower+hand);
      Elbow=Root+Upper*L1;Wrist=Elbow+Lower*L2;
      double dot=Upper.X*Lower.X+Upper.Y*Lower.Y;
      Bend=Math.Atan2(Upper.X*Lower.Y-Upper.Y*Lower.X,dot);
      double radius=19.5; EL=Math.Min(83,radius*Math.Tan(Math.Abs(Bend)*.5));
      E0=Elbow-Upper*EL;E1=Elbow+Lower*EL;
      if(Math.Abs(Bend)>1e-6){radius=EL/Math.Tan(Math.Abs(Bend)*.5);Center=E0+new Pt(-Upper.Y,Upper.X)*(Math.Sign(Bend)*radius);}W0=Wrist-Lower*6.4;W1=Wrist+Fingers*6.4;
    }
    static Pt Round(Pt a,Pt p,Pt b,double f,out Pt d){double k=1-f;d=((p-a)*k+(b-p)*f).Unit();return a*(k*k)+p*(2*k*f)+b*(f*f);}
    static Pt Rotate(Pt p,double a){double c=Math.Cos(a),s=Math.Sin(a);return new Pt(c*p.X-s*p.Y,s*p.X+c*p.Y);}
    public Pt Position(double row,out Pt d){
      double e0=300-EL*229/L1,e1=300+EL*220/L2;
      if(row<e0){d=Upper;return Root+Upper*((row-71)*L1/229);}
      if(row<e1){double a=Bend*(row-e0)/Math.Max(1e-7,e1-e0);d=Rotate(Upper,a);return Center+Rotate(E0-Center,a);}
      double w0=520-6.4*220/L2,w1=520+6.4/.375;
      if(row<w0){d=Lower;return Elbow+Lower*((row-300)*L2/220);}
      if(row<w1)return Round(W0,Wrist,W1,(row-w0)/(w1-w0),out d);
      d=Fingers;return Wrist+Fingers*((row-520)*.375);
    }
  }
  struct Vertex {
    public Pt P;public double U,V;
    public Vertex(Pt p,double u,double v){P=p;U=u;V=v;}
  }
  static double Part(double a,double b,double c,int i){return i==0?a:i==1?b:c;}
  static readonly double[] neckY={312,338,365,382,410,441,459,472};
  static readonly double[] edgeRight={337,356,368,385,390,386,373,354};
  static readonly double[] edgeLeft={266,253,239,225,219,225,240,261};
  static double NearEdge(double y,bool right){
    int i=0;while(i<neckY.Length-2&&y>=neckY[i+1])i++;
    double[] xx=right?edgeRight:edgeLeft;
    return Lerp(xx[i],xx[i+1],Clamp((y-neckY[i])/(neckY[i+1]-neckY[i])));
  }
  static void DrawTri(Vertex A,Vertex B,Vertex C,ArmArt first,ArmArt second,double open,bool right,byte[] actor){
    double d=(B.P.Y-C.P.Y)*(A.P.X-C.P.X)+(C.P.X-B.P.X)*(A.P.Y-C.P.Y);
    if(Math.Abs(d)<.000001)return;
    int x0=Math.Max(0,(int)Math.Floor(Math.Min(A.P.X,Math.Min(B.P.X,C.P.X))));
    int x1=Math.Min(W-1,(int)Math.Ceiling(Math.Max(A.P.X,Math.Max(B.P.X,C.P.X))));
    int y0=Math.Max(0,(int)Math.Floor(Math.Min(A.P.Y,Math.Min(B.P.Y,C.P.Y))));
    int y1=Math.Min(H-1,(int)Math.Ceiling(Math.Max(A.P.Y,Math.Max(B.P.Y,C.P.Y))));
    double[] c0=new double[4],c1=new double[4];
    for(int y=y0;y<=y1;y++)for(int x=x0;x<=x1;x++){
      double xx=x+.5, yy=y+.5;
      double a=((B.P.Y-C.P.Y)*(xx-C.P.X)+(C.P.X-B.P.X)*(yy-C.P.Y))/d;
      double b=((C.P.Y-A.P.Y)*(xx-C.P.X)+(A.P.X-C.P.X)*(yy-C.P.Y))/d,c=1-a-b;
      if(a<0||b<0||c<0)continue;
      double u=a*A.U+b*B.U+c*C.U, v=a*A.V+b*B.V+c*C.V;
      int r=Math.Max(0,Math.Min(722,(int)v));
      double w=v-r;
      double xA=Lerp(Lerp(first.Min[r],first.Max[r],u),Lerp(first.Min[r+1],first.Max[r+1],u),w);
      first.Image.Sample(xA,v,c0);
      double blend=open*Smooth((v-458)/61);
      if(blend>.0001){
        double xB=Lerp(Lerp(second.Min[r],second.Max[r],1-u),Lerp(second.Min[r+1],second.Max[r+1],1-u),w);
        second.Image.Sample(xB,v,c1);
        // Interpolate the hand in its own texture coordinates, then composite it once.
        for(int i=0;i<4;i++)c0[i]=Lerp(c0[i],c1[i],blend);
      }
      double alpha=c0[3]/255*Smooth((v-42)/75);
      int o=(y*W+x)*3;
      if(v<301&&y<480){
        double edge=NearEdge(y,right),inside=right?edge-x:x-edge;
        double layer=Smooth((inside+1)/6)*Smooth((y-328)/18)*(1-Smooth((y-462)/16))*(1-Smooth((v-202)/99));
        alpha*=1-layer;
        // Feather the textured arm into the painted shoulder cap.
        alpha*=Smooth((v-43)/53);
        double light=1-Smooth((v-90)/116);
        c0[0]+=5.2*light;c0[1]+=5.7*light;c0[2]+=3.2*light;
      }
      if(alpha<=0)continue;
      for(int k=0;k<3;k++)actor[o+k]=(byte)Math.Round(Math.Min(255,Lerp(actor[o+k],c0[k],alpha)));
    }
  }
  static void Arm(byte[] target,Limb rig,ArmArt primary,ArmArt openArt,double open,bool right){
    Vertex previousL=new Vertex(),previousR=new Vertex();bool started=false;
    for(int row=39;row<=723;row+=3){
      Pt d,n,p=rig.Position(row,out d);n=Normal(d);
      double f=open*Smooth((row-458)/61),scale=.405;
      double l=Lerp(primary.Min[row]-primary.Center[row],openArt.Center[row]-openArt.Max[row],f)*scale;
      double r=Lerp(primary.Max[row]-primary.Center[row],openArt.Center[row]-openArt.Min[row],f)*scale;
      var a=new Vertex(p+n*l,0,row);var b=new Vertex(p+n*r,1,row);
      if(started){
        DrawTri(previousL,previousR,b,primary,openArt,open,right,target);
        DrawTri(previousL,b,a,primary,openArt,open,right,target);
      }
      started=true;previousL=a;previousR=b;
    }
  }
  // Arm angles, upper and lower lengths, palm opening, head inclination.
  static readonly double[] Idle={18,23,-6,129,127,0, -16,-26,5,130,127,0};
  static readonly double[] Listen={17,-83,3,123,91,.03, -14,-24,3,130,127,2.0};
  static readonly double[] Think={9,-137,-31,112,124,.03, -15,-23,1,128,126,4.5};
  static readonly double[] Low={18,-8,-5,127,125,0, -16,-25,4,130,127,1};
  static readonly double[] OpenMid={18,73,10,126,102,.50, -14,-24,3,130,127,-1};
  static readonly double[] Talk={16,116,-12,126,104,1, -14,-24,3,130,127,-1.0};
  static readonly double[] Close={16,-116,-16,124,99,.08, -15,-8,0,129,119,1.0};
  static readonly double[] Smile={12,-130,-19,121,109,.05, -16,81,-9,123,107,2.9};
  static readonly double[] Laugh={14,-129,-19,116,112,.07, -19,80,-10,120,110,5.2};
  class KF {public double T;public double[] P;public KF(double t,double[] p){T=t;P=p;}}
  static readonly KF[] idleSeq={new KF(0,Idle)};
  static readonly KF[] listenSeq={new KF(0,Idle),new KF(.45,Idle),new KF(1.58,Listen),new KF(2.76,Listen),new KF(3.83,Idle)};
  static readonly KF[] thinkSeq={new KF(0,Listen),new KF(.35,Listen),new KF(1.58,Think),new KF(2.85,Think),new KF(4.48,Listen)};
  static readonly KF[] talkSeq={new KF(0,Think),new KF(.45,Close),new KF(1.23,Low),new KF(1.97,OpenMid),new KF(2.56,Talk),new KF(7.93,Talk),new KF(8.53,OpenMid),new KF(9.27,Low)};
  static readonly KF[] happySeq={new KF(0,Talk),new KF(.56,OpenMid),new KF(1.35,Low),new KF(2.20,Close),new KF(2.84,Smile),new KF(3.38,Laugh),new KF(3.93,Laugh),new KF(4.48,Smile),new KF(5.31,Close),new KF(6.20,Listen)};
  static readonly KF[] fullSeq={
    new KF(0,Idle),new KF(1.18,Idle),new KF(2.44,Listen),new KF(3.40,Listen),new KF(4.54,Think),new KF(4.78,Think),
    new KF(5.22,Close),new KF(6.07,Low),new KF(6.91,OpenMid),new KF(7.53,Talk),new KF(12.66,Talk),
    new KF(13.28,OpenMid),new KF(14.12,Low),new KF(15.00,Close),new KF(15.54,Smile),new KF(16.12,Laugh),
    new KF(16.65,Laugh),new KF(17.13,Smile),new KF(17.94,Close),new KF(18.73,Listen),new KF(19.97,Idle)
  };
  static double Slope(double a,double b){if(a*b<=0)return 0;return 2*a*b/(a+b);}
  static double[] Motion(KF[] keys,double t){
    if(t<=keys[0].T)return (double[])keys[0].P.Clone();
    if(t>=keys[keys.Length-1].T)return (double[])keys[keys.Length-1].P.Clone();
    int i=0;while(i+2<keys.Length&&t>=keys[i+1].T)i++;
    KF a=keys[i],b=keys[i+1];double d=b.T-a.T,f=(t-a.T)/d,f2=f*f,f3=f*f2;
    double[] result=new double[12];
    for(int j=0;j<result.Length;j++){
      double slope=(b.P[j]-a.P[j])/d;
      double m0=i==0?0:Slope((a.P[j]-keys[i-1].P[j])/(a.T-keys[i-1].T),slope);
      double m1=i+2>=keys.Length?0:Slope(slope,(keys[i+2].P[j]-b.P[j])/(keys[i+2].T-b.T));
      result[j]=(2*f3-3*f2+1)*a.P[j]+(f3-2*f2+f)*m0*d+(-2*f3+3*f2)*b.P[j]+(f3-f2)*m1*d;
    }
    return result;
  }
  static double Section(double t,double a,double b,double c,double d){
    return Smooth((t-a)/(b-a))*(1-Smooth((t-c)/(d-c)));
  }
  static double Loudness(double t){int i=(int)Math.Round(t*Fps);return t<0||i>=volume.Length?0:volume[i];}
  static void Audio(string path){
    using(var file=new BinaryReader(File.OpenRead(path))){
      file.BaseStream.Position=12;int rate=0;short[] data=null;
      while(file.BaseStream.Position+8<=file.BaseStream.Length){
        string name=new string(file.ReadChars(4));int count=file.ReadInt32();long next=file.BaseStream.Position+count+(count&1);
        if(name=="fmt "){int format=file.ReadInt16(),chan=file.ReadInt16();rate=file.ReadInt32();if(format!=1||chan!=1)throw new Exception("Expected mono PCM");}
        if(name=="data"){data=new short[count/2];for(int i=0;i<data.Length;i++)data[i]=file.ReadInt16();break;}
        file.BaseStream.Position=next;
      }
      if(data==null||rate==0)throw new Exception("Invalid speech WAV");
      volume=new double[(int)Math.Ceiling(data.Length*Fps/(double)rate)];double prior=0;
      for(int i=0;i<volume.Length;i++){
        int a=i*rate/Fps,b=Math.Min(data.Length,a+rate/32);double rms=0;
        for(int j=a;j<b;j++)rms+=(double)data[j]*data[j];
        double x=Clamp((Math.Sqrt(rms/Math.Max(1,b-a))/32768-.007)/.103);
        prior=Lerp(prior,x,x>prior?.8:.71);volume[i]=prior;
      }
    }
  }
  static void FaceTile(Raster atlas,int tile,int x,int y,double[] val){
    double width=atlas.Width/3.0,height=atlas.Height/2.0;
    double u=(x+.5-450*600.0/1145)/(290*600.0/1145);
    double v=(y+.5-390*720.0/1374)/(230*720.0/1374);
    atlas.Sample((tile%3+u)*width,(tile/3+v)*height,val);
  }
  static double Mask(double x,double y,double cx,double cy,double rx,double ry){
    double d=Math.Sqrt((x-cx)*(x-cx)/(rx*rx)+(y-cy)*(y-cy)/(ry*ry));return Smooth((1-d)/.24);
  }
  static void Expression(Raster atlas,double blink,double focus,double thought,double smile,double laugh,double talk){
    Buffer.BlockCopy(clean,0,face,0,clean.Length);
    var val=new double[4];var other=new double[4];
    for(int y=239;y<302;y++)for(int x=268;x<356;x++){
      double eyes=Math.Max(Mask(x,y,291.3,257,28,16),Mask(x,y,336.4,264,25,15));
      double lips=Mask(x,y,314,286.5,16.4,9.5);
      int o=(y*W+x)*3;
      if(eyes>.001){
        double[] weights={focus*(1-thought),thought,laugh,blink};
        int[] tiles={1,2,5,0};
        for(int i=0;i<tiles.Length;i++){
          double amt=eyes*weights[i];
          if(amt>.001){FaceTile(atlas,tiles[i],x,y,val);for(int k=0;k<3;k++)face[o+k]=(byte)Math.Round(Lerp(face[o+k],val[k],amt));}
        }
      }
      if(lips>.001){
        if(laugh>.001||smile>.001){
          FaceTile(atlas,5,x,y,val);
          double amt=lips*Math.Max(laugh,.48*smile);
          for(int k=0;k<3;k++)face[o+k]=(byte)Math.Round(Lerp(face[o+k],val[k],amt));
        }else if(talk>.001){
          FaceTile(atlas,3,x,y,val);FaceTile(atlas,4,x,y,other);
          double f=Smooth((talk-.24)/.76), amt=lips*Smooth(talk/.38);
          for(int k=0;k<3;k++)face[o+k]=(byte)Math.Round(Lerp(face[o+k],Lerp(val[k],other[k],f),amt));
        }
      }
    }
  }
  static void Init(Raster baseImage){
    clean=new byte[W*H*3];face=new byte[clean.Length];staged=new byte[clean.Length];frame=new byte[clean.Length];
    for(int i=0;i<W*H;i++)for(int j=0;j<3;j++)clean[3*i+j]=baseImage.Pixels[4*i+j];
    rootWeight=new float[W*H];ribWeight=new float[W*H];tiltX=new float[W*H];tiltY=new float[W*H];
    for(int y=0;y<H;y++)for(int x=0;x<W;x++){
      int i=y*W+x;double gh=G(x,y,307,232,134,141);
      rootWeight[i]=(float)G(x,y,302,348,139,82);
      ribWeight[i]=(float)G(x,y,304,408,109,78);
      tiltX[i]=(float)(gh*(y-327)/124.0);tiltY[i]=(float)(gh*(x-305)/124.0);
    }
  }
  static void Breathe(double t,double incline,double laugh,double apex,double speak){
    double b=Math.Sin(2*Math.PI*t/3.85-.2), l=apex<0?0:Math.Sin(apex*13)*Math.Exp(-2.10*apex)*laugh;
    double lift=2.3*b+3.8*l, expansion=3.3*b+4.9*l+1.03*speak;
    Parallel.For(0,H,y=>{
      int row=y*W;
      for(int x=0;x<W;x++){
        int i=row+x;
        double dx=incline*tiltX[i]-.009*b*(x-304)*ribWeight[i];
        double dy=lift*rootWeight[i]+expansion*ribWeight[i]-incline*tiltY[i];
        float sx=(float)Math.Max(0,Math.Min(W-1.001,x+dx)),sy=(float)Math.Max(0,Math.Min(H-1.001,y+dy));
        int xx=(int)sx,yy=(int)sy,f=(int)((sx-xx)*256),g=(int)((sy-yy)*256),ap=(yy*W+xx)*3,bp=ap+W*3,op=i*3;
        for(int k=0;k<3;k++){
          int top=staged[ap+k]*(256-f)+staged[ap+k+3]*f,bot=staged[bp+k]*(256-f)+staged[bp+k+3]*f;
          frame[op+k]=(byte)((top*(256-g)+bot*g+32768)>>16);
        }
      }
    });
  }
  static void DrawFrame(int section,double t,Raster atlas){
    KF[][] sequences={idleSeq,listenSeq,thinkSeq,talkSeq,happySeq,fullSeq};
    bool full=section==5;
    double[] pose=Motion(sequences[section],t);
    double v=full?t-7.20:section==3?t-2.10:-1;
    double blink=Blink(t,.75)+Blink(t,3.05)+Blink(t,7.95)+Blink(t,11.32)+Blink(t,19.98);
    double listen=full?Section(t,1.35,2.49,3.36,4.01):section==1?Section(t,.46,1.58,2.69,3.48):section==2?1-Section(t,0,1.17,3.27,4.69):0;
    double thought=full?Section(t,3.75,4.63,5.22,6.10):section==2?Section(t,.42,1.58,2.79,4.09):section==3?1-Smooth(t/.76):0;
    double happy=full?Section(t,15.05,15.55,17.30,18.05):section==4?Section(t,2.35,2.84,4.44,5.18):0;
    double laugh=full?Section(t,15.53,16.13,16.67,17.18):section==4?Section(t,2.80,3.42,3.93,4.51):0;
    double apex=full?t-16.04:t-3.30, voice=Loudness(v);
    double bounce=apex<0?0:Math.Sin(apex*12.2)*Math.Exp(-2.10*apex)*laugh;
    double speech=(v<0||v>6)?0:Section(v,0,.4,5.65,6.01);
    // Keep the gesture moving with the rhythm of the sample dialogue.
    double emphasis=speech*(4.9*Bell(v,.69,.24)-11.1*Bell(v,2.16,.43)+6.0*Bell(v,3.0,.32)-5.6*Bell(v,4.49,.5));
    double isIdle=full?(1-Smooth((t-1.13)/.9))+Smooth((t-18.71)/.9):section==0?1:section==1?1-listen:0;
    double drift=Math.Sin(t*1.94);
    Expression(atlas,Math.Min(1,blink)*(1-laugh),listen,thought,happy,.93*laugh,voice);
    Buffer.BlockCopy(face,0,staged,0,face.Length);
    var r=new Limb(new Pt(376.5,357),pose[0]+1.4*drift*isIdle,pose[1]+emphasis+2.4*bounce+1.7*drift*isIdle,pose[2]-.45*emphasis,pose[3],pose[4]);
    var l=new Limb(new Pt(232.5,357),pose[6]-1.2*drift*isIdle,pose[7]+2.8*bounce-1.5*drift*isIdle,pose[8],pose[9],pose[10]);
    Arm(staged,l,artLeft,artLeft,0,false);
    Arm(staged,r,artRight,artOpen,Clamp(pose[5]),true);
    double nod=2.8*Bell(t,full?2.94:2.1,.29)*listen;
    Breathe(t,pose[11]+1.1*drift+.55*speech+nod,laugh,apex,voice);
  }
  static void SaveFrame(string path){
    using(var b=new Bitmap(W,H,PixelFormat.Format24bppRgb)){
      var d=b.LockBits(new Rectangle(0,0,W,H),ImageLockMode.WriteOnly,PixelFormat.Format24bppRgb);
      Marshal.Copy(frame,0,d.Scan0,frame.Length);b.UnlockBits(d);b.Save(path,ImageFormat.Png);
    }
  }
  static void Render(int id,Raster atlas){
    string name=sections[id],file=Path.Combine(work,name+"-silent.mp4");
    var si=new ProcessStartInfo(ff,"-y -loglevel error -f rawvideo -pixel_format bgr24 -video_size 600x720 -framerate 30 -i pipe:0 -an -c:v libx264 -preset fast -crf 17 -pix_fmt yuv420p -movflags +faststart \""+file+"\""){UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true};
    using(var proc=Process.Start(si))
    using(var label=new Bitmap(74,31,PixelFormat.Format32bppArgb)){
      if(id<5){
        string[] zh={"待机","倾听","思考","说话","轻笑"};
        using(var g=Graphics.FromImage(label))
        using(var fg=new SolidBrush(Color.FromArgb(222,34,30,55)))
        using(var font=new Font("Microsoft YaHei UI",16f,GraphicsUnit.Pixel)){
          g.SmoothingMode=SmoothingMode.AntiAlias;
          g.TextRenderingHint=TextRenderingHint.AntiAliasGridFit;
          using(var route=new GraphicsPath()){
            route.AddArc(0,0,30,30,90,180);route.AddArc(43,0,30,30,270,180);route.CloseFigure();g.FillPath(fg,route);
          }
          var fmt=new StringFormat();fmt.Alignment=StringAlignment.Center;fmt.LineAlignment=StringAlignment.Center;
          g.DrawString(zh[id],font,Brushes.White,new RectangleF(0,0,74,31),fmt);fmt.Dispose();
        }
      }
      Color[] stamp=new Color[74*31];for(int y=0;y<31;y++)for(int x=0;x<74;x++)stamp[y*74+x]=label.GetPixel(x,y);
      for(int i=0;i<frames[id];i++){
        DrawFrame(id,i/(double)Fps,atlas);
        if(id<5)for(int y=0;y<31;y++)for(int x=0;x<74;x++){
          Color p=stamp[y*74+x];if(p.A==0)continue;
          int o=((y+660)*W+x+22)*3;int hi=p.A,lo=255-hi;
          frame[o]=(byte)((frame[o]*lo+p.B*hi)/255);frame[o+1]=(byte)((frame[o+1]*lo+p.G*hi)/255);frame[o+2]=(byte)((frame[o+2]*lo+p.R*hi)/255);
        }
        proc.StandardInput.BaseStream.Write(frame,0,frame.Length);
      }
      proc.StandardInput.Close();proc.WaitForExit();if(proc.ExitCode!=0)throw new Exception("Could not encode "+name);
    }
    Console.WriteLine(name+" "+frames[id]+" frames");
  }
  static void Main(string[] args){
    work=args[0];ff=args[1];
    Init(new Raster(Path.Combine(work,"base.png")));
    var sheet=new Raster(args[2]);artOpen=new ArmArt(sheet,0,true);artRight=new ArmArt(sheet,1,false);artLeft=new ArmArt(sheet,2,false);
    var atlas=new Raster(args[3]);Audio(args[4]);
    if(args.Length>5){
      if(args[5]=="bounds"){
        double max=0,min=600,maxY=0,minY=720, maxStep=0;int peakAt=0;
        var prev=new Pt();
        for(int f=0;f<639;f++){
          double t=f/(double)Fps;
          double[] pose=Motion(fullSeq,t);
          double v=t-7.2;
          double speech=(v<0||v>6)?0:Section(v,0,.4,5.65,6.01);
          double emphasis=speech*(4.9*Bell(v,.69,.24)-11.1*Bell(v,2.16,.43)+6*Bell(v,3.0,.32)-5.6*Bell(v,4.49,.5));
          double isIdle=(1-Smooth((t-1.13)/.9))+Smooth((t-18.71)/.9);
          double drift=Math.Sin(t*1.94);
          var r=new Limb(new Pt(376.5,357),pose[0]+1.4*drift*isIdle,pose[1]+emphasis+1.7*drift*isIdle,pose[2]-.45*emphasis,pose[3],pose[4]);
          var l=new Limb(new Pt(232.5,357),pose[6]-1.2*drift*isIdle,pose[7]-1.5*drift*isIdle,pose[8],pose[9],pose[10]);
          foreach(var limb in new Limb[]{r,l}){
            Pt d; for(int y=520;y<=708;y+=2){
              Pt p=limb.Position(y,out d);Pt n=Normal(d);var main=limb==r?artRight:artLeft;
              double fraction=limb==r?Clamp(pose[5])*Smooth((y-458)/61):0;
              double lo=Lerp(main.Min[y]-main.Center[y],artOpen.Center[y]-artOpen.Max[y],fraction)*.405;
              double hi=Lerp(main.Max[y]-main.Center[y],artOpen.Center[y]-artOpen.Min[y],fraction)*.405;
              foreach(var q in new Pt[]{p+n*lo,p+n*hi}){
                max=Math.Max(max,q.X);min=Math.Min(min,q.X);maxY=Math.Max(maxY,q.Y);minY=Math.Min(minY,q.Y);
              }
            }
          }
          Pt dd,tip=r.Position(697,out dd);if(f>0){Pt d=tip-prev;double step=Math.Sqrt(d.X*d.X+d.Y*d.Y);if(step>maxStep){maxStep=step;peakAt=f;}}prev=tip;
        }
        Console.WriteLine("Hand bounds over 639 frames x {0:F1}-{1:F1}, y {2:F1}-{3:F1}; peak right tip step {4:F1} px at {5:F3} sec",min,max,minY,maxY,maxStep,peakAt/30.0);
        if(max>=W-4||min<4||maxY>=H-4||minY<4)throw new Exception("Hands out of frame");
        return;
      }
      double[] stamps={.20,1.69,2.48,3.05,3.9,4.42,4.9,5.54,6.23,6.61,7.6,13.47,14.5,15.22,15.97,17.7,18.2,20.2};
      for(int i=0;i<stamps.Length;i++){DrawFrame(5,stamps[i],atlas);SaveFrame(Path.Combine(work,"check-"+i.ToString("00")+".png"));}
    }else for(int i=0;i<sections.Length;i++)Render(i,atlas);
  }
}
