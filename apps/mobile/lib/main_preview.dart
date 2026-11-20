import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'bootstrap.dart';
import 'features/memory/domain/memory_models.dart';
import 'features/timeline/data/person_database.dart';

@JS('companionSession')
external JSString get _session;
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final database = await PersonDatabase.open(
      factory: databaseFactoryFfiWeb,
      databasePath: 'companion-browser.db',
      automaticSummarizer: const DeterministicSummarizer(),
    );
    runApp(
      await bootstrapCompanionApp(
        database: database,
        gatewayUri: Uri.parse('http://127.0.0.1:18791'),
        gatewayToken: _session.toDart,
      ),
    );
  } catch (_) {
    runApp(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Text('浏览器无法打开本地人物数据库，请使用启用了网站存储的 Edge 或 Chrome 刷新页面。'),
        ),
      ),
    );
  }
}
