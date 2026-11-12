import 'package:material_ui/material_ui.dart';

import '../chat_controller.dart';
import '../data.dart';

class ChatMessage extends StatelessWidget {
  const ChatMessage({
    super.key,
    required this.message,
    required this.chat,
    this.lines,
  });
  final Message message;
  final ChatController chat;
  final int? lines;
  @override
  Widget build(BuildContext context) {
    final mine = message.author == 'user';
    final status = switch (message.status) {
      'pending' => '回复中…',
      'failed' => '回复失败',
      'cancelled' => '已取消',
      'interrupted' => '上次回复已中断',
      _ => '',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            mine ? '我' : chat.character.name,
            style: const TextStyle(
              color: Color(0xFFF6BC9F),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (message.text.isNotEmpty)
            Text(
              message.text,
              maxLines: lines,
              overflow: lines == null ? null : TextOverflow.ellipsis,
              textAlign: mine ? TextAlign.right : TextAlign.left,
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          if (status.isNotEmpty)
            Text(
              status,
              style: const TextStyle(fontSize: 12, color: Color(0xFFE8C5B8)),
            ),
          if (['failed', 'cancelled', 'interrupted'].contains(message.status))
            TextButton(
              key: ValueKey('retry-${message.id}'),
              onPressed: chat.busy || chat.switching
                  ? null
                  : () => chat.retry(message),
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }
}

class ChatHistory extends StatefulWidget {
  const ChatHistory({super.key, required this.chat, required this.close});
  final ChatController chat;
  final VoidCallback close;
  @override
  State<ChatHistory> createState() => _ChatHistoryState();
}

class _ChatHistoryState extends State<ChatHistory> {
  final scroll = ScrollController();
  bool initial = true;
  @override
  void initState() {
    super.initState();
    widget.chat.addListener(update);
  }

  void update() {
    final follow = !scroll.hasClients || scroll.position.extentAfter < 80;
    if (mounted) setState(() {});
    if (follow) bottom();
  }

  void bottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && scroll.hasClients) {
      scroll.jumpTo(scroll.position.maxScrollExtent);
    }
  });
  @override
  void dispose() {
    widget.chat.removeListener(update);
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (initial) {
      initial = false;
      bottom();
    }
    return SafeArea(
      top: false,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 30, height: 3, color: const Color(0xFFD8BDB5)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Expanded(
                  child: Text('聊天记录', style: TextStyle(fontSize: 20)),
                ),
                TextButton(
                  key: const Key('close-history'),
                  onPressed: widget.close,
                  child: const Text('收起'),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.chat.messages.isEmpty
                ? const Center(child: Text('还没有聊天记录'))
                : ListView.builder(
                    key: const Key('message-list'),
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: widget.chat.messages.length,
                    itemBuilder: (_, i) => ChatMessage(
                      key: ValueKey('message-${widget.chat.messages[i].id}'),
                      message: widget.chat.messages[i],
                      chat: widget.chat,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
