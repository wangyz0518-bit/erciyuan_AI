import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../timeline/data/person_database.dart';

/// Explicit, owner-scoped JSON export using the existing #36 export contract.
/// No automatic upload or external sharing service is involved.
class DataManagementPage extends StatefulWidget {
  const DataManagementPage({
    required this.database,
    required this.ownerId,
    super.key,
  });

  final PersonDatabase database;
  final String ownerId;

  @override
  State<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends State<DataManagementPage> {
  bool _working = false;
  String? _message;
  String? _lastExport;
  int? _characterCount;
  int? _eventCount;

  Future<void> _export() async {
    if (_working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final exported = await widget.database.exportOwnerJson(widget.ownerId);
      final json = jsonDecode(exported) as Map<String, dynamic>;
      await Clipboard.setData(ClipboardData(text: exported));
      if (!mounted) return;
      setState(() {
        _lastExport = exported;
        _characterCount = (json['characters'] as List).length;
        _eventCount = (json['raw_events'] as List).length;
        _message = '已将完整 JSON 数据复制到剪贴板，请粘贴保存到安全位置。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = '导出失败：$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我的 / 数据管理')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.folder_copy_outlined, size: 52),
          const SizedBox(height: 16),
          const Text(
            '导出全部人物数据',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            '一次性导出此本地用户的所有人物、全部原始消息、记忆摘要、身份版本与生成任务。'
            '使用 #36 的正式 SQLite 导出接口，不删除或压缩聊天原始记录。',
          ),
          const SizedBox(height: 12),
          const Text(
            '导出包含私人聊天内容。复制后，请将 JSON 粘贴至可信的本地文件中妥善保管，'
            '不要随意发送给其他应用或服务。',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const ValueKey('export-all-person-data'),
            onPressed: _working ? null : _export,
            icon: const Icon(Icons.content_copy),
            label: Text(_working ? '导出中…' : '一键导出并复制全部 JSON'),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                _message!,
                key: const ValueKey('export-status'),
              ),
            ),
          if (_lastExport != null) ...[
            const SizedBox(height: 20),
            Text(
              '已导出人物：$_characterCount · 原始记录：$_eventCount · '
              'JSON 字符：${_lastExport!.length}',
              key: const ValueKey('export-summary'),
            ),
            const SizedBox(height: 8),
            const Text('以下为导出内容的开头预览（完整内容已复制）：'),
            const SizedBox(height: 8),
            SelectableText(
              _lastExport!.substring(
                0,
                _lastExport!.length > 1200 ? 1200 : _lastExport!.length,
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ],
      ),
    ),
  );
}
