using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Threading.Tasks;

class Hands {
  struct Point {
    public double X, Y;
    public Point(double x,double y){X=x;Y=y;}
  }
  static double Clamp(double t){return Math.Max(0,Math.Min(1,t));}
  static double Smooth(double t){t=Clamp(t);return t*t*(3-2*t);}
  static double Mix(double a,double b,double t){return a+(b-a)*t;}
  static Point[] Shape(string encoded){
    string[] fields=encoded.Split(new[]{' '},StringSplitOptions.RemoveEmptyEntries);
    Point[] result=new Point[fields.Length/2];
    for(int i=0;i<result.Length;i++)result[i]=new Point(int.Parse(fields[2*i]),int.Parse(fields[2*i+1]));
    return result;
  }
  static double Coverage(double x,double y,Point[] p,double upscale) {
    int j=p.Length-1;
    bool inside=false;
    double nearest=double.MaxValue;
    for(int i=0;i<p.Length;j=i++){
      Point a=p[i], b=p[j];double dx=b.X-a.X,dy=b.Y-a.Y;
      if((a.Y>y)!=(b.Y>y)&&x<(b.X-a.X)*(y-a.Y)/(b.Y-a.Y)+a.X)inside=!inside;
      double u=Clamp(((x-a.X)*dx+(y-a.Y)*dy)/(dx*dx+dy*dy));
      double ex=x-a.X-u*dx,ey=y-a.Y-u*dy;
      nearest=Math.Min(nearest,ex*ex+ey*ey);
    }
    double distance=Math.Sqrt(nearest)/upscale;
    return Smooth(.48+(inside?distance:-distance)*1.13);
  }
  static Color Sample(Bitmap b,double x,double y){
    int ix=(int)x,iy=(int)y;
    double fx=x-ix,fy=y-iy;
    Color p=b.GetPixel(ix,iy),q=b.GetPixel(ix+1,iy),r=b.GetPixel(ix,iy+1),s=b.GetPixel(ix+1,iy+1);
    return Color.FromArgb(
      (int)Math.Round(Mix(Mix(p.R,q.R,fx),Mix(r.R,s.R,fx),fy)),
      (int)Math.Round(Mix(Mix(p.G,q.G,fx),Mix(r.G,s.G,fx),fy)),
      (int)Math.Round(Mix(Mix(p.B,q.B,fx),Mix(r.B,s.B,fx),fy)));
  }
  static void Reproject(Bitmap atlas,Bitmap source,int slot,double xAnchor,Point wrist,Point crop,double deg,double poseScale,double coordScale,Point[] shape,int wristY,int blendStart,int blendEnd,string outPath){
    double a=deg*Math.PI/180, dx=Math.Cos(a),dy=Math.Sin(a);
    using(var image=atlas.Clone(new Rectangle(slot*724,0,724,724),PixelFormat.Format32bppArgb)){
      for(int y=blendStart;y<724;y++){
        double t=Smooth((y-blendStart)/(double)(blendEnd-blendStart)), s=(y-wristY)*.375/poseScale;
        for(int x=Math.Max(0,(int)xAnchor-150);x<Math.Min(724,xAnchor+150);x++){
          double n=(x-xAnchor)*.405/poseScale;
          double sx=wrist.X+dx*s+dy*n,sy=wrist.Y+dy*s-dx*n;
          double coverage=Coverage((sx-crop.X)*coordScale,(sy-crop.Y)*coordScale,shape,coordScale);
          var baseColor=image.GetPixel(x,y);var refColor=coverage>0?Sample(source,sx,sy):Color.Transparent;
          double baseAlpha=baseColor.A*(1-t),refAlpha=255*coverage*t,alpha=baseAlpha+refAlpha;
          if(alpha<.5){image.SetPixel(x,y,Color.Transparent);continue;}
          image.SetPixel(x,y,Color.FromArgb((int)Math.Round(alpha),
            (int)Math.Round((baseColor.R*baseAlpha+refColor.R*refAlpha)/alpha),
            (int)Math.Round((baseColor.G*baseAlpha+refColor.G*refAlpha)/alpha),
            (int)Math.Round((baseColor.B*baseAlpha+refColor.B*refAlpha)/alpha)));
        }
      }
      image.Save(outPath,ImageFormat.Png);
    }
  }
  static void Main(string[] args){
    using(var atlas=new Bitmap(args[0]))
    using(var presenting=new Bitmap(args[1]))
    using(var laughing=new Bitmap(args[2])) {
      var open=Shape("0 249 44 219 87 192 116 168 149 155 224 143 295 123 330 104 354 91 367 91 380 101 381 122 363 150 343 163 311 175 269 191 255 211 263 227 299 243 337 254 389 263 419 240 448 228 462 228 475 240 479 247 502 236 528 232 545 241 541 255 531 263 572 263 605 269 619 282 615 293 586 299 552 305 511 320 482 335 459 350 404 370 357 381 312 393 282 400 247 395 205 386 158 381 113 374 81 366 58 379 30 404 0 427");
      Reproject(atlas,presenting,1,319,new Point(496,424),new Point(482,379),3,.84,6,open,520,499,539,Path.Combine(args[3],"left-palm-up.png"));
      var rest=Shape("227 223 272 223 303 210 343 195 390 180 423 172 463 170 484 177 510 199 535 208 557 213 578 228 605 260 621 300 629 326 620 343 598 354 573 355 580 368 591 379 580 391 544 400 507 403 471 399 422 401 378 392 333 388 293 378 261 368 234 354");
      Reproject(atlas,laughing,2,225,new Point(311,534),new Point(263,476),7,.86,5,rest,544,544,575,Path.Combine(args[3],"right-hand-on-waist.png"));
    }
  }
}
