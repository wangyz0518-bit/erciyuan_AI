import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:material_ui/material_ui.dart';

import '../app/companion_app.dart';
import '../bootstrap.dart';
import '../immersive/immersive_home.dart';
import '../immersive/model_gateway.dart';
import 'community_api.dart';
import 'community_controller.dart';
import 'community_page.dart';
import 'community_scope.dart';

class CommunityHost extends StatefulWidget {
  const CommunityHost(this.controller, {super.key});
  final CommunityController controller;
  @override
  State<CommunityHost> createState() => _CommunityHostState();
}

class _CommunityHostState extends State<CommunityHost> {
  final navigator = GlobalKey<NavigatorState>();
  late Future<CompanionApp> home;
  StreamSubscription<Uri>? links;
  CommunityController get model => widget.controller;
  @override
  void initState() {
    super.initState();
    model.addListener(reload);
    home = buildHome();
    links = AppLinks().uriLinkStream.listen((uri) {
      try {
        final id = model.api.shareId(uri.toString());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) open(share: id);
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      } on CommunityError {
        /* Ignore unrelated platform URLs. */
      }
    });
  }

  Future<CompanionApp> buildHome() {
    final current = model.api;
    final voice = current.signedIn
        ? ModelGateway(
            current.origin!.origin,
            current.token!,
            useV3: true,
            accountSession: true,
          )
        : model.legacyGuest
        ? ModelGateway.configured()
        : null;
    const oldText = String.fromEnvironment('PERSON_GATEWAY_URL');
    final useLegacy = model.legacyGuest && oldText.isNotEmpty;
    return bootstrapCompanionApp(
      ownerId: current.owner ?? localOwnerId,
      database: model.database,
      embedded: true,
      selectedId: model.selectedId,
      homeBuilder: voice?.useV3 == true
          ? (selection, db, gateway) =>
                ImmersiveHome(selection, db, gateway, voiceGateway: voice)
          : null,
      gatewayUri: useLegacy ? Uri.parse(oldText) : null,
      gatewayToken: useLegacy
          ? const String.fromEnvironment('PERSON_GATEWAY_DEV_TOKEN')
          : null,
    );
  }

  void reload() {
    if (mounted) {
      setState(() {
        home = buildHome();
      });
    }
  }

  void open({String? share}) {
    navigator.currentState?.popUntil((route) => route.isFirst);
    navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityPage(model, share: share),
      ),
    );
  }

  @override
  void dispose() {
    model.removeListener(reload);
    unawaited(links?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CommunityScope(
    open: open,
    username: model.api.username,
    child: MaterialApp(
      navigatorKey: navigator,
      title: '二次元 AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7969C3),
          brightness: Brightness.dark,
        ),
      ),
      home: FutureBuilder<CompanionApp>(
        future: home,
        builder: (_, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: reload,
                  child: const Text('读取人物失败，点此重试'),
                ),
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return KeyedSubtree(
            key: ValueKey(model.revision),
            child: snapshot.requireData,
          );
        },
      ),
    ),
  );
}
