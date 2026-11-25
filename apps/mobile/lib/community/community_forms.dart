import 'package:material_ui/material_ui.dart';

import 'community_api.dart';
import 'role_portrait.dart';

export 'role_portrait.dart' show RolePortrait;

Future<String?> communityText(
  BuildContext context,
  String title,
  String label, {
  int limit = 1000,
  int lines = 4,
  String action = '确定',
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextForm(title, label, limit, lines, action, initial),
);

class _TextForm extends StatefulWidget {
  const _TextForm(
    this.title,
    this.label,
    this.limit,
    this.lines,
    this.action,
    this.initial,
  );
  final String title, label, action, initial;
  final int limit, lines;
  @override
  State<_TextForm> createState() => _TextFormState();
}

class _TextFormState extends State<_TextForm> {
  late String value = widget.initial.trim();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextFormField(
      initialValue: widget.initial,
      autofocus: true,
      maxLength: widget.limit,
      maxLines: widget.lines,
      decoration: InputDecoration(labelText: widget.label),
      onChanged: (s) => setState(() => value = s.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: value.isEmpty || value.length > widget.limit
            ? null
            : () => Navigator.pop(context, value),
        child: Text(widget.action),
      ),
    ],
  );
}

class LoginDialog extends StatefulWidget {
  const LoginDialog(this.login, {super.key});
  final Future<void> Function(String, String, bool) login;
  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  String name = '', password = '', error = '';
  bool register = false, busy = false;
  Future<void> submit() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.login(name.trim(), password, register);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(register ? '注册账户' : '登录账户'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              maxLength: 32,
              decoration: const InputDecoration(labelText: '用户名'),
              onChanged: (s) => setState(() => name = s),
            ),
            TextField(
              maxLength: 128,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '密码（至少 8 位）'),
              onChanged: (s) => setState(() => password = s),
            ),
            if (error.isNotEmpty) Text(error),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy
              ? null
              : () => setState(() {
                  register = !register;
                  error = '';
                }),
          child: Text(register ? '已有账户，去登录' : '创建新账户'),
        ),
        FilledButton(
          onPressed: busy || name.trim().length < 2 || password.length < 8
              ? null
              : submit,
          child: Text(
            busy
                ? '请稍候'
                : register
                ? '注册'
                : '登录',
          ),
        ),
      ],
    ),
  );
}

class CardEditor extends StatefulWidget {
  const CardEditor(this.card, {super.key});
  final Json? card;
  @override
  State<CardEditor> createState() => _CardEditorState();
}

class _CardEditorState extends State<CardEditor> {
  late final card =
      <String, dynamic>{
          'name': '',
          'description': '',
          'persona': '',
          'avatar': 'star',
          'voice': 'default',
          ...?widget.card,
        }
        ..remove('id')
        ..remove('portrait');
  final form = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.card == null ? '创建角色' : '编辑角色卡')),
    body: SafeArea(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final field in [
              ('name', '角色名', 48),
              ('description', '简介', 240),
              ('persona', '人设和说话习惯', 2000),
            ])
              TextFormField(
                initialValue: card[field.$1],
                maxLength: field.$3,
                maxLines: field.$1 == 'name' ? 1 : 3,
                decoration: InputDecoration(labelText: field.$2),
                validator: (s) =>
                    s == null || s.trim().isEmpty ? '请填写${field.$2}' : null,
                onChanged: (s) => card[field.$1] = s.trim(),
              ),
            DropdownButtonFormField<String>(
              initialValue: card['avatar'],
              decoration: const InputDecoration(labelText: '公开形象'),
              items: const [
                DropdownMenuItem(value: 'star', child: Text('小星')),
                DropdownMenuItem(value: 'moon', child: Text('小月')),
                DropdownMenuItem(value: 'sprout', child: Text('小芽')),
              ],
              onChanged: (s) => card['avatar'] = s,
            ),
            DropdownButtonFormField<String>(
              initialValue: card['voice'],
              decoration: const InputDecoration(labelText: '公开预设音色'),
              items: const [
                DropdownMenuItem(value: 'default', child: Text('默认')),
                DropdownMenuItem(value: 'bright', child: Text('明快')),
              ],
              onChanged: (s) => card['voice'] = s,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(context, card);
              },
              child: const Text('保存角色卡'),
            ),
          ],
        ),
      ),
    ),
  );
}

class RoleCard extends StatelessWidget {
  const RoleCard(this.card, {super.key});
  final Json card;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RolePortrait(card['avatar'], portrait: card['portrait']),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  card['name'],
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          Text(card['description']),
          const Divider(),
          Text(card['persona']),
          const SizedBox(height: 8),
          Text(
            '形象 · ${{'star': '小星', 'moon': '小月', 'sprout': '小芽'}[card['avatar']]}     音色 · ${card['voice'] == 'bright' ? '明快' : '默认'}',
          ),
        ],
      ),
    ),
  );
}
