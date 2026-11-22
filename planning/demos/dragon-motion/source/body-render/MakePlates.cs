using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
class Plates {
    static Bitmap Tile(Bitmap b,int col,int row) {
        Bitmap p=new Bitmap(626,626,PixelFormat.Format32bppArgb);
        int sy=row==0?0:632, h=row==0?626:622;
        using(var g=Graphics.FromImage(p)) {
            g.CompositingMode=CompositingMode.SourceCopy;g.InterpolationMode=InterpolationMode.HighQualityBicubic;
            using(var attr=new ImageAttributes()){attr.SetWrapMode(WrapMode.TileFlipXY);
            g.DrawImage(b,new Rectangle(0,0,626,626),col*627,sy,626,h,GraphicsUnit.Pixel,attr);}
        }return p;
    }
    static void Patch(Bitmap dst,Bitmap src,Rectangle a,Point p){
        using(var c=src.Clone(a,PixelFormat.Format32bppArgb)){
            for(int y=0;y<c.Height;y++)for(int x=0;x<c.Width;x++){
                var cl=c.GetPixel(x,y);double alpha=Math.Min(1,Math.Min(Math.Min(x,c.Width-1-x),Math.Min(y,c.Height-1-y))/4.0);
                c.SetPixel(x,y,Color.FromArgb((int)(alpha*cl.A),cl.R,cl.G,cl.B));
            }using(var g=Graphics.FromImage(dst))g.DrawImageUnscaled(c,p);
        }
    }
    static void Main(string[] args){
        string plates=args[0];using(var a=new Bitmap(args[1]))using(var b=new Bitmap(args[2]))using(var bg=new Bitmap(args[3])){
            var idle=Tile(a,0,0);var listen=Tile(a,1,0);var think=Tile(a,0,1);var speak=Tile(a,1,1);
            var shut=Tile(b,0,0);var lips=Tile(b,1,0);var ready=Tile(b,0,1);var laugh=Tile(b,1,1);
            var blink=(Bitmap)idle.Clone();Patch(blink,shut,new Rectangle(261,218,135,57),new Point(264,220));
            var rest=(Bitmap)speak.Clone();Patch(rest,lips,new Rectangle(302,272,45,29),new Point(309,256));
            var talkBlink=(Bitmap)rest.Clone();Patch(talkBlink,shut,new Rectangle(261,218,135,57),new Point(268,201)); string[] labels={"I","L","T","O","B","S","M","H","P"}; Bitmap[] cuts={idle,listen,think,speak,blink,rest,ready,laugh,talkBlink};
            for(int i=0;i<labels.Length;i++){
                using(var frame=new Bitmap(600,720,PixelFormat.Format24bppRgb))
                using(var g=Graphics.FromImage(frame)){
                    g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.PixelOffsetMode=PixelOffsetMode.Half;
                    g.DrawImage(bg,new Rectangle(0,0,600,720),new Rectangle(0,27,bg.Width,bg.Height-54),GraphicsUnit.Pixel);
                    g.DrawImage(cuts[i],new Rectangle(-30,61,660,660));frame.Save(Path.Combine(plates,labels[i]+".png"),ImageFormat.Png);
                }
            }
        }
    }
}
