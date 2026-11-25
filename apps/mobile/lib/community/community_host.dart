import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:material_ui/material_ui.dart';

import '../app/companion_app.dart';
import '../bootstrap.dart';
import '../features/characters/presentation/character_home_page.dart';
import '../features/characters/presentation/continuous_chat_page.dart';
import '../immersive/immersive_home.dart';
import '../immersive/model_gateway.dart';
import 'community_api.dart';
import 'community_controller.dart';
import 'community_page.dart';
import 'role_tools_page.dart';
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
  AppSection section = AppSection.companion;
  String? shareId;
  int? postId;
  int pageVersion = 0;
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
          if (mounted) open(AppSection.community, share: id);
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
      homeBuilder: (selection, db, gateway) => Builder(
        builder: (context) {
          final navigation = CommunityScope.of(context)!;
          if (navigation.section == AppSection.roles && !current.signedIn) {
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) open(AppSection.companion);
              },
              child: CharacterHomePage(
                controller: selection,
                database: db,
                gateway: gateway,
                onOpen: () => open(AppSection.companion),
              ),
            );
          }
          // Leaving the companion disposes its native audio and avatar resources.
          // Its selection and role-scoped drafts live in the parent CompanionApp.
          if (navigation.section != AppSection.companion) {
            return const SizedBox.shrink();
          }
          if (voice?.useV3 == true) {
            return ImmersiveHome(selection, db, gateway, voiceGateway: voice);
          }
          return AnimatedBuilder(
            animation: selection,
            builder: (_, _) => ContinuousChatPage(
              key: ValueKey(selection.activeScope),
              selection: selection,
              database: db,
              scope: selection.activeScope,
              gateway: gateway,
              embedded: true,
            ),
          );
        },
      ),
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

  void open(AppSection next, {String? share, int? postId}) {
    FocusManager.instance.primaryFocus?.unfocus();
    navigator.currentState?.popUntil((route) => route.isFirst);
    if (next == section && share == null && postId == null) return;
    setState(() {
      section = next;
      shareId = share;
      this.postId = postId;
      pageVersion++;
    });
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
    section: section,
    username: model.api.username,
    portraitFor: (id) => model.portraits[id],
    openMemory: model.api.signedIn
        ? (context, id) => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => MemoryPage(model, id)))
        : null,
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
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        bottomNavigationBar: NavigationBar(
          height: 64,
          selectedIndex: section.index,
          onDestinationSelected: (index) => open(AppSection.values[index]),
          destinations: [
            for (final entry in AppSection.values)
              NavigationDestination(
                key: ValueKey('nav-${entry.name}'),
                label: entry.label,
                icon: Icon(switch (entry) {
                  AppSection.companion => Icons.chat_bubble_outline,
                  AppSection.roles => Icons.people_outline,
                  AppSection.community => Icons.forum_outlined,
                  AppSection.profile => Icons.person_outline,
                }),
              ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<CompanionApp>(
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
            if (section != AppSection.companion &&
                (section != AppSection.roles || model.api.signedIn))
              CommunityPage(
                model,
                key: ValueKey(pageVersion),
                section: section,
                share: shareId,
                postId: postId,
              ),
          ],
        ),
      ),
    ),
  );
}
