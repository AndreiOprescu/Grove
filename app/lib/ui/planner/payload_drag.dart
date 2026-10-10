// A thing the user can drag onto the planner: a task, a note or a goal.
// The data is a `DragPayload` string. The planner's drop areas read the
// place of the pointer, so the drag keeps its picture at the pointer.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/grove_theme.dart';
import 'block_view.dart' show mouseKinds, touchKinds;

/// Makes `child` draggable. A mouse drags at once. A finger presses and
/// holds first, so a swipe still scrolls.
class PayloadDrag extends StatelessWidget {
  const PayloadDrag({
    super.key,
    required this.payload,
    required this.label,
    required this.child,
  });

  /// From `DragPayload.task`, `.note` or `.goal`.
  final String payload;

  /// The text that moves with the pointer.
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final feedback = _Feedback(theme: theme, label: label);
    return _KindDraggable(
      touch: false,
      data: payload,
      feedback: feedback,
      child: _KindDraggable(
        touch: true,
        data: payload,
        feedback: feedback,
        child: child,
      ),
    );
  }
}

class _KindDraggable extends Draggable<String> {
  const _KindDraggable({
    required this.touch,
    required String super.data,
    required super.feedback,
    required super.child,
  }) : super(dragAnchorStrategy: pointerDragAnchorStrategy, rootOverlay: true);

  final bool touch;

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) =>
      (touch
            ? DelayedMultiDragGestureRecognizer(supportedDevices: touchKinds)
            : ImmediateMultiDragGestureRecognizer(supportedDevices: mouseKinds))
        ..onStart = onStart;
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.theme, required this.label});

  final GroveTheme theme;
  final String label;

  @override
  Widget build(BuildContext context) => FractionalTranslation(
    // A little right of and below the pointer, so the pointer stays in view.
    translation: const Offset(0.05, 0.4),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: theme.solidSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.accent, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x38000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme
                .body(12, weight: FontWeight.w600)
                .copyWith(color: theme.ink, decoration: TextDecoration.none),
          ),
        ),
      ),
    ),
  );
}
