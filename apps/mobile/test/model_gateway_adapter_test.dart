import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:erciyuan_mobile/features/characters/domain/character.dart';
import 'package:erciyuan_mobile/features/chat/data/model_gateway_adapter.dart';
import 'package:erciyuan_mobile/features/memory/domain/memory_models.dart';
import 'package:erciyuan_mobile/features/timeline/data/person_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const star = PersonScope(ownerId: 'owner-a', characterId: 'star');
const moon = PersonScope(ownerId: 'owner-a', characterId: 'moon');
const token = 'local-development-token-for-tests';

Uri baseUri(HttpServer server) =>
    Uri.parse('http://127.0.0.1:' + server.port.toString() + '/');

Future<HttpServer> startServer(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    unawaited(handler(request));
  });
  return server;
}

Future<void> writeFrame(
  HttpResponse response,
  Map<String, Object?> frame,
) async {
  response.encoding = utf8;
  response.write('data: ' + jsonEncode(frame) + '\n\n');
  await response.flush();
}

Future<Map<String, dynamic>> readRequest(HttpRequest request) async {
  return jsonDecode(await utf8.decoder.bind(request).join())
      as Map<String, dynamic>;
}

void main() {
  sqfliteFfiInit();

  late Directory temp;
  late PersonDatabase database;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('erciyuan-model-adapter-');
    database = await PersonDatabase.open(
      factory: databaseFactoryFfi,
      databasePath: path.join(temp.path, 'persons.db'),
    );
    await database.createCharacter(
      character: const Character(
        scope: star,
        name: '小星',
        description: 'test character',
      ),
      timelineId: 'timeline-star',
      baseIdentityJson: '{"name":"小星","tone":"kind"}',
    );
    await database.createCharacter(
      character: const Character(
        scope: moon,
        name: '小月',
        description: 'test character',
      ),
      timelineId: 'timeline-moon',
      baseIdentityJson: '{"name":"小月","tone":"calm"}',
    );
  });

  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  Future<void> seedMemory() async {
    await database.appendEvent(
      scope: star,
      eventId: 'history-user-1',
      speaker: 'user',
      content: '我喜欢乌龙茶',
    );
    await database.appendEvent(
      scope: star,
      eventId: 'history-assistant-1',
      speaker: 'assistant',
      content: '我会记住乌龙茶',
    );
    await database.memory.archiveNext(
      scope: star,
      summarizer: const DeterministicSummarizer(),
    );
  }

  test('assembles #47 context, parses split SSE, and commits one complete reply', () async {
    await seedMemory();
    final received = Completer<Map<String, dynamic>>();
    final server = await startServer((request) async {
      if (request.method == 'POST' && request.uri.path.endsWith('/turns')) {
        final payload = await readRequest(request);
        received.complete(payload);
        final requestId = payload['request_id'] as String;
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        await writeFrame(request.response, {
          'event': 'message.started',
          'request_id': requestId,
          'character_id': 'star',
        });
        // Deliberately split one JSON event across writes.
        request.response.write('data: {"event":"message.delta","request_id":"');
        await request.response.flush();
        request.response.write(requestId);
        request.response.write('","character_id":"star","delta":"记得"}\n\n');
        await request.response.flush();
        await writeFrame(request.response, {
          'event': 'message.delta',
          'request_id': requestId,
          'character_id': 'star',
          'delta': '乌龙茶',
        });
        await writeFrame(request.response, {
          'event': 'message.completed',
          'request_id': requestId,
          'character_id': 'star',
          'content': '记得乌龙茶',
          'usage': null,
        });
        await request.response.close();
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
    final adapter = ModelGatewayAdapter(
      baseUri: baseUri(server),
      accessToken: token,
      database: database,
    );
    final updates = <ModelTurnUpdate>[];

    final result = await adapter.sendTurn(
      scope: star,
      requestId: 'request-star-0000001',
      userEventId: 'user-current-1',
      content: '乌龙茶',
      onUpdate: updates.add,
    );
    final sent = await received.future;
    final context = sent['context'] as Map<String, dynamic>;

    expect(result.status, ModelTurnStatus.completed);
    expect(result.content, '记得乌龙茶');
    expect(context['prefix_version'], 'person-prefix-v1');
    expect(context['stable_prefix'], contains('identity_version=0'));
    expect(context['selected_summaries'], isNotEmpty);
    expect(context['expanded_sources'], isNotEmpty);
    expect(
      (context['recent_events'] as List).any(
        (event) => (event as Map)['event_id'] == 'user-current-1',
      ),
      isFalse,
    );
    expect(sent.containsKey('owner_id'), isFalse);
    expect(updates.any((event) => event.type == ModelTurnUpdateType.delta), isTrue);

    final events = await database.rawEventsFor(scope: star);
    expect(events.map((event) => event.eventId), contains('user-current-1'));
    expect(events.last.eventId, 'assistant-request-star-0000001');
    expect(events.last.speaker, 'assistant');
    expect(events.last.content, '记得乌龙茶');
    expect(await database.rawEventsFor(scope: moon), isEmpty);

    final exported = jsonDecode(await database.exportOwnerJson(star.ownerId))
        as Map<String, dynamic>;
    final tasks = (exported['generation_tasks'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      tasks.singleWhere(
        (task) => task['request_id'] == 'request-star-0000001',
      )['status'],
      'complete',
    );

    adapter.close();
    await server.close(force: true);
  });

  test('failed partial stream is not committed as an assistant event', () async {
    final server = await startServer((request) async {
      if (request.method == 'POST' && request.uri.path.endsWith('/turns')) {
        final payload = await readRequest(request);
        final requestId = payload['request_id'] as String;
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        await writeFrame(request.response, {
          'event': 'message.started',
          'request_id': requestId,
          'character_id': 'star',
        });
        await writeFrame(request.response, {
          'event': 'message.delta',
          'request_id': requestId,
          'character_id': 'star',
          'delta': '未完成片段',
        });
        await writeFrame(request.response, {
          'event': 'message.failed',
          'request_id': requestId,
          'character_id': 'star',
          'code': 'MODEL_INCOMPLETE',
        });
        await request.response.close();
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
    final adapter = ModelGatewayAdapter(
      baseUri: baseUri(server),
      accessToken: token,
      database: database,
    );

    final result = await adapter.sendTurn(
      scope: star,
      requestId: 'request-star-failed-1',
      userEventId: 'user-failed-1',
      content: '测试失败',
    );

    expect(result.status, ModelTurnStatus.failed);
    expect(result.errorCode, 'MODEL_INCOMPLETE');
    final events = await database.rawEventsFor(scope: star);
    expect(events.map((event) => event.eventId), contains('user-failed-1'));
    expect(
      events.any((event) => event.eventId == 'assistant-request-star-failed-1'),
      isFalse,
    );

    adapter.close();
    await server.close(force: true);
  });

  test('retry uses a new request ID and does not duplicate the user event in context', () async {
    final payloads = <Map<String, dynamic>>[];
    final server = await startServer((request) async {
      if (request.method == 'POST' && request.uri.path.endsWith('/turns')) {
        final payload = await readRequest(request);
        payloads.add(payload);
        final requestId = payload['request_id'] as String;
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        if (payloads.length == 1) {
          await writeFrame(request.response, {
            'event': 'message.failed',
            'request_id': requestId,
            'character_id': 'star',
            'code': 'MODEL_TIMEOUT',
          });
        } else {
          await writeFrame(request.response, {
            'event': 'message.completed',
            'request_id': requestId,
            'character_id': 'star',
            'content': '重试成功',
            'usage': null,
          });
        }
        await request.response.close();
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
    final adapter = ModelGatewayAdapter(
      baseUri: baseUri(server),
      accessToken: token,
      database: database,
    );

    final first = await adapter.sendTurn(
      scope: star,
      requestId: 'request-star-retry-01',
      userEventId: 'user-retry-1',
      content: '重试内容',
    );
    final second = await adapter.sendTurn(
      scope: star,
      requestId: 'request-star-retry-02',
      userEventId: 'user-retry-1',
      content: '重试内容',
      retryOf: 'request-star-retry-01',
    );

    expect(first.status, ModelTurnStatus.failed);
    expect(second.status, ModelTurnStatus.completed);
    expect(payloads, hasLength(2));
    expect(payloads[1]['retry_of'], 'request-star-retry-01');
    final recent = (payloads[1]['context'] as Map)['recent_events'] as List;
    expect(
      recent.any((event) => (event as Map)['event_id'] == 'user-retry-1'),
      isFalse,
    );
    final events = await database.rawEventsFor(scope: star);
    expect(
      events.where((event) => event.eventId == 'user-retry-1'),
      hasLength(1),
    );
    expect(
      events.where((event) => event.speaker == 'assistant'),
      hasLength(1),
    );

    adapter.close();
    await server.close(force: true);
  });

  test('concurrent turns remain isolated by PersonScope', () async {
    final server = await startServer((request) async {
      if (request.method == 'POST' && request.uri.path.endsWith('/turns')) {
        final payload = await readRequest(request);
        final characterId = payload['character_id'] as String;
        final requestId = payload['request_id'] as String;
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        await writeFrame(request.response, {
          'event': 'message.completed',
          'request_id': requestId,
          'character_id': characterId,
          'content': 'reply-' + characterId,
          'usage': null,
        });
        await request.response.close();
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
    final adapter = ModelGatewayAdapter(
      baseUri: baseUri(server),
      accessToken: token,
      database: database,
    );

    final results = await Future.wait([
      adapter.sendTurn(
        scope: star,
        requestId: 'request-star-concurrent-1',
        userEventId: 'star-current-1',
        content: 'star input',
      ),
      adapter.sendTurn(
        scope: moon,
        requestId: 'request-moon-concurrent-1',
        userEventId: 'moon-current-1',
        content: 'moon input',
      ),
    ]);

    expect(
      results.map((result) => result.status),
      everyElement(ModelTurnStatus.completed),
    );
    final starEvents = await database.rawEventsFor(scope: star);
    final moonEvents = await database.rawEventsFor(scope: moon);
    expect(starEvents.last.content, 'reply-star');
    expect(moonEvents.last.content, 'reply-moon');
    expect(starEvents.any((event) => event.eventId == 'moon-current-1'), isFalse);
    expect(moonEvents.any((event) => event.eventId == 'star-current-1'), isFalse);

    adapter.close();
    await server.close(force: true);
  });

  test('cancel is confirmed by the gateway and never persists partial text', () async {
    final streamStarted = Completer<void>();
    final cancelReceived = Completer<void>();
    var serverStatus = 'running';
    const requestId = 'request-star-cancel-1';

    final server = await startServer((request) async {
      if (request.method == 'POST' && request.uri.path.endsWith('/turns')) {
        await readRequest(request);
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        await writeFrame(request.response, {
          'event': 'message.started',
          'request_id': requestId,
          'character_id': 'star',
        });
        streamStarted.complete();
        await cancelReceived.future;
        try {
          await request.response.close();
        } catch (_) {
          // The client aborts the stream after the cancel endpoint confirms.
        }
      } else if (request.method == 'POST' &&
          request.uri.path.endsWith('/cancel')) {
        serverStatus = 'cancelled';
        if (!cancelReceived.isCompleted) cancelReceived.complete();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'request_id': requestId,
          'character_id': 'star',
          'status': serverStatus,
          'content': '',
          'error': 'REQUEST_CANCELLED',
        }));
        await request.response.close();
      } else if (request.method == 'GET' &&
          request.uri.path.endsWith('/' + requestId)) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'request_id': requestId,
          'character_id': 'star',
          'status': serverStatus,
          'content': '',
          'error': 'REQUEST_CANCELLED',
        }));
        await request.response.close();
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
    final adapter = ModelGatewayAdapter(
      baseUri: baseUri(server),
      accessToken: token,
      database: database,
    );

    final sending = adapter.sendTurn(
      scope: star,
      requestId: requestId,
      userEventId: 'user-cancel-1',
      content: '取消测试',
    );
    await streamStarted.future.timeout(const Duration(seconds: 2));
    final cancelled = await adapter.cancelTurn(
      scope: star,
      requestId: requestId,
    );
    final sendResult = await sending.timeout(const Duration(seconds: 2));

    expect(cancelled.status, ModelTurnStatus.cancelled);
    expect(sendResult.status, ModelTurnStatus.cancelled);
    final events = await database.rawEventsFor(scope: star);
    expect(events.any((event) => event.eventId == 'user-cancel-1'), isTrue);
    expect(
      events.any((event) => event.eventId == 'assistant-' + requestId),
      isFalse,
    );
    final exported = jsonDecode(await database.exportOwnerJson(star.ownerId))
        as Map<String, dynamic>;
    final tasks = (exported['generation_tasks'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      tasks.singleWhere((task) => task['request_id'] == requestId)['status'],
      'cancelled',
    );

    adapter.close();
    await server.close(force: true);
  });
}
