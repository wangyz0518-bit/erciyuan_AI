import '../../characters/domain/character.dart';
import '../../timeline/domain/raw_event.dart';

/// An explicitly offline and deterministic summarizer. This is not an LLM.
abstract interface class MemorySummarizer {
  String get version;
  Future<MemoryDraft> summarize(List<RawEvent> sourceEvents);
}

final class MemoryDraft {
  const MemoryDraft({
    required this.text,
    required this.terms,
    required this.sourceEventIds,
    required this.confidence,
  });

  final String text;
  final List<String> terms;
  final List<String> sourceEventIds;
  final double confidence;
}

/// A reproducible baseline for archive/index/persistence tests, not quality.
final class DeterministicSummarizer implements MemorySummarizer {
  const DeterministicSummarizer();

  @override
  String get version => 'deterministic-v1';

  @override
  Future<MemoryDraft> summarize(List<RawEvent> sourceEvents) async {
    if (sourceEvents.isEmpty) {
      throw ArgumentError('Cannot summarize an empty archive');
    }
    final terms = <String>{};
    final lines = <String>[];
    for (final event in sourceEvents) {
      final content = event.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      final excerpt = content.length > 180
          ? content.substring(0, 180) + '…'
          : content;
      lines.add(event.speaker + ': ' + excerpt);
      for (final match in RegExp(
        r'[a-zA-Z0-9_]+|[\u4e00-\u9fff]+',
      ).allMatches(content.toLowerCase())) {
        final term = match.group(0)!;
        if (term.length >= 2 && terms.length < 80) terms.add(term);
      }
    }
    return MemoryDraft(
      text: lines.join('\n'),
      terms: terms.toList()..sort(),
      sourceEventIds: List.unmodifiable(
        sourceEvents.map((event) => event.eventId),
      ),
      // Fixed test marker; it is NOT a calibrated probability.
      confidence: 0.0,
    );
  }
}

final class MemorySummary {
  const MemorySummary({
    required this.scope,
    required this.summaryId,
    required this.archiveId,
    required this.text,
    required this.sourceEventIds,
    required this.terms,
    required this.generatorVersion,
    required this.status,
    required this.confidence,
  });

  final PersonScope scope;
  final String summaryId;
  final String archiveId;
  final String text;
  final List<String> sourceEventIds;
  final List<String> terms;
  final String generatorVersion;
  final String status;
  final double confidence;
}

final class PersonaCandidate {
  const PersonaCandidate({
    required this.candidateId,
    required this.scope,
    required this.proposedJson,
    required this.sourceSummaryIds,
    required this.status,
  });

  final String candidateId;
  final PersonScope scope;
  final String proposedJson;
  final List<String> sourceSummaryIds;
  final String status;
}

final class MemoryContext {
  const MemoryContext({
    required this.stablePrefix,
    required this.promptTemplateVersion,
    required this.recentEvents,
    required this.recalledSummaries,
    required this.expandedSourceEvents,
    required this.estimatedCharacters,
  });

  final String stablePrefix;
  final String promptTemplateVersion;
  final List<RawEvent> recentEvents;
  final List<MemorySummary> recalledSummaries;
  final List<RawEvent> expandedSourceEvents;

  /// Offline character-count proxy only; never a provider token count.
  final int estimatedCharacters;
}
