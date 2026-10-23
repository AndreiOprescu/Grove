/// The main screens of the app, in the order of the switch.
enum Screen {
  today('Today'),
  planner('Planner'),
  calendar('Calendar'),
  notes('Notes'),
  garden('Garden'),
  persona('Persona'),

  /// The chats with the agent (ADR 0005). It shows only when the agent is
  /// on in Settings.
  agents('Agents');

  const Screen(this.title);

  /// The word on the screen switch.
  final String title;

  /// The screens that always show, in the order of the switch.
  static const always = [today, planner, calendar, notes, garden, persona];
}
