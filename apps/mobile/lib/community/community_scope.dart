import 'package:flutter/widgets.dart';

enum AppSection {
  companion('陪伴'),
  roles('角色'),
  community('社区'),
  profile('我的');

  const AppSection(this.label);
  final String label;
}

typedef OpenSection = void Function(
  AppSection section, {
  String? share,
  int? postId,
});

/// Optional in component tests and in the standalone web preview.
class CommunityScope extends InheritedWidget {
  const CommunityScope({
    super.key,
    required this.open,
    required this.section,
    required this.username,
    required super.child,
  });
  final OpenSection open;
  final AppSection section;
  final String? username;
  static CommunityScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CommunityScope>();
  @override
  bool updateShouldNotify(CommunityScope oldWidget) =>
      section != oldWidget.section ||
      username != oldWidget.username ||
      open != oldWidget.open;
}
