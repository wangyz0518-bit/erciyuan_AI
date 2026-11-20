param([Parameter(Mandatory=$true)][string]$CoreDll)
$ErrorActionPreference = 'Stop'
$resolvedCore = (Resolve-Path -LiteralPath $CoreDll).Path
$nativeCode = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
public static class DragonCoreCheck {
 const string Dll = @"__DLL__";
 [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] static extern int csmHasMocConsistency(IntPtr p,uint n);
 [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] static extern IntPtr csmReviveMocInPlace(IntPtr p,uint n);
 [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] static extern uint csmGetSizeofModel(IntPtr p);
 [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] static extern IntPtr csmInitializeModelInPlace(IntPtr p,IntPtr a,uint n);
 [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] static extern void csmUpdateModel(IntPtr p);
 [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] static extern int csmGetParameterCount(IntPtr p);
 [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] static extern IntPtr csmGetParameterIds(IntPtr p);
 [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] static extern IntPtr csmGetParameterValues(IntPtr p);
 [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] static extern int csmGetDrawableCount(IntPtr p);
 [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] static extern IntPtr csmGetDrawableIds(IntPtr p);
 [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] static extern IntPtr csmGetDrawableDrawOrders(IntPtr p);
 [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] static extern IntPtr csmGetDrawableVertexCounts(IntPtr p);
 [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] static extern IntPtr csmGetDrawableVertexPositions(IntPtr p);
 public class Result { public string Id; public int DrawOrder; public int Vertices; public double MaxCoordinateDelta; }
 static IntPtr Align(IntPtr p,int a) { return new IntPtr((p.ToInt64()+a-1)&~(long)(a-1)); }
 static float[][] Vertices(IntPtr m,int count) {
   var result=new float[count][];
   var ns=csmGetDrawableVertexCounts(m); var vs=csmGetDrawableVertexPositions(m);
   for(int i=0;i<count;i++) {
     result[i]=new float[2*Marshal.ReadInt32(ns,i*4)];
     Marshal.Copy(Marshal.ReadIntPtr(vs,i*IntPtr.Size),result[i],0,result[i].Length);
   }
   return result;
 }
 public static Result[] Run(string file) {
   var bytes=File.ReadAllBytes(file);
   var raw=Marshal.AllocHGlobal(bytes.Length+63); IntPtr modelRaw=IntPtr.Zero;
   try {
     var memory=Align(raw,64); Marshal.Copy(bytes,0,memory,bytes.Length);
     if(csmHasMocConsistency(memory,(uint)bytes.Length)!=1) throw new Exception("MOC consistency failed");
     var moc=csmReviveMocInPlace(memory,(uint)bytes.Length);
     if(moc==IntPtr.Zero) throw new Exception("MOC revive failed");
     uint size=csmGetSizeofModel(moc); modelRaw=Marshal.AllocHGlobal(checked((int)size+15));
     var model=csmInitializeModelInPlace(moc,Align(modelRaw,16),size);
     if(model==IntPtr.Zero) throw new Exception("Model initialization failed");
     int parameter=-1, count=csmGetParameterCount(model);
     var ids=csmGetParameterIds(model);
     for(int i=0;i<count;i++) if(Marshal.PtrToStringAnsi(Marshal.ReadIntPtr(ids,i*IntPtr.Size))=="ParamAppendageSway")parameter=i;
     if(parameter<0) throw new Exception("Sway parameter missing");
     var values=csmGetParameterValues(model); int n=csmGetDrawableCount(model);
     if(n!=4) throw new Exception("Expected four drawables");
     Marshal.Copy(new float[]{-30},0,IntPtr.Add(values,parameter*4),1); csmUpdateModel(model);
     var negative=Vertices(model,n);
     Marshal.Copy(new float[]{30},0,IntPtr.Add(values,parameter*4),1); csmUpdateModel(model);
     var positive=Vertices(model,n);
     var results=new Result[n]; var dids=csmGetDrawableIds(model); var orders=csmGetDrawableDrawOrders(model);
     int moving=0,stationary=0;
     for(int i=0;i<n;i++) {
       double delta=0;
       for(int j=0;j<negative[i].Length;j++) delta=Math.Max(delta,Math.Abs(positive[i][j]-negative[i][j]));
       results[i]=new Result{Id=Marshal.PtrToStringAnsi(Marshal.ReadIntPtr(dids,i*IntPtr.Size)),
         DrawOrder=Marshal.ReadInt32(orders,i*4),Vertices=negative[i].Length/2,MaxCoordinateDelta=delta};
       if(delta>0.000001) moving++; else stationary++;
       if(results[i].DrawOrder==600 && delta>0.000001) throw new Exception("Body unexpectedly moves");
     }
     if(moving!=3 || stationary!=1) throw new Exception("Expected three moving appendages and stationary body");
     return results;
   } finally { if(modelRaw!=IntPtr.Zero) Marshal.FreeHGlobal(modelRaw); Marshal.FreeHGlobal(raw); }
 }
}
'@
Add-Type -TypeDefinition $nativeCode.Replace('__DLL__',$resolvedCore.Replace('"','""'))
$modelFile = Join-Path $PSScriptRoot 'runtime/dragon-four-layers.moc3'
$result = [DragonCoreCheck]::Run($modelFile)
$report = [ordered]@{mocConsistency='pass'; modelInitialization='pass'; movingDrawables=3; stationaryDrawables=1; drawables=$result}
$report | ConvertTo-Json -Depth 5
