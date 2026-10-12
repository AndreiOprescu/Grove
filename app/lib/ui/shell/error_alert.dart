// Port of the `.alert("Grove", ...)` of Sources/Grove/Layouts/
// RootView.swift: when the store has an error message, a small window shows
// it. "OK" takes the message away.
import 'package:flutter/material.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../planner/planner_dialogs.dart' show DialogButton;
import '../theme/grove_theme.dart';
import '../theme/panel.dart';

/// The small window with one message and "OK".
Future<void> showErrorAlert(BuildContext context, String message) =>
    showDialog<void>(
      context: context,
      builder: (context) {
        final theme = GroveTheme.of(context);
        return Dialog(
          key: const ValueKey('error-alert'),
          backgroundColor: theme.solidSurface,
          insetPadding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.radius),
            side: BorderSide(color: theme.line),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            // The text style of the app, not the Material one of a dialog
            // (that one adds a gap between letters).
            child: DefaultTextStyle(
              style: theme.body(13).copyWith(color: theme.ink),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [
                    const ThemedHeading('Grove', 18),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        key: const ValueKey('error-alert-text'),
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        DialogButton(
                          key: const ValueKey('error-alert-ok'),
                          label: 'OK',
                          primary: true,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

/// Opens the window by itself when the store has an error message. Put it
/// around the screens of the app, below the `MaterialApp` (it needs a
/// `Navigator`).
class ErrorGate extends StatefulWidget {
  const ErrorGate({super.key, required this.store, required this.child});

  final AppStore store;
  final Widget child;

  @override
  State<ErrorGate> createState() => _ErrorGateState();
}

class _ErrorGateState extends State<ErrorGate> {
  /// A window is open, or will open after this frame.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_check);
    _check();
  }

  @override
  void didUpdateWidget(ErrorGate old) {
    super.didUpdateWidget(old);
    if (old.store != widget.store) {
      old.store.removeListener(_check);
      widget.store.addListener(_check);
      _check();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (_busy || widget.store.errorMessage == null) return;
    _busy = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _show() async {
    final store = widget.store;
    final message = store.errorMessage;
    if (!mounted || message == null) {
      _busy = false;
      return;
    }
    // "OK", a click next to the window and Escape all close it.
    await showErrorAlert(context, message);
    _busy = false;
    if (!mounted) return;
    // A newer message stays, and gets its own window.
    if (store.errorMessage == message) store.errorMessage = null;
    _check();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
