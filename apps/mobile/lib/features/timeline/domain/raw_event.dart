import '../../characters/domain/character.dart';

/// Immutable raw interaction record. Archive operations never delete it.
class RawEvent {
  const RawEvent({
    required this.scope,
    required this.eventId,
    required this.sequence,
    required this.occurredAtUtc,
    required this.speaker,
    required this.kind,
    required this.content,
    required this.status,
    this.requestId,
    this.revisionOf,
  });

  final PersonScope scope;
  final String eventId;
  final int sequence;
  final String occurredAtUtc;
  final String speaker;
  final String kind;
  final String content;
  final String status;
  final String? requestId;
  final String? revisionOf;

  bool get isContextEligible => status == 'complete';
}
