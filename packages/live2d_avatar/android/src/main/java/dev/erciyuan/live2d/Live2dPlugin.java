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
import java.util.LinkedHashMap;
import java.util.Arrays;
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
  private TextureRegistry.SurfaceProducer closingProducer;
  private CountDownLatch closeFinished;
  private long handle, frames, started, lastLoadMs;
  private boolean active = true, disposed = true;
  private String path;
  private String frameError;
  private float mouth, zoom=1, offsetX, offsetY;
  private String[] parameterIds = new String[0];
  private boolean manualPose;
  private float[] savedPose;
  private int[] savedParts;
  private String[][] poseParts = new String[0][];
  private int loads, unloads, surfaceRebuilds;
  private Map<String,Object> capabilities = new HashMap<>();
  private static native long nativeCreate(AssetManager assets, Surface surface);
  private static native void nativeLoad(long handle, String path);
  private static native void nativeCommand(long handle, String action, String value, float number);
  private static native void nativeFrame(long handle);
  private static native void nativeDestroy(long handle);
  private static native String[] nativeParameterIds(long handle);
  private static native float[] nativeParameterData(long handle);
  private static native void nativeSetPose(long handle, float[] updates);
  private static native int nativePosePart(long handle, String[] parts, int selected);

  private Map<String, Object> parameterInfo() {
    float[] data = nativeParameterData(handle);
    Map<String, Object> info = new LinkedHashMap<>();
    for (int i = 0; i < parameterIds.length; i++) {
      Map<String, Double> range = new HashMap<>();
      range.put("min", (double) data[4 * i]);
      range.put("max", (double) data[4 * i + 1]);
      range.put("default", (double) data[4 * i + 2]);
      info.put(parameterIds[i], range);
    }
    return info;
  }

  private Map<String, Double> parameterValues() {
    Map<String, Double> values = new LinkedHashMap<>();
    if (handle == 0 || path == null) return values;
    float[] data = nativeParameterData(handle);
    for (int i = 0; i < parameterIds.length; i++) {
      values.put(parameterIds[i], (double) data[4 * i + 3]);
    }
    return values;
  }

  private Map<String, Object> poseState() {
    Map<String, Object> state = new HashMap<>();
    state.put("parameters", parameterValues());
    ArrayList<Integer> selections = new ArrayList<>();
    if (handle != 0 && path != null) {
      for (String[] group : poseParts) selections.add(nativePosePart(handle, group, -1));
    }
    state.put("partSelections", selections);
    return state;
  }

  private Map<String, Object> setPose(Map<String, Number> changes, Map<Integer, Integer> selections) {
    if (handle == 0 || path == null) throw new IllegalStateException("Model surface unavailable");
    float[] updates = new float[parameterIds.length];
    Arrays.fill(updates, Float.NaN);
    float[] bounds = nativeParameterData(handle);
    var ids = Arrays.asList(parameterIds);
    for (var entry : changes.entrySet()) {
      int index = ids.indexOf(entry.getKey());
      float value = entry.getValue().floatValue();
      if (index < 0 || !Float.isFinite(value)) {
        throw new IllegalArgumentException("Invalid model parameter: " + entry.getKey());
      }
      updates[index] = Math.max(bounds[4 * index], Math.min(bounds[4 * index + 1], value));
    }
    for (var entry : selections.entrySet()) {
      int group = entry.getKey(), choice = entry.getValue();
      if (group < 0 || group >= poseParts.length || choice < 0 || choice >= poseParts[group].length) {
        throw new IllegalArgumentException("Invalid pose part selection");
      }
    }
    nativeSetPose(handle, updates);
    for (var entry : selections.entrySet()) {
      nativePosePart(handle, poseParts[entry.getKey()], entry.getValue());
    }
    manualPose = true;
    return poseState();
  }

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
    if (path != null && savedPose != null) {
      nativeSetPose(handle, savedPose);
      for (int i = 0; i < savedParts.length; i++) nativePosePart(handle, poseParts[i], savedParts[i]);
      savedPose = null;
      savedParts = null;
    }
    frameError=null;render.removeCallbacks(tick);if(active)render.post(tick);
  }
  private void destroyNative() {
    render.removeCallbacks(tick);
    if (handle != 0) {
      if (manualPose && path != null) {
        float[] data = nativeParameterData(handle);
        savedPose = new float[parameterIds.length];
        for (int i = 0; i < savedPose.length; i++) savedPose[i] = data[4 * i + 3];
        savedParts = new int[poseParts.length];
        for (int i = 0; i < savedParts.length; i++) savedParts[i] = nativePosePart(handle, poseParts[i], -1);
      }
      nativeDestroy(handle);
      handle = 0;
    }
  }
  private void close(Runnable done) {
    if(producer==null){done.run();return;}
    closingProducer = producer;
    producer = null;
    final var oldThread = thread;
    final var finished = new CountDownLatch(1);
    closeFinished = finished;
    render.post(() -> {
      try {
        disposed = true;
        path = null;
        manualPose = false;
        savedPose = null;
        savedParts = null;
        destroyNative();
      } finally {
        finished.countDown();
        oldThread.quitSafely();
        main.post(() -> {
          releaseClosingProducer();
          owner.set(false);
          done.run();
        });
      }
    });
  }

  private void releaseClosingProducer() {
    if (closingProducer == null) return;
    closingProducer.release();
    closingProducer = null;
    closeFinished = null;
  }

  @Override public void onDetachedFromEngine(FlutterPluginBinding b) {
    channel.setMethodCallHandler(null);
    close(() -> {});
    if (closeFinished == null) return;
    try {
      // The texture must be released on the main thread before FlutterJNI detaches.
      if (closeFinished.await(5, TimeUnit.SECONDS)) {
        releaseClosingProducer();
      } else {
        closingProducer = null;
        android.util.Log.e("Live2D", "Renderer teardown timed out during engine detach");
      }
    } catch (InterruptedException e) {
      closingProducer = null;
      Thread.currentThread().interrupt();
    }
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
            String[][] groups = readPoseParts(key);
            if(handle==0)throw new IllegalStateException("Surface unavailable");
            long t=SystemClock.elapsedRealtime();
            nativeLoad(handle,key);
            parameterIds = nativeParameterIds(handle);
            manualPose = false;
            savedPose = null;
            savedParts = null;
            poseParts = groups;
            var partGroups = new ArrayList<java.util.List<String>>();
            for (var group : groups) partGroups.add(Arrays.asList(group));
            info.put("poseParts", partGroups);
            info.put("parameters", parameterInfo());
            path=key;capabilities=info;lastLoadMs=SystemClock.elapsedRealtime()-t;loads++;frameError=null;
            response=info;break;
          }
          case "unload":
            path=null;capabilities=new HashMap<>();mouth=0;unloads++;
            parameterIds = new String[0];
            manualPose = false;
            savedPose = null;
            savedParts = null;
            poseParts = new String[0][];
            if(handle!=0)nativeCommand(handle,"unload","",0);break;
          case "active":
            active=Boolean.TRUE.equals(call.argument("value"));mouth=0;
            if(handle!=0)nativeCommand(handle,"mouth","",0);
            render.removeCallbacks(tick);if(active && handle!=0)render.post(tick);break;
          case "pose":
            response = setPose(call.argument("values"), call.argument("parts"));
            break;
          case "command": {
            String action=call.argument("action");String value=call.argument("value");Number number=call.argument("number");
            float n=number==null?0:number.floatValue();
            if(!Float.isFinite(n))throw new IllegalArgumentException("Parameter must be finite");
            if(action.equals("mouth"))mouth=Math.max(0,Math.min(1,n));
            if(action.equals("zoom"))zoom=Math.max(.4f,Math.min(3,n));
            if(action.equals("x"))offsetX=Math.max(-2,Math.min(2,n));
            if(action.equals("y"))offsetY=Math.max(-2,Math.min(2,n));
            if(handle==0)throw new IllegalStateException("Surface unavailable");
            nativeCommand(handle,action,value==null?"":value,n);
            if (action.equals("automaticPose") || action.equals("motion") || action.equals("expression")) {
              manualPose = false;
            }
            break;
          }
          case "stats": {
            Map<String,Object> s=new HashMap<>();s.put("frames",frames);s.put("elapsedMs",SystemClock.elapsedRealtime()-started);
            s.put("loadMs",lastLoadMs);s.put("loads",loads);s.put("unloads",unloads);s.put("surfaceRebuilds",surfaceRebuilds);
            s.put("nativeInstances",handle==0?0:1);s.put("models",path==null?0:1);s.put("active",active);
            s.put("mouth",mouth);s.put("error",frameError);s.put("capabilities",capabilities);
            s.putAll(poseState());
            s.put("manualPose", manualPose);
            response=s;break;
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
  private String[][] readPoseParts(String modelPath) throws Exception {
    JSONObject refs = readJson(modelPath).getJSONObject("FileReferences");
    if (!refs.has("Pose")) return new String[0][];
    String dir = modelPath.substring(0, modelPath.lastIndexOf('/') + 1);
    JSONArray groups = readJson(dir + refs.getString("Pose")).getJSONArray("Groups");
    String[][] result = new String[groups.length()][];
    for (int i = 0; i < groups.length(); i++) {
      JSONArray group = groups.getJSONArray(i);
      result[i] = new String[group.length()];
      for (int j = 0; j < group.length(); j++) result[i][j] = group.getJSONObject(j).getString("Id");
    }
    return result;
  }

  private JSONObject readJson(String key) throws Exception {
    try(InputStream in=binding.getApplicationContext().getAssets().open(key)) {
      ByteArrayOutputStream bytes=new ByteArrayOutputStream();byte[] buffer=new byte[4096];int n;
      while((n=in.read(buffer))!=-1){bytes.write(buffer,0,n);if(bytes.size()>1024*1024)throw new IllegalArgumentException("Model descriptor too large");}
      return new JSONObject(bytes.toString(StandardCharsets.UTF_8.name()));
    }
  }

  private Map<String,Object> validate(String key) throws Exception {
    JSONObject json = readJson(key);
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
    ArrayList<String> lipSync=new ArrayList<>();JSONArray parameterGroups=json.optJSONArray("Groups");
    if(parameterGroups!=null)for(int i=0;i<parameterGroups.length();i++){
      JSONObject group=parameterGroups.getJSONObject(i);
      if("LipSync".equals(group.optString("Name")) && "Parameter".equals(group.optString("Target"))){
        JSONArray ids=group.getJSONArray("Ids");for(int j=0;j<ids.length();j++)lipSync.add(ids.getString(j));
      }
    }
    Map<String,Object> info=new HashMap<>();info.put("expressions",expressions);info.put("motions",motions);
    info.put("lipSyncParameters",lipSync);info.put("textures",tex.length());return info;
  }
}
