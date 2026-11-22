using System;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Text;

class BodyMovie {
  const int W=600,H=720,K=10,FPS=30;
  static string work,output,ff;
  static Dictionary<string,byte[]> frames=new Dictionary<string,byte[]>();
  static Queue<string> fifo=new Queue<string>();
  static double[] levels;
  static int speechSamples,rate;
  static int[] pcm;
  static byte[] mix=new byte[W*H*3], result=new byte[W*H*3];
  static double[] rib,shoulder,head,hair,expand,tip,rotX,rotY;
  static float[] mx,my;
  static string[] sections={"idle","listening","thinking","talking","smile","continuous"};
  static int[] counts={108,114,114,237,144,534};
  static double Limit(double v){return Math.Max(0,Math.Min(1,v));}
  static double Ease(double v){v=Limit(v);return v*v*(3-2*v);}
  static double G(double x,double y,double cx,double cy,double rx,double ry){x=(x-cx)/rx;y=(y-cy)/ry;return Math.Exp(-x*x-y*y);}
  static double Bell(double t,double cx,double w){t=(t-cx)/w;return Math.Exp(-t*t);}
  static double Blink(double t){if(t<0||t>.245)return 0;if(t<.078)return Ease(t/.078);if(t<.124)return 1;return 1-Ease((t-.124)/.121);}
  static byte[] Raw(string path){
    byte[] data;if(frames.TryGetValue(path,out data))return data;
    data=new byte[W*H*3];
    using(var img=new Bitmap(path)){
      var bits=img.LockBits(new Rectangle(0,0,W,H),ImageLockMode.ReadOnly,PixelFormat.Format24bppRgb);
      if(bits.Stride!=W*3)throw new Exception("stride");Marshal.Copy(bits.Scan0,data,0,data.Length);img.UnlockBits(bits);
    }
    while(fifo.Count>=40)frames.Remove(fifo.Dequeue());frames[path]=data;fifo.Enqueue(path);return data;
  }
  static byte[] Lerp(byte[] a,byte[] b,double v,byte[] dst){
    int h=(int)(Limit(v)*256+.5);if(h<=0)return a;if(h>=256)return b;int l=256-h;
    Parallel.For(0,H,y=>{int off=y*W*3,end=off+W*3;for(int i=off;i<end;i++)dst[i]=(byte)((a[i]*l+b[i]*h+128)>>8);});return dst;
  }
  static byte[] tmp=new byte[W*H*3],tmp2=new byte[W*H*3];
  static byte[] Plate(char ch){return Raw(Path.Combine(work,"plates",ch+".png"));}
  static byte[] Pose(string pair,double f){
    if(pair.Length==1)return Plate(pair[0]); if(f<=.0001)return Plate(pair[0]);if(f>=.9999)return Plate(pair[1]);
    int n=(pair=="SO"||pair=="IB"||pair=="SP")?8:(pair=="MH"?64:32);
    double q=f*n;int i=(int)q;
    string dir=Path.Combine(work,"library",pair);
    byte[] a=Raw(Path.Combine(dir,(i+1).ToString("0000")+".png")),b=Raw(Path.Combine(dir,(i+2).ToString("0000")+".png"));
    byte[] v=Lerp(a,b,q-i,tmp);


    return v;
  }
  class Plan {public string pair="I", label="待机";public double f,listen,think,talk,laugh,blink,voice=-10,apex=-100,nod; }
  static double S(double t,double a,double b){return Ease((t-a)/(b-a));}
  static void Edge(Plan p,string edge,double t,double a,double b,bool reverse=false){p.pair=edge;p.f=reverse?1-S(t,a,b):S(t,a,b);}
  static Plan Sequence(string section,double t){
    var p=new Plan();bool continuous=section=="continuous";double st=section=="talking"?.9:6.75;
    if(section=="idle"){p.blink=Math.Max(Blink(t-.94),Blink(t-3.02));}
    else if(section=="listening"||section=="thinking"){
      bool listen=section=="listening";p.label=listen?"倾听":"思考";
      double level=S(t,.13,1.05)*(1-S(t,2.75,3.62));p.pair=listen?"IL":"IT";p.f=level;
      if(listen){p.listen=level;p.nod=4.5*Bell(t,1.75,.22)+2*Bell(t,2.29,.24);}
      else{p.think=level;p.nod=2.8*Bell(t,2.12,.5);}
    } else if(section=="talking"){
      p.label="说话";if(t<st)Edge(p,"IS",t,.10,st);else if(t<6.92){p.pair="S";p.voice=t-st;p.talk=1;}
      else Edge(p,"IS",t,6.92,7.70,true);
    } else if(section=="smile"){
      p.label="微笑"; if(t<1.05)Edge(p,"IM",t,.10,1.05);
      else if(t<1.36)p.pair="M";
      else if(t<1.93)Edge(p,"MH",t,1.36,1.93);
      else if(t<2.74)p.pair="H";
      else if(t<3.47)Edge(p,"MH",t,2.74,3.47,true);
      else if(t<3.74)p.pair="M";else Edge(p,"IM",t,3.74,4.60,true);
      p.laugh=S(t,1.32,1.93)*(1-S(t,3.00,3.52));p.apex=t-1.75;
    } else if(continuous){
      if(t<2.05){p.blink=Blink(t-1.02);}
      else if(t<2.92){Edge(p,"IL",t,2.05,2.92);p.listen=p.f;}
      else if(t<4.14){p.pair="L";p.listen=1;p.nod=4.2*Bell(t,3.30,.22)+1.4*Bell(t,3.77,.21);}
      else if(t<5.02){Edge(p,"LT",t,4.14,5.02);p.listen=1-p.f;p.think=p.f;}
      else if(t<6.00){p.pair="T";p.think=1;p.nod=2.1*Bell(t,5.52,.4);}
      else if(t<st){Edge(p,"TS",t,6.0,st);p.think=1-p.f;}
      else if(t<12.77){p.pair="S";p.voice=t-st;p.talk=1;}
      else if(t<13.52)Edge(p,"SM",t,12.77,13.52);
      else if(t<13.73)p.pair="M";
      else if(t<14.29)Edge(p,"MH",t,13.73,14.29);
      else if(t<15.08)p.pair="H";
      else if(t<15.82)Edge(p,"MH",t,15.08,15.82,true);
      else if(t<16.10)p.pair="M";
      else if(t<17.03)Edge(p,"IM",t,16.10,17.03,true);
      else p.blink=Blink(t-17.28);
      p.laugh=S(t,13.70,14.29)*(1-S(t,15.32,15.87));p.apex=t-14.11;
    }
    return p;
  }
  static void Audio(string path){
    using(var r=new BinaryReader(File.OpenRead(path))){
      r.BaseStream.Position=12;while(r.BaseStream.Position+8<=r.BaseStream.Length){
        string tag=Encoding.ASCII.GetString(r.ReadBytes(4));int sz=r.ReadInt32();long next=r.BaseStream.Position+sz+(sz&1);
        if(tag=="fmt "){if(r.ReadInt16()!=1||r.ReadInt16()!=1)throw new Exception("Audio format");rate=r.ReadInt32();}
        if(tag=="data"){pcm=new int[sz/2];for(int i=0;i<pcm.Length;i++)pcm[i]=r.ReadInt16();break;}r.BaseStream.Position=next;
      }
    }
    speechSamples=pcm.Length;levels=new double[(int)Math.Ceiling(speechSamples*FPS/(double)rate)+4];double prev=0;
    for(int f=0;f<levels.Length;f++){int i=f*rate/FPS,last=Math.Min(speechSamples,i+rate/32);double energy=0;
      for(int j=i;j<last;j++)energy+=(double)pcm[j]*pcm[j];double rms=Math.Sqrt(energy/Math.Max(1,last-i))/32768;
      double target=Limit((rms-.009)/.110);prev=target>prev?.86*target+.14*prev:.68*target+.32*prev;levels[f]=prev;}
  }
  static void InitGrid(){
    int n=(W/K+1)*(H/K+1);rib=new double[n];shoulder=new double[n];head=new double[n];hair=new double[n];expand=new double[n];tip=new double[n];rotX=new double[n];rotY=new double[n];mx=new float[n];my=new float[n];
    for(int y=0;y<=H;y+=K)for(int x=0;x<=W;x+=K){
      int i=y/K*(W/K+1)+x/K;double edge=Ease(x/75.0)*Ease((W-x)/75.0)*Ease((H-y)/48.0)*Ease(y/47.0);
      rib[i]=G(x,y,309,522,128,78)*edge;shoulder[i]=G(x,y,296,447,171,72)*edge;
      head[i]=G(x,y,306,275,143,127)*edge;hair[i]=G(x,y,220,366,153,148)*edge;
      expand[i]=((x-304)/106.0)*rib[i];tip[i]=G(x,y,333,170,150,106)*edge;
      rotX[i]=(y-406)*head[i]/180.0;rotY[i]=(x-304)*head[i]/150.0;
    }
  }
  static void Deform(byte[] input,double t,Plan p){
    double cycle=Math.Sin(2*Math.PI*t/3.54-.46), drift=Math.Sin(2*Math.PI*t/6.2+.5);
    double rebound=p.apex<0?0:Math.Exp(-p.apex*2.45)*Math.Sin(2*Math.PI*2.25*p.apex);
    double tongue=p.voice<0?0:1.9*Bell(p.voice,.96,.34)+2.1*Bell(p.voice,2.86,.38)+1.45*Bell(p.voice,4.37,.36);
    double chest=4.6*cycle+5.8*rebound*p.laugh+1.15*tongue,
           shoulders=2.15*cycle+5.2*rebound*p.laugh+1.1*tongue,
           nod=p.nod-4.8*rebound*p.laugh-.83*tongue+.60*cycle,
           turn=1.5*p.listen+2.3*p.think+1.55*p.laugh*rebound;
    for(int i=0;i<mx.Length;i++){
      mx[i]=(float)(-2.2*cycle*expand[i]+turn*rotX[i]+.70*drift*hair[i]+.35*drift*tip[i]);
      my[i]=(float)(chest*rib[i]+shoulders*shoulder[i]-nod*head[i]-turn*rotY[i]+.50*cycle*tip[i]);
    }
    const int cols=W/K+1;
    Parallel.For(0,H,y=>{
      int row=(y/K)*cols;float v=(y%K)/(float)K;
      for(int block=0;block<W/K;block++){
        int k=row+block;float dx=mx[k]+v*(mx[k+cols]-mx[k]),dy=my[k]+v*(my[k+cols]-my[k]);
        float ex=mx[k+1]+v*(mx[k+cols+1]-mx[k+1]),ey=my[k+1]+v*(my[k+cols+1]-my[k+1]);
        float ix=(ex-dx)/K,iy=(ey-dy)/K;
        for(int x=block*K;x<(block+1)*K;x++,dx+=ix,dy+=iy){
          float sx=Math.Max(0,Math.Min(W-1.002f,x+dx)),sy=Math.Max(0,Math.Min(H-1.002f,y+dy));int x0=(int)sx,y0=(int)sy;
          int fx=(int)((sx-x0)*256),fy=(int)((sy-y0)*256),ox=256-fx,oy=256-fy;
          int src=(y0*W+x0)*3,dst=(y*W+x)*3,bot=src+W*3;
          for(int c=0;c<3;c++){int topv=input[src+c]*ox+input[src+3+c]*fx,botv=input[bot+c]*ox+input[bot+3+c]*fx;
            result[dst+c]=(byte)((topv*oy+botv*fy+32768)>>16);}
        }
      }
    });
  }
  static byte[] Look(Plan p){
    if(p.voice>=0){
      int f=Math.Min(levels.Length-1,(int)Math.Round(p.voice*FPS));double m=levels[Math.Max(0,f)];
      byte[] face=Pose("SO",m);Buffer.BlockCopy(face,0,mix,0,mix.Length);
      double blink=Math.Max(Blink(p.voice-1.93),Blink(p.voice-4.95));
      if(blink>0){var eyes=Pose("SP",blink);for(int y=266;y<334;y++)Buffer.BlockCopy(eyes,(y*W+237)*3,mix,(y*W+237)*3,157*3);}
      return mix;
    }
    if(p.blink>0)return Pose("IB",p.blink);return Pose(p.pair,p.f);
  }
  static void Render(string name,int frameCount){
    string file=Path.Combine(work,name+"-silent.mp4");
    var si=new ProcessStartInfo(ff,"-y -loglevel error -f rawvideo -pixel_format bgr24 -video_size 600x720 -framerate 30 -i pipe:0 -an -c:v libx264 -preset fast -crf 17 -pix_fmt yuv420p -movflags +faststart \""+file+"\""){UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true};
    using(var proc=Process.Start(si))
    using(var label=new Bitmap(88,36,PixelFormat.Format32bppArgb)){
      if(name!="continuous"){
        using(var g=Graphics.FromImage(label))using(var bg=new SolidBrush(Color.FromArgb(210,48,38,58)))using(var font=new Font("Microsoft YaHei UI",17f,GraphicsUnit.Pixel)){
          g.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;g.TextRenderingHint=TextRenderingHint.AntiAliasGridFit;
          using(var path=new System.Drawing.Drawing2D.GraphicsPath()){path.AddArc(0,0,26,26,180,90);path.AddArc(40,0,26,26,270,90);path.AddArc(40,7,26,26,0,90);path.AddArc(0,7,26,26,90,90);path.CloseFigure();g.FillPath(bg,path);}
          g.DrawString(Sequence(name,1.4).label,font,Brushes.White,new PointF(13,4));
        }
      }
      Color[] stamp=new Color[88*36];for(int j=0;j<36;j++)for(int i=0;i<88;i++)stamp[j*88+i]=label.GetPixel(i,j);
      for(int n=0;n<frameCount;n++){
        double t=n/(double)FPS;var p=Sequence(name,t);Deform(Look(p),t,p);
        if(name!="continuous")for(int j=0;j<36;j++)for(int i=0;i<88;i++){Color c=stamp[j*88+i];if(c.A==0)continue;int off=((j+665)*W+i+24)*3,inv=255-c.A;result[off]=(byte)((result[off]*inv+c.B*c.A)/255);result[off+1]=(byte)((result[off+1]*inv+c.G*c.A)/255);result[off+2]=(byte)((result[off+2]*inv+c.R*c.A)/255);}
        proc.StandardInput.BaseStream.Write(result,0,result.Length);
      }
      proc.StandardInput.Close();proc.WaitForExit();if(proc.ExitCode!=0)throw new Exception("Encoding failed "+name);
    }
    Console.WriteLine(name+" "+frameCount+" frames");
  }
  static void Main(string[] args){
    work=args[0];output=args[1];ff=args[2];Audio(args[3]);InitGrid();
    for(int i=0;i<sections.Length;i++)Render(sections[i],counts[i]);
  }
}
