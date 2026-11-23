import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../bootstrap.dart';
import '../features/characters/domain/character.dart';
import '../features/timeline/data/person_database.dart';
import 'community_api.dart';

class CommunityController extends ChangeNotifier {
  CommunityController(this.database);
  final PersonDatabase database;
  static const storage = FlutterSecureStorage();
  static const configured = String.fromEnvironment('COMMUNITY_GATEWAY_URL');
  static const legacy = String.fromEnvironment('MODEL_GATEWAY_URL');
  CommunityApi api = CommunityApi(null);
  String? selectedId;
  bool explicitServer = false;
  int revision = 0;
  bool get legacyGuest =>
      !api.signedIn && !explicitServer && configured.isEmpty;

  Future<void> restore() async {
    final savedOrigin = await storage.read(key: 'community.origin');
    explicitServer = savedOrigin != null || configured.isNotEmpty;
    final endpoint = configured.isNotEmpty ? configured : savedOrigin ?? legacy;
    if (endpoint.isEmpty) return;
    final origin = CommunityApi.parseOrigin(endpoint);
    api = CommunityApi(origin);
    final pending = await storage.read(
      key: 'community.revoke.${origin.origin}',
    );
    final value = await storage.read(key: 'community.session');
    await _revokePending(origin);
    if (value == null) return;
    final saved = jsonDecode(value) as Json;
    if (saved['origin'] != origin.origin) return;
    if (pending != null && saved['token'] == pending) {
      await _clear();
      return;
    }
    api = CommunityApi(
      origin,
      token: saved['token'],
      owner: saved['id'],
      username: saved['username'],
    );
    try {
      await refreshLibrary();
    } on CommunityError catch (e) {
      if (e.code == 'LOGIN_REQUIRED') {
        await _clear();
      } else if (e.code != 'NETWORK') {
        rethrow;
      }
    }
  }

  Future<void> configure(String input) async {
    final next = CommunityApi(CommunityApi.parseOrigin(input));
    await next.items('/community/posts');
    await storage.write(key: 'community.origin', value: next.origin!.origin);
    api = next;
    explicitServer = true;
    _changed();
  }

  Future<void> authenticate(
    String username,
    String password,
    bool register,
  ) async {
    await _revokePending(api.origin!);
    final result = await CommunityApi(api.origin).request(
      'POST',
      register ? '/community/register' : '/community/login',
      {'username': username, 'password': password},
    );
    await storage.write(
      key: 'community.session',
      value: jsonEncode({...result, 'origin': api.origin!.origin}),
    );
    api = CommunityApi(
      api.origin,
      token: result['token'],
      owner: result['id'],
      username: result['username'],
    );
    selectedId = null;
    try {
      await refreshLibrary();
    } finally {
      _changed();
    }
  }

  Future<void> refreshLibrary({bool reloadHome = false}) async {
    final current = api;
    if (!current.signedIn) return;
    var cards = await current.items('/community/characters');
    final existing = {for (final card in cards) card['id']};
    final cached = await database.charactersForOwner(current.owner!);
    final pending = cached
        .where(
          (c) =>
              c.scope.characterId.startsWith('m-') &&
              !existing.contains(c.scope.characterId),
        )
        .toList();
    for (final role in pending) {
      final source = cards.firstWhere(
        (c) => localRole(c['id']) == role.appearance,
        orElse: () => cards.first,
      );
      await current.request(
        'PUT',
        '/community/migrations/${role.scope.characterId}',
        {
          'name': role.name,
          'description': role.description,
          'avatar': source['avatar'],
          'persona': source['persona'],
          'voice': source['voice'],
        },
      );
    }
    if (pending.isNotEmpty) {
      cards = await current.items('/community/characters');
    }
    for (final card in cards) {
      await _cache(current, card);
    }
    if (reloadHome && current == api) _changed();
  }

  Future<void> _cache(CommunityApi current, Json card) =>
      database.syncCharacter(
        Character(
          scope: PersonScope(
            ownerId: current.owner!,
            characterId: localRole(card['id']),
          ),
          name: card['name'],
          description: card['description'],
          avatar: card['avatar'],
        ),
        card['persona'],
      );

  Future<void> choose(Json card) async {
    final current = api;
    await _cache(current, card);
    if (current != api) return;
    selectedId = localRole(card['id']);
    _changed();
  }

  Future<void> migrateGuest() async {
    final owner = api.owner!;
    await database.claimGuest(localOwnerId, owner);
    await refreshLibrary();
    _changed();
  }

  Future<void> logout() async {
    final current = api;
    final origin = current.origin!;
    final pendingKey = 'community.revoke.${origin.origin}';
    await storage.write(key: pendingKey, value: current.token);
    await _clear();
    _changed();
    await _revokePending(origin);
  }

  Future<void> _revokePending(Uri origin) async {
    final key = 'community.revoke.${origin.origin}';
    final token = await storage.read(key: key);
    if (token == null) return;
    try {
      await CommunityApi(
        origin,
        token: token,
      ).request('POST', '/community/logout');
      if (await storage.read(key: key) == token) await storage.delete(key: key);
    } on CommunityError {
      // Local sign-out already completed. Retry when this server is reachable.
    }
  }

  Future<void> expired(CommunityApi previous) async {
    if (api != previous) return;
    await _clear();
    _changed();
  }

  Future<void> _clear() async {
    await storage.delete(key: 'community.session');
    api = CommunityApi(api.origin);
    selectedId = null;
  }

  void _changed() {
    revision++;
    notifyListeners();
  }
}
