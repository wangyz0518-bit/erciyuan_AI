import 'package:material_ui/material_ui.dart';

import 'community_api.dart';
import 'community_controller.dart';
import 'community_forms.dart';

class SupportPage extends StatefulWidget {
  const SupportPage(this.model, {super.key});
  final CommunityController model;

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  late final CommunityApi api = widget.model.api;
  List<Json> tickets = [];
  int? before;
  bool busy = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    run(() => load());
  }

  Future<void> run(Future<void> Function() task) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await task();
    } on CommunityError catch (e) {
      if (!mounted) return;
      if (e.code == 'LOGIN_REQUIRED') {
        await widget.model.expired(api);
        if (mounted) Navigator.pop(context);
      } else {
        setState(() => error = e.toString());
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load({bool append = false}) async {
    final data = await api.request(
      'GET',
      '/community/tickets${append ? '?before=$before' : ''}',
    );
    final items = (data['items'] as List).cast<Json>();
    if (!mounted) return;
    setState(() {
      tickets = append ? [...tickets, ...items] : items;
      before = data['next_before'];
    });
  }

  Future<void> submit() async {
    final message = await communityText(
      context,
      '提交反馈',
      '问题或建议',
      limit: 1000,
      action: '提交',
    );
    if (message == null || !mounted) return;
    await api.request('POST', '/community/feedback', {'message': message});
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('反馈已提交')));
    await load();
  }

  Widget ticketCard(Json row) {
    const kinds = {'feedback': '用户反馈', 'post': '帖子举报', 'comment': '评论举报'};
    const results = {'reply': '已回复', 'hide': '已下架', 'dismiss': '已驳回'};
    final kind = kinds[row['kind']] ?? '处理记录';
    final status = results[row['action']] ?? '待处理';
    final reply = row['reply'];
    return Card(
      child: ListTile(
        title: Text('#${row['id']} $kind · $status'),
        subtitle: Text(
          [row['message'], if (reply != null) '运营回复：$reply'].join('\n'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('反馈与处理记录'),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: busy ? null : () => run(() => load()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: busy ? null : () => run(submit),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('提交反馈'),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error.isNotEmpty) Text(error),
          if (!busy && error.isEmpty && tickets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('暂无反馈或举报记录。'),
            ),
          for (final row in tickets) ticketCard(row),
          if (before != null)
            TextButton(
              onPressed: busy ? null : () => run(() => load(append: true)),
              child: const Text('更多记录'),
            ),
        ],
      ),
    ),
  );
}
