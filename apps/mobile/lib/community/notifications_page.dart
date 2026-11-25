import 'package:material_ui/material_ui.dart';

import 'community_api.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage(this.api, {super.key});
  final CommunityApi api;
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Json> items = [];
  bool busy = false, more = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool append = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final suffix = append ? '?before=${items.last['id']}' : '';
      final batch = await widget.api.items('/community/notifications$suffix');
      items = [if (append) ...items, ...batch];
      more = batch.length == 30;
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(Json notice) async {
    setState(() => busy = true);
    try {
      final detail = await widget.api.request(
        'POST',
        "/community/notifications/${notice['id']}/open",
      );
      if (mounted) Navigator.pop(context, detail);
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('回复通知'),
      actions: [
        IconButton(
          tooltip: '刷新通知',
          onPressed: busy ? null : () => load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error.isNotEmpty) Text(error),
        if (!busy && error.isEmpty && items.isEmpty)
          const ListTile(title: Text('暂无回复通知')),
        for (final item in items)
          ListTile(
            leading: Icon(
              item['seen'] == 0
                  ? Icons.mark_email_unread_outlined
                  : Icons.drafts_outlined,
            ),
            title: Text(item['body']),
            subtitle: Text(
              "${item['username']} · ${item['parent'] == null ? '评论了帖子' : '回复了评论'}",
            ),
            onTap: busy ? null : () => open(item),
          ),
        if (more)
          TextButton(
            onPressed: busy ? null : () => load(append: true),
            child: const Text('更早的通知'),
          ),
      ],
    ),
  );
}
