import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../features/characters/application/character_selection_controller.dart';
import '../features/characters/presentation/character_home_page.dart';
import '../features/chat/data/model_gateway_adapter.dart';
import '../features/timeline/data/person_database.dart';

typedef CompanionHomeBuilder = Widget Function(
  CharacterSelectionController,
  PersonDatabase,
  ModelGatewayAdapter?,
);

/// Owns the official local store, single-owner selection, and optional gateway.
class CompanionApp extends StatefulWidget {
  const CompanionApp({
    required this.controller,
    required this.database,
    this.gateway,
    this.homeBuilder,
    this.closeDatabaseOnDispose = true,
    this.embedded = false,
    super.key,
  });

  final CharacterSelectionController controller;
  final PersonDatabase database;
  final ModelGatewayAdapter? gateway;
  final bool closeDatabaseOnDispose;
  final bool embedded;
  final CompanionHomeBuilder? homeBuilder;

  @override
  State<CompanionApp> createState() => _CompanionAppState();
}

class _CompanionAppState extends State<CompanionApp> {
  @override
  void dispose() {
    widget.gateway?.close();
    if (widget.closeDatabaseOnDispose) unawaited(widget.database.close());
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.embedded
      ? _home()
      : MaterialApp(
          title: '二次元 AI',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF7969C3),
              brightness: Brightness.dark,
            ),
          ),
          home: _home(),
        );

  Widget _home() =>
      widget.homeBuilder?.call(
        widget.controller,
        widget.database,
        widget.gateway,
      ) ??
      CharacterHomePage(
        controller: widget.controller,
        database: widget.database,
        gateway: widget.gateway,
      );
}
