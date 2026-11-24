import 'package:flutter/widgets.dart';

/// Optional in component tests and in the standalone web preview.
class CommunityScope extends InheritedWidget {
  const CommunityScope({
    super.key,
    required this.open,
    required this.username,
    required super.child,
  });
  final VoidCallback open;
  final String? username;
  static CommunityScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CommunityScope>();
  @override
  bool updateShouldNotify(CommunityScope oldWidget) =>
      username != oldWidget.username || open != oldWidget.open;
}
