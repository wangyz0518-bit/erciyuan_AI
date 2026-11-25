import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../bootstrap.dart';
import '../features/characters/presentation/data_management_page.dart';
import 'community_scope.dart';
import 'community_api.dart';
import 'community_controller.dart';
import 'community_forms.dart';
import 'support_page.dart';
import 'account_page.dart';
import 'role_tools_page.dart';
import 'notifications_page.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage(
    this.model, {
    super.key,
    required this.section,
    this.share,
    this.postId,
  });
  final AppSection section;
  final int? postId;
  final CommunityController model;
  final String? share;
  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  CommunityController get model => widget.model;
  CommunityApi get api => model.api;
  String error = '';
  final searchField = TextEditingController();
  String query = '';
  bool discovery = false;
  Json? focusedReply;
  List<Json> rows = [], comments = [];
  bool busy = false, more = false, guestHistory = false;
  Json? post;
  String? pendingShare;
  int? pendingPost;

  @override
  void initState() {
    super.initState();
    pendingShare = widget.share;
    pendingPost = widget.postId;
    run(load);
  }

  @override
  void dispose() {
    searchField.dispose();
    super.dispose();
  }

  Future<List<Json>> feed({int? before}) {
    final params = {
      if (query.isNotEmpty) 'q': query,
      if (discovery) 'roles_only': 'true',
      if (before != null) 'before': before.toString(),
    };
    return api.items(
      Uri(
        path: '/community/posts',
        queryParameters: params.isEmpty ? null : params,
      ).toString(),
    );
  }

  Future<void> search() async {
    FocusManager.instance.primaryFocus?.unfocus();
    query = searchField.text.trim();
    rows = [];
    more = false;
    await load();
  }

  Future<void> run(Future<void> Function() task) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    final previous = api;
    try {
      await task();
    } on CommunityError catch (e) {
      if (mounted &&
          e.code == 'POST_NOT_FOUND' &&
          widget.section == AppSection.community &&
          previous == api) {
        // A share may be withdrawn while its detail or a search result is open.
        post = null;
        pendingShare = null;
        pendingPost = null;
        rows = [];
        comments = [];
        more = false;
        try {
          await load();
        } on CommunityError {
          // The feed can be retried independently with the refresh button.
        }
      }
      if (e.code == 'LOGIN_REQUIRED' && previous.signedIn) {
        await model.expired(previous);
        if (mounted && widget.section == AppSection.roles) rows = [];
      }
      if (mounted) setState(() => error = e.toString());
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() async {
    if (api.origin == null) return;
    if (pendingShare != null) {
      final found = await api.request('GET', '/community/shares/$pendingShare');
      pendingShare = null;
      await showPost(found);
    } else if (pendingPost != null) {
      await showPost(await api.request('GET', '/community/posts/$pendingPost'));
      pendingPost = null;
    } else if (post != null) {
      await showPost(
        await api.request('GET', '/community/posts/${post!['id']}'),
      );
    } else if (widget.section == AppSection.roles) {
      if (api.signedIn) {
        await model.refreshLibrary();
        rows = await api.items('/community/characters');
      } else {
        rows = [];
      }
      more = false;
    } else if (widget.section == AppSection.profile) {
      guestHistory = await model.database.hasGuestHistory(localOwnerId);
    } else {
      rows = await feed();
      more = rows.length == 30;
    }
  }

  Future<void> showPost(Json item, {Json? focus}) async {
    final replies = await api.items('/community/posts/${item['id']}/comments');
    post = item;
    focusedReply = focus;
    comments = replies;
    more = replies.length == 50;
  }

  Future<void> pageMore() async {
    if (post != null) {
      final next = await api.items(
        '/community/posts/${post!['id']}/comments?after=${comments.last['id']}',
      );
      comments = [...comments, ...next];
      more = next.length == 50;
    } else {
      final next = await feed(before: rows.last['id'] as int);
      rows = [...rows, ...next];
      more = next.length == 30;
    }
  }

  Future<bool> login() async {
    if (api.signedIn) return true;
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => LoginDialog(model.authenticate),
        ) ??
        false;
  }

  Future<void> closePost() async {
    post = null;
    pendingShare = null;
    pendingPost = null;
    await load();
  }

  Future<void> configure() async {
    final value = await communityText(
      context,
      '连接社区',
      '社区服务地址',
      limit: 240,
      lines: 1,
    );
    if (value != null) {
      await model.configure(value);
      await load();
    }
  }

  Future<void> openLink() async {
    final link = await communityText(
      context,
      '打开角色链接',
      '粘贴分享链接',
      limit: 500,
      lines: 2,
      action: '预览',
    );
    if (link != null) {
      pendingShare = api.shareId(link);
      await load();
    }
  }

  Future<void> enterChat(Json card) async {
    await model.choose(card);
    if (mounted) CommunityScope.of(context)!.open(AppSection.companion);
  }

  Future<void> importCard() async {
    if (!await login() || !mounted) return;
    final card = await api.request(
      'POST',
      '/community/shares/${post!['share']}/import',
    );
    if (mounted) await enterChat(card);
  }

  Future<void> edit([Json? card]) async {
    if (!await login() || !mounted) return;
    final draft = await Navigator.push<Json>(
      context,
      MaterialPageRoute(builder: (_) => CardEditor(card)),
    );
    if (draft == null) return;
    await api.request(
      card == null ? 'POST' : 'PUT',
      '/community/characters${card == null ? '' : '/${card['id']}'}',
      draft,
    );
    await model.refreshLibrary(reloadHome: true);
    rows = await api.items('/community/characters');
  }

  Future<void> publish([Json? card]) async {
    if (!await login() || !mounted) return;
    bool sharePortrait = false;
    if (card != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('预览公开角色卡'),
          content: StatefulBuilder(
            builder: (context, update) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RoleCard({...card, if (!sharePortrait) 'portrait': null}),
                  if (card['portrait'] != null)
                    CheckboxListTile(
                      title: const Text('随角色分享自定义形象'),
                      value: sharePortrait,
                      onChanged: (v) => update(() => sharePortrait = v == true),
                    ),
                  const Text('公开角色卡包含人设与公开音色。私人绑定和记忆仅自己可见。'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('返回'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('继续发布'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final body = await communityText(
      context,
      card == null ? '发布讨论' : '分享角色',
      '想对大家说什么？',
      limit: 3000,
      action: '发布',
    );
    if (body == null) return;
    final item = await api.request('POST', '/community/posts', {
      'body': body,
      if (card != null) 'character_id': card['id'],
      if (sharePortrait) 'share_portrait': true,
    });
    if (!mounted) return;
    if (widget.section == AppSection.roles) {
      CommunityScope.of(context)!
          .open(AppSection.community, postId: item['id'] as int);
    } else {
      await showPost(item);
    }
  }

  Future<void> comment([Json? parent]) async {
    if (!await login() || !mounted) return;
    final body = await communityText(
      context,
      parent == null ? '发表评论' : '回复 ${parent['username']}',
      '内容',
      action: '发送',
    );
    if (body == null) return;
    await api.request('POST', '/community/posts/${post!['id']}/comments', {
      'body': body,
      if (parent != null) 'parent_id': parent['id'],
    });
    await load();
  }

  Future<void> remove([Json? reply]) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(reply == null ? '删除这篇帖子？' : '删除这条评论？'),
        content: reply == null && post!['share'] != null
            ? const Text('分享链接将失效。已经导入的角色会保留。')
            : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await api.request(
      'DELETE',
      '/community/posts/${post!['id']}${reply == null ? '' : '/comments/${reply['id']}'}',
    );
    if (reply == null) post = null;
    await load();
  }

  Future<void> report([Json? comment]) async {
    if (!await login() || !mounted) return;
    final reason = await communityText(
      context,
      comment == null ? '举报帖子' : '举报评论',
      '举报原因',
      limit: 1000,
      action: '提交举报',
    );
    if (reason == null || !mounted) return;
    await api.request('POST', '/community/reports', {
      'post_id': post!['id'],
      if (comment != null) 'comment_id': comment['id'],
      'message': reason,
    });
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('举报已提交，可在「我的」查看处理记录')));
    }
  }

  Future<void> openSupport() async {
    if (!await login() || !mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => SupportPage(model)));
  }

  Future<void> migrate() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('迁入本机访客记录？'),
        content: Text('有聊天记录的访客角色及其本机记忆将移到「${api.username}」的角色库，成为独立角色。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('保留在访客中'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认迁入'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await model.migrateGuest();
      await load();
    }
  }

  Widget button(String text, Future<void> Function() task) => OutlinedButton(
    onPressed: busy ? null : () => run(task),
    child: Text(text),
  );
  List<Widget> detail() {
    final item = post!;
    return [
      Text(item['username'], style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      SelectableText(item['body']),
      if (item['card'] != null) ...[
        RoleCard(item['card']),
        FilledButton(
          onPressed: busy ? null : () => run(importCard),
          child: const Text('加入我的角色 / 开始聊天'),
        ),
        button('复制分享链接', () async {
          await Clipboard.setData(
            ClipboardData(
              text: api.origin!.resolve('/s/${item['share']}').toString(),
            ),
          );
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('分享链接已复制')));
          }
        }),
      ],
      if (item['username'] == api.username)
        button('删除帖子', () => remove())
      else
        button('举报帖子', () => report()),
      const Divider(),
      Row(
        children: [
          Expanded(
            child: Text('评论', style: Theme.of(context).textTheme.titleMedium),
          ),
          button('写评论', () => comment()),
        ],
      ),
      if (focusedReply case final notice?)
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: Text(notice['body']),
          subtitle: Text(
            "通知定位 · #${notice['comment']} · ${notice['username']}",
          ),
        ),
      if (comments.isEmpty) const Text('还没有评论。'),
      for (final row in comments)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(row['body'] ?? '评论已删除'),
          subtitle: Text(
            '#${row['id']} · ${row['username']}${row['parent'] == null ? '' : ' · 回复 #${row['parent']}'}',
          ),
          trailing: row['body'] == null
              ? null
              : Wrap(
                  children: [
                    IconButton(
                      tooltip: '回复',
                      onPressed: busy ? null : () => run(() => comment(row)),
                      icon: const Icon(Icons.reply),
                    ),
                    if (row['username'] == api.username)
                      IconButton(
                        tooltip: '删除评论',
                        onPressed: busy ? null : () => run(() => remove(row)),
                        icon: const Icon(Icons.delete_outline),
                      )
                    else
                      IconButton(
                        tooltip: '举报评论',
                        onPressed: busy ? null : () => run(() => report(row)),
                        icon: const Icon(Icons.flag_outlined),
                      ),
                  ],
                ),
        ),
      if (more) button('更多评论', pageMore),
    ];
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      if (post != null && !busy) {
        run(closePost);
      } else {
        CommunityScope.of(context)!.open(AppSection.companion);
      }
    },
    child: Scaffold(
      appBar: AppBar(
        leading: post == null
            ? null
            : BackButton(onPressed: busy ? null : () => run(closePost)),
        title: Text(post == null ? widget.section.label : '帖子详情'),
        actions: [
          IconButton(
            onPressed: busy ? null : () => run(load),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
          if (widget.section == AppSection.community && api.origin != null)
            IconButton(
              onPressed: busy ? null : () => run(openLink),
              icon: const Icon(Icons.link),
              tooltip: '打开分享链接',
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (busy) const LinearProgressIndicator(),
            if (error.isNotEmpty)
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (widget.section == AppSection.profile) ...[
              ListTile(
                title: Text(api.username ?? '访客'),
                subtitle: api.origin == null ? null : Text(api.origin!.host),
              ),
              if (api.origin == null)
                button('连接社区服务', configure)
              else if (api.signedIn) ...[
                button('账户与备份', () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => AccountPage(model)),
                  );
                }),
                if (guestHistory) button('迁入本机访客记录', migrate),
                button('退出账户', () async {
                  await model.logout();
                  await load();
                }),
              ] else
                button('登录 / 注册', () async {
                  if (await login()) await load();
                }),
              if (api.origin != null && !api.signedIn)
                button('找回账户', () => resetPassword(context, api)),
              if (api.origin != null)
                ListTile(
                  leading: const Icon(Icons.feedback_outlined),
                  title: const Text('反馈与处理记录'),
                  onTap: busy ? null : () => run(openSupport),
                ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('本机数据管理'),
                onTap: busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DataManagementPage(
                            database: model.database,
                            ownerId: api.owner ?? localOwnerId,
                          ),
                        ),
                      ),
              ),
            ] else if (api.origin == null)
              button('连接社区服务', configure)
            else if (post != null)
              ...detail()
            else if (widget.section == AppSection.roles) ...[
              if (!api.signedIn)
                button('登录后查看角色库', () async {
                  if (await login()) await load();
                })
              else ...[
                button('创建角色', () => edit()),
                for (final card in rows)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card['name'],
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(card['description']),
                          Wrap(
                            spacing: 6,
                            children: [
                              button('聊天', () => enterChat(card)),
                              button('素材', () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => RoleAssetsPage(api, card),
                                  ),
                                );
                                await load();
                              }),
                              button('记忆', () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        MemoryPage(model, card['id']),
                                  ),
                                );
                              }),
                              button('编辑', () => edit(card)),
                              button('分享', () => publish(card)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ] else ...[
              TextField(
                key: const ValueKey('community-search'),
                controller: searchField,
                readOnly: busy,
                textInputAction: TextInputAction.search,
                inputFormatters: [LengthLimitingTextInputFormatter(100)],
                onSubmitted: (_) => run(search),
                decoration: InputDecoration(
                  labelText: '搜索帖子或角色名',
                  suffixIcon: IconButton(
                    tooltip: '搜索',
                    onPressed: busy ? null : () => run(search),
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
              if (query.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            searchField.clear();
                            await search();
                          }),
                    icon: const Icon(Icons.close),
                    label: Text(
                      '清除搜索「$query」',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              Wrap(
                spacing: 8,
                children: [
                  button(discovery ? '返回全部帖子' : '发现角色', () async {
                    discovery = !discovery;
                    rows = [];
                    more = false;
                    query = '';
                    searchField.clear();
                    await load();
                  }),
                  if (api.signedIn)
                    button('回复通知', () async {
                      final notice = await Navigator.of(context).push<Json>(
                        MaterialPageRoute(
                          builder: (_) => NotificationsPage(api),
                        ),
                      );
                      if (notice != null) {
                        await showPost(
                          await api.request(
                            'GET',
                            "/community/posts/${notice['post']}",
                          ),
                          focus: notice,
                        );
                      }
                    }),
                  button('发布讨论', () => publish()),
                ],
              ),
              if (rows.isEmpty && !busy && error.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    query.isEmpty
                        ? '还没有帖子。发布第一篇讨论，或到「角色」分享角色。'
                        : '没有找到匹配的帖子或角色。',
                  ),
                ),
              for (final item in rows)
                Card(
                  child: ListTile(
                    key: ValueKey("community-post-${item['id']}"),
                    leading: item['card'] == null
                        ? null
                        : RolePortrait(
                            item['card']['avatar'],
                            portrait: item['card']['portrait'],
                          ),
                    title: Text(
                      item['card']?['name'] ?? item['body'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        '${item['username']}${item['share'] == null ? '' : ' · 角色分享'}',
                        if (query.isNotEmpty && item['card'] != null)
                          item['body'],
                      ].join('\n'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: busy ? null : () => run(() => showPost(item)),
                  ),
                ),
              if (more) button('更早的帖子', pageMore),
            ],
          ],
        ),
      ),
    ),
  );
}
