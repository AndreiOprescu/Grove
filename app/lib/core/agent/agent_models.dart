import 'dart:convert';

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

/// One chat with the agent (ADR 0004, 0005). It syncs, so any device can
/// make it and see the result, and one desktop runs it. A job made from a
/// task has [taskId]; a job made on the Agents screen may have none. Each
/// new message of the person queues the job again: the messages, steps and
/// results are its [AgentEvent]s.
class AgentJob {
  AgentJob({
    String? id,
    this.taskId,
    this.title = '',
    this.instructions = '',
    this.emailAccess = false,
    this.planAccess = false,
    this.links = const [],
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
  final String? taskId;

  /// The name of the chat in the list of the Agents screen.
  final String title;

  /// What the person typed first, on top of the task itself.
  final String instructions;

  /// The person allowed the agent to read their email for this job. The
  /// runner also needs its own switch on.
  final bool emailAccess;

  /// The person allowed the agent to see their plan: the open tasks, the
  /// blocks and the deadlines of the next days.
  final bool planAccess;

  /// The notes, tasks and files the person linked to the chat.
  final List<AgentLink> links;
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
    Object? taskId = keep,
    String? title,
    String? instructions,
    bool? emailAccess,
    bool? planAccess,
    List<AgentLink>? links,
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
    taskId: identical(taskId, keep) ? this.taskId : taskId as String?,
    title: title ?? this.title,
    instructions: instructions ?? this.instructions,
    emailAccess: emailAccess ?? this.emailAccess,
    planAccess: planAccess ?? this.planAccess,
    links: links ?? this.links,
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
    title,
    instructions,
    emailAccess,
    planAccess,
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
      other is AgentJob &&
      sameList(other._props, _props) &&
      sameList(other.links, links);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(_props), Object.hashAll(links));

  @override
  String toString() => 'AgentJob($id, $taskId, ${status.code})';
}

/// What a link of a chat points at.
enum AgentLinkKind {
  note('note'),
  task('task'),

  /// A file the person added on a computer. Grove keeps a copy on that
  /// computer only: files do not sync (ADR 0005).
  file('file');

  const AgentLinkKind(this.code);

  final String code;

  static AgentLinkKind? fromCode(Object? code) =>
      values.where((k) => k.code == code).firstOrNull;
}

/// A note, a task or a file that the person linked to a chat. The agent
/// reads it as data, never as instructions.
class AgentLink {
  const AgentLink({
    required this.kind,
    required this.id,
    required this.name,
    this.device,
  });

  final AgentLinkKind kind;

  /// The id of the note or task. For a file: the name of its copy in the
  /// agent files folder of [device].
  final String id;

  /// What the person sees: the title, or the name of the file.
  final String name;

  /// For a file: the device that keeps the copy.
  final String? device;

  Map<String, Object?> toJson() => {
    'kind': kind.code,
    'id': id,
    'name': name,
    'device': ?device,
  };

  /// Reads the `links_json` of a job. A link Grove cannot read is left out,
  /// and text that is no list gives no links.
  static List<AgentLink> listFromJson(String? text) {
    if (text == null || text.trim().isEmpty) return const [];
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return const [];
    }
    if (json is! List<Object?>) return const [];
    return [
      for (final l in json)
        if (l
            case {
              'kind': final Object? kind,
              'id': final String id,
              'name': final String name,
            }
            when AgentLinkKind.fromCode(kind) != null)
          AgentLink(
            kind: AgentLinkKind.fromCode(kind)!,
            id: id,
            name: name,
            device: l['device'] is String ? l['device'] as String : null,
          ),
    ];
  }

  static String listToJson(List<AgentLink> links) =>
      jsonEncode([for (final l in links) l.toJson()]);

  @override
  bool operator ==(Object other) =>
      other is AgentLink &&
      other.kind == kind &&
      other.id == id &&
      other.name == name &&
      other.device == device;

  @override
  int get hashCode => Object.hash(kind, id, name, device);

  @override
  String toString() => 'AgentLink(${kind.code}, $id, $name)';
}

/// What a line of a chat is.
enum AgentEventKind {
  /// A message of the person.
  ask('ask'),

  /// One thing the agent did while it worked: a search, a page or a file
  /// it read, a thought, a tool that was refused.
  step('step'),

  /// The answer of one run: the JSON of an [AgentResult].
  result('result'),

  /// The run failed or was cancelled. The body says why.
  stopped('stopped');

  const AgentEventKind(this.code);

  final String code;

  /// An unknown text (a newer Grove) reads as a step: shown, never run.
  static AgentEventKind fromCode(String code) =>
      values.firstWhere((k) => k.code == code, orElse: () => step);
}

/// One line of a chat with the agent. Events sync, so a phone can watch a
/// job that runs on the computer.
class AgentEvent {
  AgentEvent({
    String? id,
    required this.jobId,
    required this.seq,
    required this.kind,
    this.label = '',
    this.body = '',
    String? createdAt,
    String? updatedAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? updatedAt ?? Stamp.now(),
       updatedAt = updatedAt ?? createdAt ?? Stamp.now();

  final String id;
  final String jobId;

  /// The place in the chat, from 1.
  final int seq;
  final AgentEventKind kind;

  /// For a step: what kind of step ([AgentStep.label]). For a result: the
  /// keys of the changes the person applied, with commas between them.
  final String label;
  final String body;
  final String createdAt;
  final String updatedAt;

  AgentEvent copyWith({String? label, String? body, String? updatedAt}) =>
      AgentEvent(
        id: id,
        jobId: jobId,
        seq: seq,
        kind: kind,
        label: label ?? this.label,
        body: body ?? this.body,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is AgentEvent &&
      other.id == id &&
      other.jobId == jobId &&
      other.seq == seq &&
      other.kind == kind &&
      other.label == label &&
      other.body == body &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(id, jobId, seq, kind, label, body, createdAt, updatedAt);

  @override
  String toString() => 'AgentEvent($jobId #$seq ${kind.code} $label)';
}

/// One thing the agent did, read from a line of its output.
class AgentStep {
  const AgentStep(this.label, this.text);

  /// [search], [web], [file], [mail], [think], [blocked] or [tool].
  final String label;
  final String text;

  static const search = 'search';
  static const web = 'web';
  static const file = 'file';
  static const mail = 'mail';
  static const think = 'think';
  static const blocked = 'blocked';
  static const tool = 'tool';

  @override
  bool operator ==(Object other) =>
      other is AgentStep && other.label == label && other.text == text;

  @override
  int get hashCode => Object.hash(label, text);

  @override
  String toString() => 'AgentStep($label, $text)';
}

/// A change of the plan that the agent proposes: put a task on the planner
/// on [day] at [start] for [minutes]. Nothing changes until the person
/// presses Apply.
class PlanChange {
  const PlanChange({
    required this.taskId,
    required this.day,
    required this.start,
    required this.minutes,
  });

  final String taskId;
  final DayKey day;

  /// Minutes after midnight.
  final int start;
  final int minutes;

  Map<String, Object?> toJson() => {
    'task_id': taskId,
    'day': day.string,
    'start': AgentTime.format(start),
    'minutes': minutes,
  };

  /// Null when a value is missing or wrong: the change is left out.
  static PlanChange? fromJson(Object? json) {
    if (json case {
      'task_id': final String taskId,
      'day': final String day,
      'start': final String start,
      'minutes': final num minutes,
    }) {
      final d = DayKey.parse(day);
      final s = AgentTime.parse(start);
      final m = minutes.round();
      if (taskId.isEmpty || d == null || s == null) return null;
      if (m < 5 || m > 720 || s + m > 1440) return null;
      return PlanChange(taskId: taskId, day: d, start: s, minutes: m);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PlanChange &&
      other.taskId == taskId &&
      other.day == day &&
      other.start == start &&
      other.minutes == minutes;

  @override
  int get hashCode => Object.hash(taskId, day, start, minutes);
}

/// A new task that the agent proposes, maybe as a subtask of
/// [parentTaskId], maybe planned for [day]. Nothing is made until the
/// person presses Apply.
class NewTask {
  const NewTask({
    required this.title,
    this.parentTaskId,
    this.minutes,
    this.day,
  });

  final String title;
  final String? parentTaskId;
  final int? minutes;
  final DayKey? day;

  Map<String, Object?> toJson() => {
    'title': title,
    'parent_task_id': parentTaskId ?? '',
    'minutes': minutes ?? 0,
    'day': day?.string ?? '',
  };

  /// Null when the title is missing. An empty parent, 0 minutes or an
  /// empty day mean "none".
  static NewTask? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final title = json['title'];
    if (title is! String || title.trim().isEmpty) return null;
    final parent = json['parent_task_id'];
    final minutes = json['minutes'];
    final day = json['day'];
    final m = minutes is num ? minutes.round() : 0;
    return NewTask(
      title: title.trim(),
      parentTaskId: parent is String && parent.isNotEmpty ? parent : null,
      minutes: m > 0 && m <= 720 ? m : null,
      day: day is String ? DayKey.parse(day) : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NewTask &&
      other.title == title &&
      other.parentTaskId == parentTaskId &&
      other.minutes == minutes &&
      other.day == day;

  @override
  int get hashCode => Object.hash(title, parentTaskId, minutes, day);
}

/// "14:30" ↔ 870, the way the agent writes a time of day.
abstract final class AgentTime {
  static final _hm = RegExp(r'^(\d{1,2}):(\d{2})$');

  static int? parse(String text) {
    final m = _hm.firstMatch(text.trim());
    if (m == null) return null;
    final h = int.parse(m[1]!), min = int.parse(m[2]!);
    if (h > 23 || min > 59) return null;
    return h * 60 + min;
  }

  static String format(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:'
      '${(minute % 60).toString().padLeft(2, '0')}';
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
    this.planChanges = const [],
    this.newTasks = const [],
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
      planChanges: [
        for (final c in _items(json, 'plan_changes')) ?PlanChange.fromJson(c),
      ],
      newTasks: [
        for (final t in _items(json, 'new_tasks')) ?NewTask.fromJson(t),
      ],
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

  /// Times on the planner it proposes for tasks. A change Grove cannot read
  /// is left out.
  final List<PlanChange> planChanges;

  /// Tasks it proposes to add.
  final List<NewTask> newTasks;

  /// The key of a proposal, kept in the result event when it is applied.
  static String planKey(int index) => 'p$index';
  static String taskKey(int index) => 't$index';

  Map<String, Object?> toJson() => {
    'summary': summary,
    'steps': steps,
    if (document case final d?) 'document': d.toJson(),
    if (emailDraft case final e?) 'email_draft': e.toJson(),
    if (textDraft case final t?) 'text_draft': t.toJson(),
    'questions': questions,
    'sources': sources,
    if (planChanges.isNotEmpty)
      'plan_changes': [for (final c in planChanges) c.toJson()],
    if (newTasks.isNotEmpty)
      'new_tasks': [for (final t in newTasks) t.toJson()],
  };

  /// The items of a list of proposals. Anything else gives none: a wrong
  /// proposal must not lose the rest of the answer.
  static List<Object?> _items(Map<String, Object?> json, String key) =>
      switch (json[key]) {
        final List<Object?> l => l,
        _ => const [],
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
      sameList(other.sources, sources) &&
      sameList(other.planChanges, planChanges) &&
      sameList(other.newTasks, newTasks);

  @override
  int get hashCode => Object.hash(
    summary,
    Object.hashAll(steps),
    document,
    emailDraft,
    textDraft,
    Object.hashAll(questions),
    Object.hashAll(sources),
    Object.hashAll(planChanges),
    Object.hashAll(newTasks),
  );

  @override
  String toString() => 'AgentResult($summary)';
}
