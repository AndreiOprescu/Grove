import 'package:flutter/material.dart';

/// Root widget. Themes, navigation and the Day Planner come in later
/// milestones (see docs/cross-platform-plan.md).
class GroveApp extends StatelessWidget {
  const GroveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grove',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F7A5A),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F7A5A),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const _HomePlaceholder(),
    );
  }
}

class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text('Grove', style: Theme.of(context).textTheme.displayMedium),
      ),
    );
  }
}
