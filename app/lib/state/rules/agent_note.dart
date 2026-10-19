import '../../core/agent/agent_models.dart';
import '../../core/agent/agent_policy.dart';
import '../../core/model/task.dart';
import '../../core/parsing/reference_parser.dart';

/// The notes the agent leaves on a task, and the plain messages of a job
/// (ADR 0004). No database and no views here.
///
/// Every text of the agent goes through [AgentPolicy.safeForNote], so it
/// cannot make a task or a link. Only the links Grove writes itself (to the
/// task, and to the document) are real links.
abstract final class AgentNote {
  // The messages of a job.

  static const crashed = 'Grove was closed while the agent worked.';
  static const timedOut =
      'The agent took longer than 10 minutes and was stopped.';
  static const cancelled = 'The job was cancelled.';
  static const taskGone = 'The task is gone.';
  static const notSaved = 'Grove could not save the result of the agent.';
  static const _noAnswer = 'The agent stopped before it answered.';

  /// The extra question when the job asked for email and this computer does
  /// not allow it.
  static const emailNotAllowed =
      'Email was not allowed on this computer, so the agent did not read '
      'your email. Turn on "Let the agent read my email" in Settings on the '
      'computer that runs agent tasks.';

  /// The longest error text of `claude` that is shown.
  static const _maxError = 300;

  /// A run that printed no answer. The first lines of [stderr] say why.
  static String noAnswer(String stderr) {
    final text = stderr.trim();
    if (text.isEmpty) return _noAnswer;
    final short = text.length > _maxError
        ? '${text.substring(0, _maxError)}…'
        : text;
    return '$_noAnswer $short';
  }

  // The notes.

  /// "Agent: Book the dentist"
  static String title(TaskItem task) => 'Agent: ${_line(task.title)}';

  /// The title of the document note: the agent's title, or "Document: Book
  /// the dentist" when it gave none.
  static String documentTitle(TaskItem task, AgentDocument doc) {
    final t = _line(AgentPolicy.safeForNote(doc.title));
    return t.isEmpty ? 'Document: ${_line(task.title)}' : t;
  }

  /// The body of the document note: a link to the task, then the document.
  static String documentBody(TaskItem task, AgentDocument doc) =>
      '${_taskLine(task)}\n\n${AgentPolicy.safeForNote(doc.markdown.trim())}';

  /// The body of the result note: links to the task and the document, then
  /// Summary, Steps, Email draft, Text draft, Questions and Sources. An empty
  /// part is left out.
  static String resultBody(
    TaskItem task,
    AgentResult result, {
    ({String id, String title})? document,
  }) {
    final head = [
      _taskLine(task),
      if (document case final d?)
        'Document: ${ReferenceParser.mention(title: d.title, id: d.id)}',
    ];
    final parts = <String>[
      '## Summary\n\n${result.summary.trim()}',
      if (result.steps.isNotEmpty) '## Steps\n\n${_list(result.steps)}',
      if (result.emailDraft case final e?)
        '## Email draft\n\nTo: ${_line(e.to)}\nSubject: ${_line(e.subject)}'
            '\n\n${e.body.trim()}',
      if (result.textDraft case final t?)
        '## Text draft\n\nTo: ${_line(t.to)}\n\n${t.body.trim()}',
      if (result.questions.isNotEmpty)
        '## Questions\n\n${_list(result.questions)}',
      if (result.sources.isNotEmpty) '## Sources\n\n${_list(result.sources)}',
    ];
    // The text of the agent is made safe as one piece, so a list line made
    // here cannot become a check box either.
    return '${head.join('\n')}\n\n'
        '${AgentPolicy.safeForNote(parts.join('\n\n'))}';
  }

  static String _taskLine(TaskItem task) =>
      'Task: ${ReferenceParser.mention(title: task.title, id: task.id)}';

  static String _list(List<String> items) => [
    for (final i in items)
      if (_line(i).isNotEmpty) '- ${_line(i)}',
  ].join('\n');

  static final _space = RegExp(r'\s+');

  /// One line, with the spaces collapsed.
  static String _line(String text) => text.replaceAll(_space, ' ').trim();
}
