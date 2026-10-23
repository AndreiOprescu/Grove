import '../model/day_key.dart';
import '../model/ids.dart';

/// Where a job of the agent is (ADR 0004).
enum AgentStatus {
  /// Made on some device. It waits for the desktop that runs agent tasks.
  queued('queued'),

  /// A runner took it and `claude` is working on it.
  running('running'),

  /// The person pressed Cancel on some device. The runner sees it and stops.
  cancelRequested('cancel_requested'),
  done('done'),
  failed('failed'),
  cancelled('cancelled');

  const AgentStatus(this.code);

  /// The text in the database.
  final String code;

  /// An unknown text (a newer Grove) reads as failed, so nothing runs it.
  static AgentStatus fromCode(String code) =>
      values.firstWhere((s) => s.code == code, orElse: () => failed);

  /// Done, failed or cancelled: nothing happens to the job any more.
  bool get isFinished => this == done || this == failed || this == cancelled;
}

/// One task given to the agent. It syncs, so any device can make it and see
/// the result, and one desktop runs it.
class AgentJob {
  AgentJob({
    String? id,
    required this.taskId,
    this.instructions = '',
    this.emailAccess = false,
    this.status = AgentStatus.queued,
    this.runnerDevice,
    this.resultJson,
    this.error,
    this.resultNoteId,
    String? createdAt,
    String? updatedAt,
    this.finishedAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? updatedAt ?? Stamp.now(),
       updatedAt = updatedAt ?? createdAt ?? Stamp.now();

  final String id;
  final String taskId;

  /// What the person typed in the dialog, on top of the task itself.
  final String instructions;

  /// The person allowed the agent to read their email for this job. The
  /// runner also needs its own switch on.
  final bool emailAccess;
  final AgentStatus status;

  /// The name of the desktop that took the job.
  final String? runnerDevice;

  /// The [AgentResult] as JSON, when the job is done.
  final String? resultJson;

  /// A plain message for the person, when the job failed.
  final String? error;

  /// The note that holds the result.
  final String? resultNoteId;
  final String createdAt;
  final String updatedAt;
  final String? finishedAt;

  AgentJob copyWith({
    String? id,
    String? taskId,
    String? instructions,
    bool? emailAccess,
    AgentStatus? status,
    Object? runnerDevice = keep,
    Object? resultJson = keep,
    Object? error = keep,
    Object? resultNoteId = keep,
    String? createdAt,
    String? updatedAt,
    Object? finishedAt = keep,
  }) => AgentJob(
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    instructions: instructions ?? this.instructions,
    emailAccess: emailAccess ?? this.emailAccess,
    status: status ?? this.status,
    runnerDevice: identical(runnerDevice, keep)
        ? this.runnerDevice
        : runnerDevice as String?,
    resultJson: identical(resultJson, keep)
        ? this.resultJson
        : resultJson as String?,
    error: identical(error, keep) ? this.error : error as String?,
    resultNoteId: identical(resultNoteId, keep)
        ? this.resultNoteId
        : resultNoteId as String?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    finishedAt: identical(finishedAt, keep)
        ? this.finishedAt
        : finishedAt as String?,
  );

  List<Object?> get _props => [
    id,
    taskId,
    instructions,
    emailAccess,
    status,
    runnerDevice,
    resultJson,
    error,
    resultNoteId,
    createdAt,
    updatedAt,
    finishedAt,
  ];

  @override
  bool operator ==(Object other) =>
      other is AgentJob && sameList(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);

  @override
  String toString() => 'AgentJob($id, $taskId, ${status.code})';
}

/// A document the agent wrote. Grove saves it as its own note.
class AgentDocument {
  const AgentDocument({required this.title, required this.markdown});

  final String title;
  final String markdown;

  Map<String, Object?> toJson() => {'title': title, 'markdown': markdown};

  @override
  bool operator ==(Object other) =>
      other is AgentDocument &&
      other.title == title &&
      other.markdown == markdown;

  @override
  int get hashCode => Object.hash(title, markdown);
}

/// An email the agent wrote. Grove never sends it: the person opens it in
/// Mail and presses Send there.
class EmailDraft {
  const EmailDraft({required this.to, required this.subject, this.body = ''});

  /// One address, or several with commas between them.
  final String to;
  final String subject;
  final String body;

  Map<String, Object?> toJson() => {'to': to, 'subject': subject, 'body': body};

  @override
  bool operator ==(Object other) =>
      other is EmailDraft &&
      other.to == to &&
      other.subject == subject &&
      other.body == body;

  @override
  int get hashCode => Object.hash(to, subject, body);
}

/// A text message the agent wrote. The person opens it in Messages.
class TextDraft {
  const TextDraft({required this.to, required this.body});

  /// A phone number, or the name of the person when the agent has no number.
  final String to;
  final String body;

  Map<String, Object?> toJson() => {'to': to, 'body': body};

  @override
  bool operator ==(Object other) =>
      other is TextDraft && other.to == to && other.body == body;

  @override
  int get hashCode => Object.hash(to, body);
}

/// What the agent gives back (the JSON of `AgentPolicy.resultSchema`).
class AgentResult {
  const AgentResult({
    required this.summary,
    this.steps = const [],
    this.document,
    this.emailDraft,
    this.textDraft,
    this.questions = const [],
    this.sources = const [],
  });

  /// Reads the JSON of the agent. A missing list is empty. A draft with no
  /// body (or a document with no text) counts as no draft. Throws a
  /// [FormatException] when the summary is missing or a value has the wrong
  /// type.
  factory AgentResult.fromJson(Map<String, Object?> json) {
    final summary = json['summary'];
    if (summary is! String) {
      throw const FormatException('The result has no summary.');
    }
    final doc = _map(json, 'document');
    final email = _map(json, 'email_draft');
    final text = _map(json, 'text_draft');
    final markdown = doc == null ? '' : _text(doc, 'markdown');
    final emailBody = email == null ? '' : _text(email, 'body');
    final textBody = text == null ? '' : _text(text, 'body');
    return AgentResult(
      summary: summary,
      steps: _list(json, 'steps'),
      document: markdown.trim().isEmpty
          ? null
          : AgentDocument(title: _text(doc!, 'title'), markdown: markdown),
      emailDraft: emailBody.trim().isEmpty
          ? null
          : EmailDraft(
              to: _text(email!, 'to'),
              subject: _text(email, 'subject'),
              body: emailBody,
            ),
      textDraft: textBody.trim().isEmpty
          ? null
          : TextDraft(to: _text(text!, 'to'), body: textBody),
      questions: _list(json, 'questions'),
      sources: _list(json, 'sources'),
    );
  }

  final String summary;

  /// What the agent did, one line each.
  final List<String> steps;
  final AgentDocument? document;
  final EmailDraft? emailDraft;
  final TextDraft? textDraft;

  /// What the agent could not do or needs to know.
  final List<String> questions;

  /// The web pages and emails it used.
  final List<String> sources;

  Map<String, Object?> toJson() => {
    'summary': summary,
    'steps': steps,
    if (document case final d?) 'document': d.toJson(),
    if (emailDraft case final e?) 'email_draft': e.toJson(),
    if (textDraft case final t?) 'text_draft': t.toJson(),
    'questions': questions,
    'sources': sources,
  };

  static Map<String, Object?>? _map(Map<String, Object?> json, String key) =>
      switch (json[key]) {
        null => null,
        final Map<String, Object?> m => m,
        _ => throw FormatException('$key is not an object.'),
      };

  static String _text(Map<String, Object?> json, String key) =>
      switch (json[key]) {
        null => '',
        final String s => s,
        _ => throw FormatException('$key is not a text.'),
      };

  static List<String> _list(Map<String, Object?> json, String key) =>
      switch (json[key]) {
        null => const [],
        final List<Object?> l when l.every((x) => x is String) =>
          l.cast<String>().toList(),
        _ => throw FormatException('$key is not a list of texts.'),
      };

  @override
  bool operator ==(Object other) =>
      other is AgentResult &&
      other.summary == summary &&
      sameList(other.steps, steps) &&
      other.document == document &&
      other.emailDraft == emailDraft &&
      other.textDraft == textDraft &&
      sameList(other.questions, questions) &&
      sameList(other.sources, sources);

  @override
  int get hashCode => Object.hash(
    summary,
    Object.hashAll(steps),
    document,
    emailDraft,
    textDraft,
    Object.hashAll(questions),
    Object.hashAll(sources),
  );

  @override
  String toString() => 'AgentResult($summary)';
}
