/// The main screens of the app, in the order of the switch.
enum Screen {
  today('Today'),
  planner('Planner'),
  calendar('Calendar'),
  notes('Notes'),
  garden('Garden');

  const Screen(this.title);

  /// The word on the screen switch.
  final String title;
}
