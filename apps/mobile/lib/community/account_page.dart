import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import 'community_api.dart';
import 'community_controller.dart';

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<List<String>?> accountFields(
  BuildContext context,
  String title,
  List<String> labels, {
  bool showUsername = false,
  String? notice,
}) {
  final values = List.filled(labels.length, '');
  return showDialog<List<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (notice != null) Text(notice),
              for (int i = 0; i < labels.length; i++)
                TextField(
                  decoration: InputDecoration(labelText: labels[i]),
                  maxLength: 128,
                  obscureText: !(showUsername && i == 0),
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (value) => update(() => values[i] = value),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: values.any((v) => v.isEmpty)
                ? null
                : () => Navigator.pop(ctx, values),
            child: const Text('确认'),
          ),
        ],
      ),
    ),
  );
}

Future<void> resetPassword(BuildContext context, CommunityApi api) async {
  final data = await accountFields(
    context,
    '找回账户',
    ['用户名', '一次性恢复码', '新密码（至少 8 位）'],
    showUsername: true,
    notice: '重设后需要用新密码重新登录所有设备。',
  );
  if (data == null) return;
  await api.request('POST', '/community/account/reset', {
    'username': data[0],
    'code': data[1].trim(),
    'password': data[2],
  });
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('密码已更新，请重新登录')));
  }
}

class AccountPage extends StatefulWidget {
  const AccountPage(this.model, {super.key});
  final CommunityController model;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool busy = false;
  String status = '';
  CommunityApi get api => widget.model.api;
  Future<void> run(Future<void> Function() task) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = '';
    });
    try {
      await task();
    } catch (e) {
      status = e.toString();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> issue() async {
    final values = await accountFields(context, '生成恢复码', [
      '当前密码',
    ], notice: '请将恢复码保存在自己的密码管理器中。生成新码后旧码立即失效。');
    if (values == null) return;
    final result = await api.request(
      'POST',
      '/community/account/recovery-code',
      {'password': values.first},
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存一次性恢复码'),
        content: SelectableText(result['code']),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('已保存'),
          ),
        ],
      ),
    );
  }

  Future<void> backup() async {
    if (!await confirmAction(
      context,
      '备份到当前账户？',
      '将本机的角色、文字记录与记忆存到当前社区服务，替换上次备份。原始录音不参与备份。',
      '开始备份',
    )) {
      return;
    }
    final current = api;
    final data = jsonDecode(
      await widget.model.database.exportOwnerJson(current.owner!),
    ) as Json;
    await current.request('PUT', '/community/account/backup', data);
    status = '备份成功';
  }

  Future<void> restore() async {
    final current = api;
    final result = await current.request('GET', '/community/account/backup');
    final data = result['snapshot'] as Json;
    final date = DateTime.fromMillisecondsSinceEpoch(
      (result['created'] as int) * 1000,
    ).toLocal();
    if (!mounted ||
        !await confirmAction(
          context,
          '恢复这份备份？',
          '$date 的备份有 ${(data['characters'] as List).length} 个角色、${(data['raw_events'] as List).length} 条记录。恢复将替换本机当前账户的记录。',
          '确认恢复',
        )) {
      return;
    }
    await widget.model.database.restoreOwnerJson(current.owner!, data);
    await widget.model.refreshLibrary(reloadHome: true);
    status = '恢复成功';
  }

  Future<void> erase() async {
    final values = await accountFields(
      context,
      '永久注销账户',
      ['当前密码'],
      notice:
          '将删除账户、角色库、聊天录音、记忆、备份、帖子、评论及本机账户记录，并退出所有在线会话。其他人此前导入的公开角色副本仍归导入者。',
    );
    if (values == null ||
        !mounted ||
        !await confirmAction(context, '确认永久注销？', '此操作无法撤回。', '永久注销')) {
      return;
    }
    final current = api;
    await current.request('DELETE', '/community/account', {
      'password': values.first,
    });
    await widget.model.database.clearOwner(current.owner!);
    await widget.model.expired(current);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('账户与备份')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (status.isNotEmpty) Text(status),
        for (final item in [
          ('生成恢复码', issue),
          ('备份本机数据', backup),
          ('从账户恢复', restore),
          ('注销账户', erase),
        ])
          ListTile(
            title: Text(item.$1),
            onTap: busy ? null : () => run(item.$2),
          ),
      ],
    ),
  );
}
