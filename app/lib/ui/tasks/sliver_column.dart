import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Slivers one after the other, painted from the first to the last, as a
/// `Column` paints its children.
///
/// Flutter paints the slivers of a scroll view, and of a
/// `SliverMainAxisGroup`, from the last to the first. A heading with a glow
/// (the Futuristic theme) would then shine over the row under it, and not
/// under it. The layout and the hit test are the ones of Flutter.
class SliverColumn extends SliverMainAxisGroup {
  const SliverColumn({super.key, required super.slivers});

  @override
  RenderSliverMainAxisGroup createRenderObject(BuildContext context) =>
      RenderSliverColumn();
}

class RenderSliverColumn extends RenderSliverMainAxisGroup {
  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      if (child.geometry!.visible) {
        final place = child.parentData! as SliverPhysicalParentData;
        context.paintChild(child, offset + place.paintOffset);
      }
      child = childAfter(child);
    }
  }
}
