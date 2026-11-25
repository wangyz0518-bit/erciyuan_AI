import 'package:material_ui/material_ui.dart';

import 'community_api.dart';
import 'role_portrait.dart';

enum LibraryAction {
  assets('素材', Icons.palette_outlined),
  memory('记忆', Icons.bookmark_outline),
  edit('编辑', Icons.edit_outlined),
  share('分享', Icons.ios_share);

  const LibraryAction(this.label, this.icon);
  final String label;
  final IconData icon;
}

class LibraryRoleCard extends StatelessWidget {
  const LibraryRoleCard({
    super.key,
    required this.card,
    required this.onChat,
    required this.onManage,
  });
  final Json card;
  final VoidCallback? onChat;
  final ValueChanged<LibraryAction>? onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 86,
                height: 116,
                child: RoleArtwork(card['avatar'], portrait: card['portrait']),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          card['name'],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      PopupMenuButton<LibraryAction>(
                        tooltip: '管理${card['name']}',
                        enabled: onManage != null,
                        onSelected: onManage,
                        itemBuilder: (_) => [
                          for (final action in LibraryAction.values)
                            PopupMenuItem(
                              value: action,
                              child: Row(
                                children: [
                                  Icon(action.icon, size: 20),
                                  const SizedBox(width: 12),
                                  Text(action.label),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  if ((card['description'] as String).isNotEmpty)
                    Text(
                      card['description'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: onChat,
                    icon: const Icon(Icons.chat_bubble_outline, size: 17),
                    label: const Text('聊天'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CommunityPostTile extends StatelessWidget {
  const CommunityPostTile({super.key, required this.item, required this.onTap});
  final Json item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = item['card'] as Json?;
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    return Card(
      child: InkWell(
        key: ValueKey("community-post-${item['id']}"),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (card != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 68,
                    height: 86,
                    child: RoleArtwork(
                      card['avatar'],
                      portrait: card['portrait'],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card == null
                          ? item['username']
                          : '角色分享 · ${item['username']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: card == null
                            ? color.onSurfaceVariant
                            : color.primary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      card?['name'] ?? item['body'],
                      maxLines: card == null ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: card == null
                          ? theme.textTheme.bodyLarge
                          : theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                    ),
                    if (card != null &&
                        (item['body'] as String).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item['body'],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: color.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: color.onSurfaceVariant,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileSection extends StatelessWidget {
  const ProfileSection(this.title, {super.key, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
        Card(child: Column(children: children)),
      ],
    ),
  );
}
