import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

// Prototype-only local schema; this is not the cross-team server contract.
class Character {
  const Character(this.id, this.name, this.description);
  final String id;
  final String name;
  final String description;
}

const demoCharacters = [
  Character('xing', '小星', '温柔的星空旅伴'),
  Character('yue', '小月', '开朗的月光旅伴'),
];

class Message {
  Message({
    required this.id,
    required this.characterId,
    required this.author,
    required this.text,
    required this.status,
    this.replyTo,
  });
  final int id;
  final String characterId;
  final String author;
  String text;
  String status;
  final int? replyTo;
  Map<String, Object?> toRow() => {
    'id': id,
    'character_id': characterId,
    'author': author,
    'text': text,
    'status': status,
    'reply_to': replyTo,
  };
  factory Message.fromRow(Map<String, Object?> r) => Message(
    id: r['id'] as int,
    characterId: r['character_id'] as String,
    author: r['author'] as String,
    text: r['text'] as String,
    status: r['status'] as String,
    replyTo: r['reply_to'] as int?,
  );
}

class LocalStore {
  LocalStore(this.db);
  final Database db;
  static Future<LocalStore> open({String name = 'companion-poc.db'}) async {
    final db = await openDatabase(
      path.join(await getDatabasesPath(), name),
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE characters (id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE messages (id INTEGER PRIMARY KEY, character_id TEXT NOT NULL, author TEXT NOT NULL, text TEXT NOT NULL, status TEXT NOT NULL, reply_to INTEGER)',
        );
        await db.execute(
          'CREATE INDEX messages_character ON messages(character_id, id)',
        );
        await db.execute(
          'CREATE TABLE preferences (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        for (final c in demoCharacters) {
          await db.insert('characters', {
            'id': c.id,
            'name': c.name,
            'description': c.description,
          });
        }
      },
    );
    // A process can die between any two streamed chunks. Never restore a spinner.
    await db.update(
      'messages',
      {'status': 'interrupted'},
      where: 'status = ?',
      whereArgs: ['pending'],
    );
    return LocalStore(db);
  }

  Future<List<Character>> characters() async =>
      (await db.query('characters', orderBy: 'id'))
          .map(
            (r) => Character(
              r['id'] as String,
              r['name'] as String,
              r['description'] as String,
            ),
          )
          .toList();
  Future<List<Message>> messages(String id) async => (await db.query(
    'messages',
    where: 'character_id = ?',
    whereArgs: [id],
    orderBy: 'id',
  )).map(Message.fromRow).toList();
  Future<void> save(Message m) async => db.insert(
    'messages',
    m.toRow(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  Future<void> savePair(Message a, Message b) async =>
      db.transaction((txn) async {
        await txn.insert('messages', a.toRow());
        await txn.insert('messages', b.toRow());
      });
  Future<String?> preference(String key) async {
    final r = await db.query('preferences', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  Future<void> setPreference(String key, String value) async => db.insert(
    'preferences',
    {'key': key, 'value': value},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  Future<int> count() async =>
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM messages'),
      ) ??
      0;
}
