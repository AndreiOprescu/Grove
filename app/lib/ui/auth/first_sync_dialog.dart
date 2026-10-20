// The question of the first login (question card Q-4, answer A): this device
// has data and the account has data too. The person chooses one time.
import 'package:flutter/material.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../planner/planner_dialogs.dart' show DialogButton;
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';

/// The two answers, each with one line that says what it does. The sync
/// card shows it, and so does [showFirstSyncDialog].
class FirstSyncChoices extends StatelessWidget {
  const FirstSyncChoices({super.key, required this.store, this.onAnswered});

  final AppStore store;

  /// Runs after a tap on an answer, before the work of the answer is done.
  final VoidCallback? onAnswered;

  static const useAccountKey = ValueKey('first-sync-use-account');
  static const addDeviceKey = ValueKey('first-sync-add-device');

  void _answer(FirstSyncChoice choice) {
    onAnswered?.call();
    store.answerFirstSync(choice);
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final small = theme.body(12).copyWith(color: theme.muted);
    Widget choice(Key key, String label, String what, FirstSyncChoice value) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            DialogButton(key: key, label: label, onTap: () => _answer(value)),
            Text(what, style: small),
          ],
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        choice(
          useAccountKey,
          'Use the account data',
          'The data of this device is replaced. Grove saves a copy of it '
              'first.',
          FirstSyncChoice.useAccount,
        ),
        choice(
          addDeviceKey,
          'Add this device too',
          'Nothing is replaced. The account gets the data of this device '
              'too. A list or a task that is on both can show two times.',
          FirstSyncChoice.addDevice,
        ),
      ],
    );
  }
}

/// Opens the question as a small window. "Not now" closes it with no
/// answer: no sync runs, and the sync card keeps the question.
Future<void> showFirstSyncDialog(BuildContext context, AppStore store) =>
    showDialog<void>(
      context: context,
      builder: (context) {
        final theme = GroveTheme.of(context);
        return Dialog(
          key: const ValueKey('first-sync-dialog'),
          backgroundColor: theme.solidSurface,
          insetPadding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.radius),
            side: BorderSide(color: theme.line),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
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
                    const ThemedHeading('Two sets of data', 18),
                    Text(
                      'This device has data, and your account has data too. '
                      'What should Grove do? You choose one time.',
                      style: theme.body(13).copyWith(color: theme.muted),
                    ),
                    FirstSyncChoices(
                      store: store,
                      onAnswered: () => Navigator.of(context).pop(),
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        DialogButton(
                          key: const ValueKey('first-sync-later'),
                          label: 'Not now',
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

/// Opens the question by itself when the store has one. Put it around the
/// screens of the app, below the `MaterialApp` (it needs a `Navigator`).
class FirstSyncGate extends StatefulWidget {
  const FirstSyncGate({super.key, required this.store, required this.child});

  final AppStore store;
  final Widget child;

  @override
  State<FirstSyncGate> createState() => _FirstSyncGateState();
}

class _FirstSyncGateState extends State<FirstSyncGate> {
  bool _asked = false;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  void _check() {
    final question = widget.store.firstSyncQuestion;
    if (!question) {
      _asked = false;
      return;
    }
    // One window for one question. After "Not now" the card has it.
    if (_asked || _open) return;
    _asked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !widget.store.firstSyncQuestion) return;
      _open = true;
      await showFirstSyncDialog(context, widget.store);
      _open = false;
    });
  }

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: widget.store,
    onChange: _check,
    builder: (_) => widget.child,
  );
}
