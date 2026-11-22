using System;
using System.IO;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Globalization;
using System.Text;

class DragonPreview {
    static string assets, work, target;
    static int[] pcm;
    static int sampleRate;
    static string[] names={"blink","listen","mouth-open","blink-half","think","mouth-small","smile"};
    static Dictionary<string,Bitmap> patches=new Dictionary<string,Bitmap>();
    static Dictionary<string,Rectangle> boxes=new Dictionary<string,Rectangle>();
    static Bitmap body, scenery;
    static void Main(string[] args) {
        target=args[0]; work=args[1]; assets=Path.Combine(target,"assets");
        using(var a=new Bitmap(args[2]))
        using(var b=new Bitmap(args[3])) {
            body=a.Clone(new Rectangle(0,0,626,626),PixelFormat.Format32bppArgb);
            body.Save(Path.Combine(assets,"portrait.png"));
            var eyes=new Rectangle(264,225,143,84);
            var mouth=new Rectangle(309,303,46,34);
            var face=new Rectangle(265,229,142,109);
            Export(a,627,0,"blink",eyes);
            Export(a,0,628,"listen",eyes);
            Export(a,627,628,"mouth-open",mouth);
            Export(b,0,0,"blink-half",eyes);
            Export(b,627,0,"think",eyes);
            Export(b,0,628,"mouth-small",mouth);
            Export(b,627,628,"smile",face);
        }
        File.WriteAllText(Path.Combine(assets,"placement.json"),Manifest(),new UTF8Encoding(false));
        scenery=new Bitmap(args[4]);
        ReadWave(Path.Combine(work,"line.wav"));
        MakeMovie(args[5]);
    }
    static int Luma(Color c){return (3*c.R+6*c.G+c.B)/10;}
    static Point Align(Bitmap sheet,int x0,int y0){
        var anchors=new[]{new Rectangle(333,291,16,13),new Rectangle(295,314,13,14),new Rectangle(349,322,13,10),new Rectangle(256,286,14,13)};
        int best=Int32.MaxValue,dx=0,dy=0;
        for(int y=-6;y<=6;y++)for(int x=-6;x<=6;x++){
            int err=0;
            foreach(var r in anchors) for(int j=r.Top;j<r.Bottom;j+=2)for(int i=r.Left;i<r.Right;i+=2){
                int diff=Luma(body.GetPixel(i,j))-Luma(sheet.GetPixel(i+x0+x,j+y0+y));
                err+=Math.Min(diff*diff,900);
            }
            if(err<best){best=err;dx=x;dy=y;}
        }
        return new Point(dx,dy);
    }
    static void Export(Bitmap atlas,int x,int y,string name,Rectangle rect){
        Point shift=Align(atlas,x,y);
        Bitmap crop=atlas.Clone(new Rectangle(x+shift.X+rect.X,y+shift.Y+rect.Y,rect.Width,rect.Height),PixelFormat.Format32bppArgb);
        for(int j=0;j<crop.Height;j++)for(int i=0;i<crop.Width;i++){
            var c=crop.GetPixel(i,j);
            double edge=Math.Max(0,Math.Min(1,Math.Min(Math.Min(i,crop.Width-1-i),Math.Min(j,crop.Height-1-j))/5.0));
            crop.SetPixel(i,j,Color.FromArgb((int)(edge*c.A),c.R,c.G,c.B));
        }
        crop.Save(Path.Combine(assets,name+".png")); patches[name]=crop; boxes[name]=rect;
        Console.WriteLine("{0} source offset {1},{2}",name,shift.X,shift.Y);
    }
    static string Manifest(){
        var s=new StringBuilder("{\n  \"canvas\": [626,626],\n  \"base\": \"portrait.png\",\n  \"origin\": \"top-left\",\n  \"overlays\": [\n");
        for(int i=0;i<names.Length;i++){string n=names[i];var r=boxes[n]; s.AppendFormat("    {{\"file\":\"{0}.png\",\"x\":{1},\"y\":{2},\"width\":{3},\"height\":{4}}}{5}\n",n,r.X,r.Y,r.Width,r.Height,i+1==names.Length?"":",");}
        return s.Append("  ]\n}\n").ToString();
    }
    static void ReadWave(string file){
        using(var r=new BinaryReader(File.OpenRead(file))){
            r.BaseStream.Position=12;
            while(r.BaseStream.Position+8<=r.BaseStream.Length){
                string id=Encoding.ASCII.GetString(r.ReadBytes(4));int size=r.ReadInt32();long next=r.BaseStream.Position+size+(size&1);
                if(id=="fmt "){int format=r.ReadInt16(),channels=r.ReadInt16();sampleRate=r.ReadInt32();r.ReadInt32();r.ReadInt16();int bits=r.ReadInt16();if(format!=1||channels!=1||bits!=16)throw new Exception("Unexpected WAV format.");}
                if(id=="data"){pcm=new int[size/2];for(int i=0;i<pcm.Length;i++)pcm[i]=r.ReadInt16();break;}
                r.BaseStream.Position=next;
            }
        }
        if(pcm==null||sampleRate==0)throw new Exception("Missing PCM.");
    }
    static double Level(double time){
        int start=(int)(time*sampleRate),len=sampleRate/25;
        if(start<0||start>=pcm.Length)return 0;
        int end=Math.Min(start+len,pcm.Length);double sum=0;
        for(int i=start;i<end;i++)sum+=(double)pcm[i]*pcm[i];
        return Math.Sqrt(sum/(end-start))/32768;
    }
    static void Overlay(Graphics g,string n){ var r=boxes[n];g.DrawImageUnscaled(patches[n],r.X,r.Y);}
    static string Blink(double t,double onset){
        double d=t-onset;if(d<0||d>=.21)return null;
        return d<.055||d>.142?"blink-half":"blink";
    }
    static void MakeMovie(string ffmpeg){
        const int width=600,height=720,fps=30;
        const double speakStart=5.4;
        double replyLength=pcm.Length/(double)sampleRate;
        double end=speakStart+replyLength+1.75;
        string audio=Path.Combine(work,"line.wav"),movie=Path.Combine(target,"dragon-demo.mp4");
        var si=new ProcessStartInfo(ffmpeg,"-y -v error -f rawvideo -pixel_format bgr24 -video_size 600x720 -framerate 30 -i pipe:0 -an -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p \""+Path.Combine(work,"silent.mp4")+"\"");
        si.UseShellExecute=false;si.RedirectStandardInput=true;si.CreateNoWindow=true;
        int frames=(int)Math.Ceiling(end*fps);
        using(var proc=Process.Start(si))
        using(var bg=new Bitmap(width,height,PixelFormat.Format24bppRgb))
        using(var shot=new Bitmap(width,height,PixelFormat.Format24bppRgb))
        using(var sprite=new Bitmap(626,626,PixelFormat.Format32bppPArgb))
        using(var normal=new Font("Microsoft YaHei UI",24,FontStyle.Regular,GraphicsUnit.Pixel))
        using(var small=new Font("Microsoft YaHei UI",16,FontStyle.Regular,GraphicsUnit.Pixel))
        using(var ivory=new SolidBrush(Color.FromArgb(255,246,229)))
        using(var white=new SolidBrush(Color.White))
        using(var scrim=new LinearGradientBrush(new Rectangle(0,564,width,156),Color.FromArgb(0,22,16,37),Color.FromArgb(187,22,16,37),LinearGradientMode.Vertical)){
            using(var g=Graphics.FromImage(bg)){g.InterpolationMode=InterpolationMode.HighQualityBicubic;double scale=Math.Max(width/(double)scenery.Width,height/(double)scenery.Height);float sw=(float)(scenery.Width*scale),sh=(float)(scenery.Height*scale);g.DrawImage(scenery,(width-sw)/2,(height-sh)/2,sw,sh);}
            byte[] bytes=new byte[width*height*3]; double amp=0, previousMouthTime=-1; string lastMouth=null; int wideFrames=0,smallFrames=0;
            double[] blinks={1.03,3.01,6.95,9.64,end-.55};
            for(int frame=0;frame<frames;frame++){
                double t=frame/(double)fps, spoken=t-speakStart;
                bool talking=spoken>=0&&spoken<replyLength;
                string state=t<1.9?"待机":t<3.9?"倾听":t<speakStart?"思考":talking?"说话":t<end-.35?"微笑":"待机";
                var b= (string)null; foreach(double onset in blinks){string v=Blink(t,onset);if(v!=null)b=v;}
                using(var ink=Graphics.FromImage(sprite)){
                    ink.CompositingMode=CompositingMode.SourceCopy;ink.DrawImageUnscaled(body,0,0);ink.CompositingMode=CompositingMode.SourceOver;
                    if(state=="微笑")Overlay(ink,"smile");
                    if(b!=null)Overlay(ink,b);else if(state=="倾听")Overlay(ink,"listen");else if(state=="思考")Overlay(ink,"think");
                    if(talking){
                        double value=Level(spoken);amp=value>amp?value:0.4*amp+0.6*value;
                        string mouth=amp<.013?null:amp<.075?"mouth-small":"mouth-open";
                        if(mouth!=lastMouth&&(t-previousMouthTime>=.065||amp<.008)){lastMouth=mouth;previousMouthTime=t;}
                        if(lastMouth!=null){Overlay(ink,lastMouth);if(lastMouth=="mouth-open")wideFrames++;else smallFrames++;}
                    }
                }
                using(var g=Graphics.FromImage(shot)){
                    g.CompositingMode=CompositingMode.SourceCopy;g.DrawImageUnscaled(bg,0,0);g.CompositingMode=CompositingMode.SourceOver;
                    g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.PixelOffsetMode=PixelOffsetMode.Half;
                    float size=(float)(677.0+1.9*Math.Sin(t*Math.PI*2/4.3));g.DrawImage(sprite,(width-size)/2,height-size+1,size,size);
                    g.FillRectangle(scrim,0,564,width,156);g.TextRenderingHint=TextRenderingHint.AntiAliasGridFit;
                    if(talking){
                        g.DrawString(state,small,ivory,27,634);
                        g.DrawString(spoken<2.55?"你也听见风声了吗？":"陪我在这里，再待一会儿吧。",normal,white,26,662);
                    }else g.DrawString(state,normal,white,26,662);
                }
                if(frame==15||frame==34||frame==86||frame==138||frame==208)shot.Save(Path.Combine(work,"check-"+frame+".png"));
                var data=shot.LockBits(new Rectangle(0,0,width,height),ImageLockMode.ReadOnly,PixelFormat.Format24bppRgb);
                if(data.Stride!=width*3)throw new Exception("Unexpected stride.");Marshal.Copy(data.Scan0,bytes,0,bytes.Length);shot.UnlockBits(data);
                proc.StandardInput.BaseStream.Write(bytes,0,bytes.Length);
            }
            proc.StandardInput.Close();proc.WaitForExit();if(proc.ExitCode!=0)throw new Exception("Video encoding failed.");
            Console.WriteLine("Frames {0}, seconds {1:F2}; speaking frames small {2}, wide {3}",frames,frames/(double)fps,smallFrames,wideFrames);
        }
    }
}
