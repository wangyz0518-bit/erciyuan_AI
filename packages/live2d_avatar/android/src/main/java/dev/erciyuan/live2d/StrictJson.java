package dev.erciyuan.live2d;

import android.util.JsonReader;
import android.util.JsonToken;
import java.io.*;
import java.nio.charset.*;
import org.json.*;

/** Bounded, strict UTF-8 JSON; JSONObject alone silently accepts duplicate keys. */
final class StrictJson {
  static JSONObject read(File file) throws Exception {
    if (file.length() == 0 || file.length() > 1024 * 1024) throw new IOException("JSON 大小超限: " + file.getName());
    var decoder = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT);
    try (var r = new JsonReader(new InputStreamReader(new FileInputStream(file), decoder))) {
      r.setLenient(false);
      Object result = value(r, 0);
      if (!(result instanceof JSONObject) || r.peek() != JsonToken.END_DOCUMENT) throw new IOException("JSON 根必须为单一对象");
      return (JSONObject) result;
    }
  }
  private static Object value(JsonReader r, int depth) throws Exception {
    if (depth > 64) throw new IOException("JSON 嵌套过深");
    switch (r.peek()) {
      case BEGIN_OBJECT: {
        var o = new JSONObject(); r.beginObject();
        while (r.hasNext()) {
          String key = r.nextName();
          if (o.has(key)) throw new IOException("JSON 重复键: " + key);
          o.put(key, value(r, depth + 1));
        }
        r.endObject(); return o;
      }
      case BEGIN_ARRAY: {
        var a = new JSONArray(); r.beginArray();
        while (r.hasNext()) a.put(value(r, depth + 1));
        r.endArray(); return a;
      }
      case STRING: return r.nextString();
      case BOOLEAN: return r.nextBoolean();
      case NULL: r.nextNull(); return JSONObject.NULL;
      case NUMBER: {
        String s = r.nextString();
        if (!s.matches("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?")) throw new IOException("JSON 数字无效");
        double n = Double.parseDouble(s);
        if (!Double.isFinite(n)) throw new IOException("JSON 数字非有限值");
        return n;
      }
      default: throw new IOException("JSON 语法无效");
    }
  }
}
