package dev.erciyuan.live2d;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.zip.*;
import org.json.*;

/** v0.1 data-only package gate. Runs on the render worker, before calling Cubism. */
final class AvatarPackage {
  static final long MIB = 1024L * 1024;
  final File root;
  final JSONObject manifest;
  final Set<String> parameters = new LinkedHashSet<>(), parts = new LinkedHashSet<>();
  final Set<String> opacityParts = new LinkedHashSet<>();
  final Map<String, String> motions = new LinkedHashMap<>();
  String zipHash, contentHash;
  private final Map<String, JSONObject> json = new HashMap<>();
  // R5's JSON reader needs a newline after final numbers and lacks exponent/unicode escapes.
  // Normalize in memory only: preserve the delivered files and content hash byte-for-byte.
  String[] sdkPaths() { return json.keySet().toArray(new String[0]); }
  String[] sdkJson(String[] paths) throws Exception {
    String[] values=new String[paths.length];
    for(int i=0;i<paths.length;i++) values[i]=sdkValue(json.get(paths[i]));
    return values;
  }
  private static String sdkValue(Object value) throws Exception {
    if(value instanceof JSONObject) {
      JSONObject o=(JSONObject)value; StringBuilder out=new StringBuilder("{\n"); int count=0;
      for(var keys=o.keys();keys.hasNext();) {String k=keys.next(); if(count++>0)out.append(",\n");out.append(sdkValue(k)).append(": ").append(sdkValue(o.get(k)));}
      return out.append("\n}").toString();
    }
    if(value instanceof JSONArray) {
      JSONArray a=(JSONArray)value; StringBuilder out=new StringBuilder("[\n");
      for(int i=0;i<a.length();i++){if(i>0)out.append(",\n");out.append(sdkValue(a.get(i)));}
      return out.append("\n]").toString();
    }
    if(value instanceof Number) return java.math.BigDecimal.valueOf(((Number)value).doubleValue()).stripTrailingZeros().toPlainString();
    if(value instanceof String) {
      StringBuilder out=new StringBuilder("\"");
      for(char c:((String)value).toCharArray()) {
        switch(c) {
          case '\\': out.append("\\\\"); break; case '"': out.append("\\\""); break;
          case '\n': out.append("\\n"); break; case '\r': out.append("\\r"); break; case '\t': out.append("\\t"); break;
          case '\b': out.append("\\b"); break; case '\f': out.append("\\f"); break;
          default: need(c>=32,"SDK 不支持此控制字符");out.append(c);
        }
      }
      return out.append('"').toString();
    }
    return value.toString();
  }

  static void need(boolean ok, String message) throws IOException {
    if (!ok) throw new IOException(message);
  }
  static String path(String s) throws IOException {
    need(s.length() <= 180 && !s.contains("..") && s.matches("[A-Za-z0-9_-][A-Za-z0-9_.-]*(/[A-Za-z0-9_-][A-Za-z0-9_.-]*)*"), "路径非法: " + s);
    return s;
  }
  File file(String s) throws IOException {
    File f = new File(root, path(s));
    need(f.getCanonicalPath().startsWith(root.getCanonicalPath() + File.separator), "路径越界");
    need(f.isFile() && f.length() > 0, "资源缺失或为空: " + s);
    return f;
  }
  JSONObject json(String s) throws Exception {
    if (!json.containsKey(s)) json.put(s, StrictJson.read(file(s)));
    return json.get(s);
  }
  static String string(JSONObject o, String key) throws Exception {
    need(o.get(key) instanceof String, "字段必须是字符串: " + key);
    return o.getString(key);
  }
  static double number(JSONObject o, String key) throws Exception {
    need(o.get(key) instanceof Number, "字段必须是数字: " + key);
    return o.getDouble(key);
  }
  static int integer(JSONObject o, String key, int min, int max) throws Exception {
    double n = number(o, key);
    need(n == Math.rint(n) && n >= min && n <= max, "整数范围无效: " + key);
    return (int)n;
  }
  static void fields(JSONObject o, String required, String optional) throws Exception {
    Set<String> allowed = new HashSet<>(Arrays.asList((required + " " + optional).split(" ")));
    for (var it = o.keys(); it.hasNext();) { String key = it.next(); need(allowed.contains(key), "不支持的字段: " + key); }
    for (String key : required.split(" ")) if (!key.isEmpty()) need(o.has(key), "缺少字段: " + key);
  }
  static void eq(JSONObject o, String k, String v) throws Exception { need(string(o,k).equals(v), "不支持的 " + k + "，要求 " + v); }
  static void label(JSONObject o, String key, int max) throws Exception {
    String s = string(o,key); need(s.codePointCount(0,s.length()) >= 1 && s.codePointCount(0,s.length()) <= max, "文字长度无效: " + key);
  }
  static void png(File file, int cap) throws Exception {
    try (var in = new DataInputStream(new FileInputStream(file))) {
      need(in.readLong() == 0x89504e470d0a1a0aL && in.readInt() == 13 && in.readInt() == 0x49484452, "不是 PNG: " + file.getName());
      int w = in.readInt(), h = in.readInt(), depth = in.readUnsignedByte(), color = in.readUnsignedByte();
      need(w > 0 && h > 0 && w <= cap && h <= cap, "PNG 尺寸超限: " + file.getName());
      need(depth == 8 && (color == 6 || color == 2 || color == 3), "不支持的 PNG 编码");
    }
  }

  AvatarPackage(File directory) throws Exception {
    root = directory;
    manifest = json("manifest.json");
    fields(manifest, "format formatVersion id version name renderer runtimeProfile entry preview actions", "expressions");
    eq(manifest,"format","erciyuan-avatar"); eq(manifest,"formatVersion","0.1");
    eq(manifest,"renderer","live2d-cubism"); eq(manifest,"runtimeProfile","native-r5-basic-v1");
    need(string(manifest,"id").matches("[a-z][a-z0-9_-]{2,63}"), "id 格式无效");
    need(string(manifest,"version").matches("[0-9]+\\.[0-9]+\\.[0-9]+"), "version 格式无效"); label(manifest,"name",64);
    String entry = path(string(manifest,"entry")), preview = path(string(manifest,"preview"));
    need(entry.endsWith(".model3.json") && preview.endsWith(".png"), "入口或封面后缀无效"); png(file(preview),1024);
    JSONObject model = json(entry);
    fields(model,"Version FileReferences", "Groups Layout HitAreas"); integer(model,"Version",3,3);
    JSONObject refs = model.getJSONObject("FileReferences");
    fields(refs,"Moc Textures Motions","Physics Pose Expressions UserData DisplayInfo");
    String dir = entry.substring(0,entry.lastIndexOf('/')+1);
    String moc = dir + path(string(refs,"Moc")); need(moc.endsWith(".moc3"),"需要 MOC3"); file(moc);
    JSONArray textures = refs.getJSONArray("Textures"); need(textures.length() >= 1 && textures.length() <= 4,"纹理数量应为 1–4");
    for(int i=0;i<textures.length();i++) png(file(dir+path(textures.getString(i))),2048);
    if (model.has("Groups")) for (int i=0;i<model.getJSONArray("Groups").length();i++) {
      JSONObject g=model.getJSONArray("Groups").getJSONObject(i);
      eq(g,"Target","Parameter"); eq(g,"Name","EyeBlink");
      JSONArray ids=g.getJSONArray("Ids"); for(int j=0;j<ids.length();j++) parameters.add(ids.getString(j));
    }
    JSONObject groups=refs.getJSONObject("Motions");
    need(groups.has("Idle") && groups.getJSONArray("Idle").length()==1,"必须只有一个 Idle 动作");
    Map<String,Boolean> loops=new HashMap<>(); int motionCount=0;
    for(var keys=groups.keys();keys.hasNext();) {
      String group=keys.next(); need(group.matches("[A-Za-z][A-Za-z0-9_]{0,31}"),"动作分组名称无效");
      JSONArray list=groups.getJSONArray(group); need(list.length()<=64,"动作分组过大");
      for(int i=0;i<list.length();i++) {
        need(++motionCount<=256,"模型动作过多");
        JSONObject m=list.getJSONObject(i); fields(m,"File FadeInTime FadeOutTime","");
        need(number(m,"FadeInTime")>=0 && number(m,"FadeOutTime")>=0,"动作淡入淡出无效");
        String f=dir+path(string(m,"File"));
        need(f.endsWith(".motion3.json"),"动作文件后缀无效");
        boolean loop=motion(json(f));
        need(loop==group.equals("Idle"),"动作循环与分组不一致: "+f);
        motions.put(group+":"+i,f); loops.put(group+":"+i,loop);
      }
    }
    JSONObject actions=manifest.getJSONObject("actions");
    need(actions.length()>=3 && actions.length()<=24 && actions.has("idle") && actions.has("wave") && actions.has("weight_shift"),"必须声明 idle、wave 和 weight_shift");
    for(var keys=actions.keys();keys.hasNext();) {
      String id=keys.next(); need(id.matches("[a-z][a-z0-9_]{0,31}"),"动作 ID 无效");
      JSONObject a=actions.getJSONObject(id); boolean idle=id.equals("idle");
      fields(a,"label group index playback"+(idle?"":" returnTo"),""); label(a,"label",32);
      String group=string(a,"group"); int index=integer(a,"index",0,63);
      String key=group+":"+index;
      need(motions.containsKey(key),"动作映射无效: "+id);
      if(idle) { need(group.equals("Idle") && index==0,"idle 映射无效"); eq(a,"playback","loop"); }
      else { need(!group.equals("Idle"),"触发动作不能映射到 Idle"); eq(a,"playback","once"); eq(a,"returnTo","idle"); }
    }
    String wave=motions.get(actionKey("wave")), shift=motions.get(actionKey("weight_shift"));
    need(!wave.equals(shift) && !hash(file(wave)).equals(hash(file(shift))),"wave 与 weight_shift 必须是不同动作");
    Set<String> expressions=new HashSet<>();
    if(refs.has("Expressions")) {
      JSONArray list=refs.getJSONArray("Expressions");
      for(int i=0;i<list.length();i++) {
        JSONObject e=list.getJSONObject(i); fields(e,"Name File","");
        need(expressions.add(string(e,"Name")),"重复的表情名称");
        JSONObject expression=json(dir+path(string(e,"File"))); eq(expression,"Type","Live2D Expression");
        JSONArray ps=expression.getJSONArray("Parameters");
        for(int j=0;j<ps.length();j++) { JSONObject p=ps.getJSONObject(j); parameters.add(string(p,"Id")); number(p,"Value");
          need(Arrays.asList("Add","Multiply","Overwrite").contains(p.optString("Blend","Add")),"表情 Blend 无效"); }
      }
    }
    if(manifest.has("expressions")) {
      JSONObject ex=manifest.getJSONObject("expressions"); need(ex.length()<=16,"表情过多");
      for(var keys=ex.keys();keys.hasNext();) { String id=keys.next(); need(id.matches("[a-z][a-z0-9_]{0,31}"),"表情 ID 无效");
        JSONObject e=ex.getJSONObject(id); fields(e,"label name",""); label(e,"label",32); label(e,"name",64);
        need(expressions.contains(string(e,"name")),"表情映射无效: "+id); }
    }
    if(refs.has("Pose")) {
      JSONObject pose=json(dir+path(string(refs,"Pose"))); integer(pose,"Version",3,3);
      JSONArray gs=pose.getJSONArray("Groups");
      for(int i=0;i<gs.length();i++) { JSONArray ps=gs.getJSONArray(i); need(ps.length()>0,"Pose 空分组");
        for(int j=0;j<ps.length();j++) { JSONObject p=ps.getJSONObject(j); parts.add(string(p,"Id"));
          if(p.has("Link")) for(int k=0;k<p.getJSONArray("Link").length();k++) parts.add(p.getJSONArray("Link").getString(k)); }
      }
    }
    if(refs.has("Physics")) physics(json(dir+path(string(refs,"Physics"))));
    for(String optional:new String[]{"UserData","DisplayInfo"}) if(refs.has(optional)) json(dir+path(string(refs,optional)));
  }
  String actionKey(String id) throws Exception {
    JSONObject a=manifest.getJSONObject("actions").getJSONObject(id);
    return a.getString("group")+":"+a.getInt("index");
  }
  private boolean motion(JSONObject m) throws Exception {
    fields(m,"Version Meta Curves","UserData FadeInTime FadeOutTime"); integer(m,"Version",3,3);
    JSONObject meta=m.getJSONObject("Meta"); double duration=number(meta,"Duration");
    need(duration>0 && duration<=20 && number(meta,"Fps")>0,"动作时长或 FPS 无效");
    need(meta.get("Loop") instanceof Boolean,"Loop 必须是布尔值");
    need(meta.optInt("UserDataCount",0)==0 && (!m.has("UserData") || m.getJSONArray("UserData").length()==0),"不支持动作事件");
    JSONArray curves=m.getJSONArray("Curves"); int segments=0,points=0;
    Set<String> seen=new HashSet<>(); int lastTarget=0;
    need(integer(meta,"CurveCount",1,4096)==curves.length(),"曲线数量不匹配");
    for(int i=0;i<curves.length();i++) {
      JSONObject c=curves.getJSONObject(i); String target=string(c,"Target"),id=string(c,"Id");
      int rank=target.equals("Model")?0:target.equals("Parameter")?1:2;
      need(rank>=lastTarget,"曲线需按 Model、Parameter、PartOpacity 顺序导出");lastTarget=rank;
      need(seen.add(target+":"+id),"重复动作曲线");
      if(target.equals("Parameter")) parameters.add(id);
      else if(target.equals("PartOpacity")) { parts.add(id);opacityParts.add(id); }
      else need(target.equals("Model") && Arrays.asList("EyeBlink","LipSync","Opacity").contains(id) && !id.equals("LipSync"),"不支持的曲线目标");
      JSONArray s=c.getJSONArray("Segments"); need(s.length()>=5,"动作曲线为空");
      double time=numeric(s,0); need(time==0,"曲线必须从 0 秒开始"); numeric(s,1); points++;
      for(int p=2;p<s.length();) {
        double type=numeric(s,p++); need(type==0 || type==1 || type==2 || type==3,"曲线类型无效");
        int count=type==1?3:1; need(p+count*2<=s.length(),"曲线片段截断");
        double start=time;
        for(int q=0;q<count;q++) { double t=numeric(s,p++); numeric(s,p++); need(t>=time && t<=duration+0.00001,"曲线时间无效"); time=t; points++; }
        need(time>start,"曲线片段不能为零时长");
        segments++;
      }
      need(Math.abs(time-duration)<0.0001,"曲线必须覆盖完整时长");
    }
    need(integer(meta,"TotalSegmentCount",1,200000)==segments && integer(meta,"TotalPointCount",1,200000)==points,"曲线计数不匹配");
    return meta.getBoolean("Loop");
  }
  private static double numeric(JSONArray a,int i) throws Exception { need(a.get(i) instanceof Number,"曲线数值无效"); return a.getDouble(i); }
  private void physics(JSONObject p) throws Exception {
    integer(p,"Version",3,3); JSONObject meta=p.getJSONObject("Meta"); JSONArray settings=p.getJSONArray("PhysicsSettings");
    need(integer(meta,"PhysicsSettingCount",1,256)==settings.length(),"物理分组计数无效");
    int ins=0,outs=0,vertices=0;
    for(int i=0;i<settings.length();i++) {
      JSONObject s=settings.getJSONObject(i); JSONArray vs=s.getJSONArray("Vertices"); need(vs.length()>=2,"物理顶点不足"); vertices+=vs.length();
      for(String key:new String[]{"Input","Output"}) {
        JSONArray list=s.getJSONArray(key); if(key.equals("Input")) ins+=list.length(); else outs+=list.length();
        for(int j=0;j<list.length();j++) { JSONObject v=list.getJSONObject(j); JSONObject ref=v.getJSONObject(key.equals("Input")?"Source":"Destination");
          eq(ref,"Target","Parameter"); parameters.add(string(ref,"Id"));
          need(Arrays.asList("X","Y","Angle").contains(string(v,"Type")),"物理类型无效");
          double weight=number(v,"Weight"); need(weight>=0 && weight<=100,"物理权重无效");
          need(v.get("Reflect") instanceof Boolean,"物理 Reflect 无效");
          if(key.equals("Output")) { integer(v,"VertexIndex",1,vs.length()-1); number(v,"Scale"); }
        }
      }
      JSONObject norm=s.getJSONObject("Normalization");
      for(String key:new String[]{"Position","Angle"}) { JSONObject n=norm.getJSONObject(key); double lo=number(n,"Minimum"),hi=number(n,"Maximum"),def=number(n,"Default"); need(lo<hi && def>=lo && def<=hi,"物理归一化无效"); }
      for(int j=0;j<vs.length();j++) { JSONObject v=vs.getJSONObject(j); number(v.getJSONObject("Position"),"X"); number(v.getJSONObject("Position"),"Y");
        for(String k:new String[]{"Mobility","Delay","Acceleration","Radius"}) need(number(v,k)>=0,"物理顶点无效"); }
    }
    need(integer(meta,"TotalInputCount",0,100000)==ins && integer(meta,"TotalOutputCount",0,100000)==outs && integer(meta,"VertexCount",0,100000)==vertices,"物理总计数无效");
  }

  static String hash(File f) throws Exception {
    MessageDigest d=MessageDigest.getInstance("SHA-256");
    try(var in=new FileInputStream(f)) { byte[] b=new byte[16384]; int n; while((n=in.read(b))!=-1)d.update(b,0,n); }
    return hex(d.digest());
  }
  static String hex(byte[] b) { StringBuilder s=new StringBuilder(); for(byte v:b)s.append(String.format(Locale.ROOT,"%02x",v&255)); return s.toString(); }
  private static long u32(RandomAccessFile f) throws Exception { return Integer.toUnsignedLong(Integer.reverseBytes(f.readInt())); }
  private static int u16(RandomAccessFile f) throws Exception { return Short.toUnsignedInt(Short.reverseBytes(f.readShort())); }

  /** Inspect central and local headers before inflation; no ZIP64, links or encryption. */
  static void unpack(File zip, File target) throws Exception {
    need(zip.isFile() && zip.length()>22 && zip.length()<=64*MIB,"ZIP 大小应小于 64 MiB");
    Map<String,Long> sizes=new LinkedHashMap<>(); Set<String> names=new HashSet<>();
    try(var f=new RandomAccessFile(zip,"r")) {
      long end=-1;
      for(long p=f.length()-22;p>=Math.max(0,f.length()-65557);p--) { f.seek(p); if(u32(f)==0x06054b50L) { f.seek(p+20); if(p+22+u16(f)==f.length()) { end=p; break; } } }
      need(end>=0,"ZIP 目录缺失"); f.seek(end+4); need(u16(f)==0 && u16(f)==0,"不支持分卷 ZIP");
      int count=u16(f); need(count==u16(f) && count>0 && count<=512,"ZIP 条目数量超限");
      long cdSize=u32(f),cd=u32(f); need(cd+cdSize==end,"ZIP 目录范围无效"); f.seek(cd); long total=0; int files=0;
      for(int i=0;i<count;i++) {
        need(u32(f)==0x02014b50L,"ZIP 目录损坏"); int made=u16(f); u16(f); int flags=u16(f),method=u16(f);
        need((flags & ~0x080e)==0 && (method==0 || method==8),"不支持加密或压缩方式");
        f.skipBytes(8); long compressed=u32(f),size=u32(f); int nameLen=u16(f),extra=u16(f),comment=u16(f); need(u16(f)==0,"不支持分卷");
        u16(f); long attr=u32(f),local=u32(f); byte[] nameBytes=new byte[nameLen]; f.readFully(nameBytes);
        String name=new String(nameBytes,StandardCharsets.US_ASCII); boolean dir=name.endsWith("/");
        String checked=path(dir?name.substring(0,name.length()-1):name);
        need(names.add(checked.toLowerCase(Locale.ROOT)),"重复或大小写冲突路径: "+name);
        int mode=(int)(attr>>16)&0170000;
        need(mode==0 || mode==(dir?0040000:0100000),"不接受链接或特殊文件");
        need(local+30+nameLen+compressed<=cd,"ZIP 资源范围无效");
        long next=f.getFilePointer()+extra+comment; need(next<=end,"ZIP 目录越界");
        f.seek(local); need(u32(f)==0x04034b50L,"ZIP 本地头损坏"); u16(f);
        need(u16(f)==flags && u16(f)==method,"ZIP 头信息不一致"); f.skipBytes(16); int ln=u16(f),le=u16(f);
        byte[] localName=new byte[ln]; f.readFully(localName); need(Arrays.equals(localName,nameBytes),"ZIP 文件名不一致");
        need(f.getFilePointer()+le+compressed<=cd,"ZIP 数据越界"); f.seek(next);
        if(dir) { need(size==0,"目录条目大小无效"); continue; }
        need(++files<=256,"普通文件超过 256 个");
        need(name.endsWith(".json") || name.endsWith(".png") || name.endsWith(".moc3"),"不接受此文件类型: "+name);
        need(size>0 && size<=(name.endsWith(".json")?MIB:64*MIB),"单文件大小超限: "+name);
        total+=size; need(total<=128*MIB,"解压大小超过 128 MiB"); sizes.put(name,size);
      }
      need(f.getFilePointer()==end,"ZIP 目录长度不一致");
    }
    need(sizes.keySet().stream().filter(n->n.endsWith(".model3.json")).count()==1 && sizes.keySet().stream().filter(n->n.endsWith(".moc3")).count()==1,"每包必须只有一个模型");
    long total=0;
    try(var z=new ZipFile(zip)) {
      for(var entry:sizes.entrySet()) {
        ZipEntry e=z.getEntry(entry.getKey()); need(e!=null && e.getSize()==entry.getValue(),"ZIP 条目不一致");
        File out=new File(target,entry.getKey()); need(out.getCanonicalPath().startsWith(target.getCanonicalPath()+File.separator),"路径越界");
        need(out.getParentFile().isDirectory() || out.getParentFile().mkdirs(),"无法创建资源目录");
        CRC32 crc=new CRC32(); long written=0;
        try(var in=z.getInputStream(e); var stream=new FileOutputStream(out)) {
          byte[] b=new byte[16384]; int n;
          while((n=in.read(b))!=-1) { written+=n; total+=n; need(written<=entry.getValue() && total<=128*MIB,"实际解压大小超限"); stream.write(b,0,n); crc.update(b,0,n); }
        }
        need(written==entry.getValue() && crc.getValue()==e.getCrc(),"ZIP 长度或 CRC 校验失败");
        if(entry.getKey().endsWith(".json")) StrictJson.read(out);
        if(entry.getKey().endsWith(".png")) png(out,2048);
      }
    }
  }
  static String contentHash(File root) throws Exception {
    var files=new ArrayList<File>(); collect(root,files); files.sort(Comparator.comparing(File::getAbsolutePath));
    MessageDigest d=MessageDigest.getInstance("SHA-256");
    for(File f:files) { String name=f.getAbsolutePath().substring(root.getAbsolutePath().length()+1).replace('\\','/');
      d.update(name.getBytes(StandardCharsets.US_ASCII)); d.update((byte)0); d.update(hash(f).getBytes(StandardCharsets.US_ASCII)); }
    return hex(d.digest());
  }
  private static void collect(File root,List<File> files) throws Exception {
    File[] children=root.listFiles(); need(children!=null,"目录不可读");
    for(File f:children) { if(f.isDirectory())collect(f,files); else files.add(f); }
  }
  static void delete(File root) throws IOException {
    if(root.isDirectory()) { File[] children=root.listFiles(); if(children!=null)for(File f:children)delete(f); }
    if(root.exists() && !root.delete()) throw new IOException("无法清理临时资源");
  }
}
