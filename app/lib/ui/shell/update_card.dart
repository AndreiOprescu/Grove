// The card that says a newer Grove is out on GitHub. It shows over every
// screen until the person picks Later or Skip (`AppStore.availableUpdate`).
// Update opens the file for this device; the person installs it.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../editor/editor_tools.dart' show LinkOpener;
import '../tasks/task_widgets.dart' show CardButton, StoreBuilder;
import '../theme/grove_theme.dart';
import 'shell_layout.dart';

class UpdateLayer extends StatelessWidget {
  const UpdateLayer({
    super.key,
    required this.store,
    required this.openLink,
    required this.child,
    this.platform,
  });

  final AppStore store;

  /// Opens a link in the browser. Null in a test with no browser.
  final LinkOpener? openLink;
  final Widget child;

  /// The device, for the right file. Null: this device.
  final UpdatePlatform? platform;

  static UpdatePlatform thisDevice() {
    if (kIsWeb) return UpdatePlatform.other;
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS => UpdatePlatform.macos,
      TargetPlatform.windows => UpdatePlatform.windows,
      TargetPlatform.android => UpdatePlatform.android,
      TargetPlatform.iOS => UpdatePlatform.ios,
      _ => UpdatePlatform.other,
    };
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      child,
      Positioned.fill(
        child: StoreBuilder(store: store, builder: _place),
      ),
    ],
  );

  Widget _place(BuildContext context) {
    final release = store.availableUpdate;
    return LayoutBuilder(
      builder: (context, box) {
        final phone = ShellRules.layoutFor(box.maxWidth) == ShellLayout.phone;
        return SafeArea(
          child: Align(
            alignment: phone ? Alignment.bottomCenter : Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: release == null
                    ? const SizedBox.shrink()
                    : ConstrainedBox(
                        key: ValueKey('update-${release.version}'),
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: _UpdateCard(
                          release: release,
                          platform: platform ?? thisDevice(),
                          store: store,
                          openLink: openLink,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({
    required this.release,
    required this.platform,
    required this.store,
    required this.openLink,
  });

  final ReleaseInfo release;
  final UpdatePlatform platform;
  final AppStore store;
  final LinkOpener? openLink;

  void _open(String url) {
    final openLink = this.openLink;
    final uri = Uri.tryParse(url);
    if (openLink == null || uri == null) {
      store.showToast('Grove could not open the link.');
      return;
    }
    unawaited(
      openLink(uri).then((opened) {
        if (!opened) store.showToast('Grove could not open the link.');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final download = release.downloadFor(platform);
    return Semantics(
      key: const ValueKey('update-card'),
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.solidSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.line),
          boxShadow: [
            BoxShadow(
              color: theme.ink.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [
              Text(
                'Grove ${release.version} is here',
                style: theme
                    .body(14, weight: FontWeight.w700)
                    .copyWith(color: theme.ink),
              ),
              Text(
                download == null
                    ? 'You have Grove ${store.currentVersion}. See what is '
                          'new on GitHub.'
                    : 'You have Grove ${store.currentVersion}. Update '
                          'downloads the new version. Open the file to '
                          'install it.',
                style: theme.body(12).copyWith(color: theme.muted),
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (download != null)
                    CardButton(
                      key: const ValueKey('update-download'),
                      label: 'Update',
                      primary: true,
                      onTap: () => _open(download),
                    ),
                  CardButton(
                    key: const ValueKey('update-notes'),
                    label: "What's new",
                    onTap: () => _open(release.pageUrl),
                  ),
                  CardButton(
                    key: const ValueKey('update-later'),
                    label: 'Later',
                    onTap: store.laterUpdate,
                  ),
                  CardButton(
                    key: const ValueKey('update-skip'),
                    label: 'Skip this version',
                    onTap: store.skipUpdate,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
