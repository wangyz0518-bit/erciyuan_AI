package dev.erciyuan.live2d;

import android.content.Context;
import android.graphics.BitmapFactory;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.json.*;

final class AvatarPackageStore {
  private final Context context;
  private final File base, receipts;
  AvatarPackageStore(Context context) {
    this.context=context;
    base=new File(context.getFilesDir(),"avatar-packages");
    receipts=new File(context.getFilesDir(),"avatar-receipts");
    base.mkdirs(); receipts.mkdirs();
  }
  String key(AvatarPackage p) throws Exception { return p.manifest.getString("id")+"@"+p.manifest.getString("version"); }
  private File receipt(String key) throws Exception {
    AvatarPackage.need(key.matches("[a-z][a-z0-9_-]{2,63}@[0-9]+\\.[0-9]+\\.[0-9]+"),"包标识无效");
    return new File(receipts,key+".json");
  }
  AvatarPackage prepare(String source) throws Exception {
    File staging=new File(base,"stage-"+UUID.randomUUID());
    AvatarPackage.need(staging.mkdir(),"无法创建导入目录");
    try {
      File zip=new File(source);
      AvatarPackage.unpack(zip,staging);
      AvatarPackage p=new AvatarPackage(staging);
      p.zipHash=AvatarPackage.hash(zip); p.contentHash=AvatarPackage.contentHash(staging);
      File existing=receipt(key(p));
      if(existing.isFile()) {
        AvatarPackage.need(StrictJson.read(existing).getString("contentHash").equals(p.contentHash),"同 id/version 内容不同，请提升资源版本");
        AvatarPackage installed=open(key(p)); installed.zipHash=p.zipHash; return installed;
      }
      var cover=BitmapFactory.decodeFile(p.file(p.manifest.getString("preview")).getPath());
      AvatarPackage.need(cover!=null,"封面 PNG 解码失败"); cover.recycle();
      File installed=new File(base,p.contentHash);
      if(installed.exists()) AvatarPackage.delete(installed); // Uncommitted residue only; content hash is unique.
      AvatarPackage.need(staging.renameTo(installed),"原子安装失败");
      AvatarPackage result=new AvatarPackage(installed);
      result.zipHash=p.zipHash; result.contentHash=p.contentHash;
      return result;
    } finally { if(staging.exists()) AvatarPackage.delete(staging); }
  }
  AvatarPackage open(String key) throws Exception {
    JSONObject r=StrictJson.read(receipt(key)); String hash=r.getString("contentHash");
    AvatarPackage.need(hash.matches("[a-f0-9]{64}"),"本地包记录损坏");
    File root=new File(base,hash);
    AvatarPackage.need(AvatarPackage.contentHash(root).equals(hash),"本地资源完整性校验失败");
    AvatarPackage p=new AvatarPackage(root); p.contentHash=hash; p.zipHash=r.getString("sha256"); return p;
  }
  String last() { return context.getSharedPreferences("avatar-packages",0).getString("selected",""); }
  void commit(AvatarPackage p) throws Exception {
    JSONObject r=new JSONObject(); r.put("contentHash",p.contentHash); r.put("sha256",p.zipHash);
    File target=receipt(key(p)),temp=new File(receipts,"pending.json");
    try(var out=new FileOutputStream(temp)) { out.write(r.toString().getBytes(StandardCharsets.UTF_8)); out.getFD().sync(); }
    // Android's rename within filesDir is atomic and available on the plugin's API 24 minimum.
    AvatarPackage.need(temp.renameTo(target),"安装记录原子提交失败");
    AvatarPackage.need(context.getSharedPreferences("avatar-packages",0).edit().putString("selected",key(p)).commit(),"包选择保存失败");
  }
  void discard(AvatarPackage p) throws Exception { if(p!=null && !receipt(key(p)).isFile()) AvatarPackage.delete(p.root); }
  String describe(AvatarPackage p) throws Exception {
    JSONObject o=new JSONObject(); o.put("manifest",p.manifest); o.put("key",key(p));
    o.put("sha256",p.zipHash); o.put("contentHash",p.contentHash);
    o.put("previewPath",p.file(p.manifest.getString("preview")).getPath());
    o.put("structure","passed"); o.put("sdk","passed"); o.put("visual","manual-review");
    return o.toString();
  }
  String list() throws Exception {
    JSONArray result=new JSONArray(); File[] files=receipts.listFiles();
    if(files!=null) for(File f:files) if(f.getName().endsWith(".json") && !f.getName().equals("pending.json")) {
      String key=f.getName().substring(0,f.getName().length()-5);
      try { JSONObject receipt=StrictJson.read(f); File root=new File(base,receipt.getString("contentHash"));
        JSONObject m=StrictJson.read(new File(root,"manifest.json"));
        result.put(new JSONObject().put("key",key).put("name",m.getString("name")).put("version",m.getString("version")));
      } catch(Exception ignored) { /* A corrupted local package is not selectable. */ }
    }
    return result.toString();
  }
}
