class Message {
  Message({
    required this.id,
    required this.characterId,
    required this.author,
    required this.text,
    required this.status,
    required this.eventId,
    this.turnId,
    this.occurredAt,
    this.replyTo,
  });

  final int id;
  final String characterId, author, eventId;
  final String? turnId;
  final DateTime? occurredAt;
  String text, status;
  final int? replyTo;
}
