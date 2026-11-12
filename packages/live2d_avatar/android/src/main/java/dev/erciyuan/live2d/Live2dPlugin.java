package dev.erciyuan.live2d;

import android.content.res.AssetManager;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.SystemClock;
import android.view.Surface;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.InputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/** One visible Cubism instance; every native operation is serialized on one thread. */
public final class Live2dPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  static { System.loadLibrary("live2d_avatar"); }
  private static final AtomicBoolean owner = new AtomicBoolean();
  private final Handler main = new Handler(android.os.Looper.getMainLooper());
  private HandlerThread thread;
  private Handler render;
  private FlutterPluginBinding binding;
  private MethodChannel channel;
  private TextureRegistry.SurfaceProducer producer;
  private long handle, frames, started, lastLoadMs;
  private boolean active = true, disposed = true;
  private String path;
  private String frameError;
  private float mouth, zoom=1, offsetX, offsetY;
  private int loads, unloads, surfaceRebuilds;
  private Map<String,Object> capabilities = new HashMap<>();
  private static native long nativeCreate(AssetManager assets, Surface surface);
  private static native void nativeLoad(long handle, String path);
  private static native void nativeCommand(long handle, String action, String value, float number);
  private static native void nativeFrame(long handle);
  private static native void nativeDestroy(long handle);

  @Override public void onAttachedToEngine(FlutterPluginBinding b) {
    binding=b; channel=new MethodChannel(b.getBinaryMessenger(),"erciyuan/live2d");channel.setMethodCallHandler(this);
  }
  private final Runnable tick = new Runnable() {
    @Override public void run() {
      if(disposed || !active || handle==0) return;
      try {nativeFrame(handle);frames++;render.postDelayed(this,16);}
      catch(Exception e) {frameError=e.getMessage();active=false;}
    }
  };
  private void attachSurface(Surface surface) {
    if(disposed)return;
    destroyNative();
    handle=nativeCreate(binding.getApplicationContext().getAssets(),surface);
    surfaceRebuilds++;
    if(path!=null)nativeLoad(handle,path);
    nativeCommand(handle,"mouth","",mouth);nativeCommand(handle,"zoom","",zoom);
    nativeCommand(handle,"x","",offsetX);nativeCommand(handle,"y","",offsetY);
    frameError=null;render.removeCallbacks(tick);if(active)render.post(tick);
  }
  private void destroyNative() {
    render.removeCallbacks(tick);
    if(handle!=0){nativeDestroy(handle);handle=0;}
  }
  private void close(Runnable done) {
    if(producer==null){done.run();return;}
    final var oldProducer=producer;producer=null;
    final var oldThread=thread;
    render.post(()->{
      disposed=true;path=null;destroyNative();
      main.post(()->{oldProducer.release();oldThread.quitSafely();owner.set(false);done.run();});
    });
  }
  @Override public void onDetachedFromEngine(FlutterPluginBinding b) {
    channel.setMethodCallHandler(null);close(()->{});
  }
  @Override public void onMethodCall(MethodCall call, MethodChannel.Result result) {
    if(call.method.equals("create")) {
      if(producer!=null || !owner.compareAndSet(false,true)){result.error("busy","Only one Live2D view is supported",null);return;}
      thread=new HandlerThread("Live2D-render");thread.start();render=new Handler(thread.getLooper());
      producer=binding.getTextureRegistry().createSurfaceProducer();producer.setSize(720,1280);
      final var output=producer;
      output.setCallback(new TextureRegistry.SurfaceProducer.Callback(){
        @Override public void onSurfaceAvailable(){
          if(producer!=output)return;
          Surface surface=output.getSurface();render.post(()->{try{attachSurface(surface);}catch(Exception e){frameError=e.getMessage();}});
        }
        @Override public void onSurfaceCleanup(){
          if(producer!=output)return;
          // Finish GPU work before Flutter destroys the borrowed surface.
          CountDownLatch finished=new CountDownLatch(1);
          render.post(()->{try{destroyNative();}finally{finished.countDown();}});
          try { if(!finished.await(5,TimeUnit.SECONDS)) android.util.Log.e("Live2D","Surface cleanup timed out"); }
          catch(InterruptedException e){Thread.currentThread().interrupt();}
        }
      });
      Surface surface=output.getSurface();
      render.post(()->{
        try {disposed=false;active=true;frames=0;started=SystemClock.elapsedRealtime();attachSurface(surface);
          main.post(()->result.success(output.id()));
        }catch(Exception e){main.post(()->close(()->result.error("create_failed",e.getMessage(),null)));}
      });return;
    }
    if(call.method.equals("dispose")){close(()->result.success(null));return;}
    if(producer==null){result.error("not_created","Create the view first",null);return;}
    render.post(()->{
      try {
        Object response=null;
        if(disposed)throw new IllegalStateException("View disposed");
        switch(call.method){
          case "load": {
            String key=binding.getFlutterAssets().getAssetFilePathByName(call.argument("asset"));
            Map<String,Object> info=validate(key);
            if(handle==0)throw new IllegalStateException("Surface unavailable");
            long t=SystemClock.elapsedRealtime();
            nativeLoad(handle,key);
            path=key;capabilities=info;lastLoadMs=SystemClock.elapsedRealtime()-t;loads++;frameError=null;
            response=info;break;
          }
          case "unload":
            path=null;capabilities.clear();mouth=0;unloads++;
            if(handle!=0)nativeCommand(handle,"unload","",0);break;
          case "active":
            active=Boolean.TRUE.equals(call.argument("value"));mouth=0;
            if(handle!=0)nativeCommand(handle,"mouth","",0);
            render.removeCallbacks(tick);if(active && handle!=0)render.post(tick);break;
          case "command": {
            String action=call.argument("action");String value=call.argument("value");Number number=call.argument("number");
            float n=number==null?0:number.floatValue();
            if(!Float.isFinite(n))throw new IllegalArgumentException("Parameter must be finite");
            if(action.equals("mouth"))mouth=Math.max(0,Math.min(1,n));
            if(action.equals("zoom"))zoom=Math.max(.4f,Math.min(3,n));
            if(action.equals("x"))offsetX=Math.max(-2,Math.min(2,n));
            if(action.equals("y"))offsetY=Math.max(-2,Math.min(2,n));
            if(handle==0)throw new IllegalStateException("Surface unavailable");
            nativeCommand(handle,action,value==null?"":value,n);break;
          }
          case "stats": {
            Map<String,Object> s=new HashMap<>();s.put("frames",frames);s.put("elapsedMs",SystemClock.elapsedRealtime()-started);
            s.put("loadMs",lastLoadMs);s.put("loads",loads);s.put("unloads",unloads);s.put("surfaceRebuilds",surfaceRebuilds);
            s.put("nativeInstances",handle==0?0:1);s.put("models",path==null?0:1);s.put("active",active);
            s.put("mouth",mouth);s.put("error",frameError);s.put("capabilities",capabilities);response=s;break;
          }
          default: main.post(result::notImplemented);return;
        }
        final Object answer=response;main.post(()->result.success(answer));
      }catch(Exception e){main.post(()->result.error("live2d_error",e.getMessage(),null));}
    });
  }
  private void checkFile(String dir,String file) throws Exception {
    if(file.isEmpty()||file.startsWith("/")||file.contains("..")||file.contains(":"))throw new IllegalArgumentException("Invalid asset reference");
    try(InputStream in=binding.getApplicationContext().getAssets().open(dir+file)) {
      if(in.read()<0)throw new IllegalArgumentException("Empty asset: "+file);
    }
  }
  private Map<String,Object> validate(String key) throws Exception {
    JSONObject json;
    try(InputStream in=binding.getApplicationContext().getAssets().open(key)) {
      ByteArrayOutputStream bytes=new ByteArrayOutputStream();byte[] buffer=new byte[4096];int n;
      while((n=in.read(buffer))!=-1){bytes.write(buffer,0,n);if(bytes.size()>1024*1024)throw new IllegalArgumentException("Model descriptor too large");}
      json=new JSONObject(bytes.toString(StandardCharsets.UTF_8.name()));
    }
    if(json.getInt("Version")!=3)throw new IllegalArgumentException("Only model3.json Version 3 is supported");
    JSONObject refs=json.getJSONObject("FileReferences");String dir=key.substring(0,key.lastIndexOf('/')+1);
    checkFile(dir,refs.getString("Moc"));JSONArray tex=refs.getJSONArray("Textures");
    if(tex.length()<1 || tex.length()>8)throw new IllegalArgumentException("Unsupported texture count");
    for(int i=0;i<tex.length();i++)checkFile(dir,tex.getString(i));
    for(String f:new String[]{"Physics","Pose"})if(refs.has(f))checkFile(dir,refs.getString(f));
    ArrayList<String> expressions=new ArrayList<>(), motions=new ArrayList<>();
    JSONArray ex=refs.optJSONArray("Expressions");
    if(ex!=null)for(int i=0;i<ex.length();i++){JSONObject x=ex.getJSONObject(i);checkFile(dir,x.getString("File"));expressions.add(x.getString("Name"));}
    JSONObject groups=refs.optJSONObject("Motions");
    if(groups!=null)for(var keys=groups.keys();keys.hasNext();){String group=keys.next();JSONArray list=groups.getJSONArray(group);
      for(int i=0;i<list.length();i++){checkFile(dir,list.getJSONObject(i).getString("File"));motions.add(group+":"+i);}}
    Map<String,Object> info=new HashMap<>();info.put("expressions",expressions);info.put("motions",motions);info.put("textures",tex.length());return info;
  }
}
