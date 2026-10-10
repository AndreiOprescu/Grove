// The engine (app/lib/state, app/lib/core) names pictures with the SF Symbol
// names of the Mac app. SF Symbols exist only on Apple systems, so the
// screens map each name to a Material icon here.
import 'package:flutter/material.dart';

/// The icon for a name that is not in the list.
const IconData unknownSymbolIcon = Icons.help_outline;

const Map<String, IconData> _icons = {
  // left panels
  'note.text': Icons.sticky_note_2_outlined,
  'checklist': Icons.checklist,
  'target': Icons.track_changes,
  // command palette
  'plus.circle': Icons.add_circle_outline,
  'square.and.pencil': Icons.edit_square,
  'sun.max': Icons.wb_sunny_outlined,
  'calendar': Icons.calendar_month_outlined,
  'wand.and.stars': Icons.auto_fix_high_outlined,
  'calendar.day.timeline.left': Icons.view_timeline_outlined,
  'leaf': Icons.eco_outlined,
  'paintpalette': Icons.palette_outlined,
  'wind': Icons.air,
  'circle': Icons.circle_outlined,
  'checkmark.circle.fill': Icons.check_circle,
  // moods of a day
  'cloud.rain': Icons.cloudy_snowing,
  'cloud.sun': Icons.wb_cloudy_outlined,
};

/// True when `name` has its own icon.
bool hasSymbolIcon(String name) => _icons.containsKey(name);

/// The icon for an SF Symbol name. A name with no icon gives
/// [unknownSymbolIcon]; add the name to the list above.
IconData symbolIcon(String name) => _icons[name] ?? unknownSymbolIcon;
