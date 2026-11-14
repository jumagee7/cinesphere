import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/device_form.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/tv_focus.dart';

/// The first-launch question: which interface does this screen want?
///
/// Guessing from geometry is what labelled every Android TV a tablet, and a
/// maximised desktop browser measures exactly like a 10-foot set, so the app
/// asks once and remembers. Nothing dismisses it — but it only appears after
/// sign-in, so it can never stand between someone and the account screen.
class LayoutChoicePrompt extends StatelessWidget {
  const LayoutChoicePrompt({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    if (settings.hasChosenLayout) return const SizedBox.shrink();

    // Two full-screen asks at once is one too many: the layout decides what the
    // Trakt card even looks like, so it goes first.
    final auth = context.watch<AuthService>();
    final traktAskPending =
        !auth.isTraktConnected && !auth.hasDismissedTraktPrompt;

    final guess = deviceFormOf(context);

    return Positioned.fill(
      // Material rather than a Container: this prompt is a sibling of the
      // Scaffold, so with no Material ancestor its text draws the debug
      // "missing Material" style — bold and yellow-underlined.
      child: Material(
        color: Colors.black.withValues(alpha: 0.72),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.outlineVariant),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xB3000000),
                        blurRadius: 40,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Choose your layout',
                          style:
                              AppTheme.sectionTitle.copyWith(fontSize: 20)),
                      const SizedBox(height: 6),
                      Text(
                        traktAskPending
                            ? 'It only takes a second — we will ask about Trakt afterwards.'
                            : 'Vyro sizes its cards and navigation to the screen it opens on. Pick the one that matches yours; you can change it later in Settings.',
                        style: AppTheme.metadata.copyWith(height: 1.45),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      for (final option in _layoutOptions) ...[
                        _OptionCard(
                          option: option,
                          // A remote starts on the answer the canvas suggests.
                          autofocus: option.form == guess,
                          onSelect: () => context
                              .read<SettingsService>()
                              .chooseLayout(option.form),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The same three choices as a modal, for someone who wants to change their
/// mind after the first-launch answer.
Future<void> showLayoutPicker(BuildContext context) {
  final current = context.read<SettingsService>().forcedLayout;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    // Three cards plus the heading are taller than a landscape phone, and a
    // bottom sheet that cannot scroll just clips the last option off screen.
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Interface layout', style: AppTheme.sectionTitle),
            const SizedBox(height: 4),
            Text('Applies the moment you pick it.',
                style: AppTheme.metadata.copyWith(height: 1.4)),
            const SizedBox(height: 16),
            for (final option in _layoutOptions)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OptionCard(
                  option: option,
                  autofocus: option.form ==
                      (current ?? deviceFormOf(sheetContext)),
                  selected: option.form == current,
                  onSelect: () {
                    sheetContext
                        .read<SettingsService>()
                        .chooseLayout(option.form);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// The three things a screen can be for. Shared by the first-launch prompt and
/// the Settings picker so the two can never drift apart.
const List<_LayoutOption> _layoutOptions = [
  _LayoutOption(
    form: DeviceForm.tv,
    icon: Icons.live_tv_rounded,
    title: 'TV',
    blurb:
        'Side-rail navigation, big artwork and D-pad focus. Stays landscape.',
  ),
  _LayoutOption(
    form: DeviceForm.tablet,
    icon: Icons.tablet_rounded,
    title: 'Tablet',
    blurb:
        'Bottom tabs, with cards and grid columns that grow with the screen.',
  ),
  _LayoutOption(
    form: DeviceForm.phone,
    icon: Icons.phone_android_rounded,
    title: 'Mobile',
    blurb: 'Bottom tabs and phone-sized cards, whatever the screen is.',
  ),
];

class _LayoutOption {
  final DeviceForm form;
  final IconData icon;
  final String title;
  final String blurb;

  const _LayoutOption({
    required this.form,
    required this.icon,
    required this.title,
    required this.blurb,
  });
}

class _OptionCard extends StatelessWidget {
  final _LayoutOption option;
  final bool autofocus;
  final bool selected;
  final VoidCallback onSelect;

  const _OptionCard({
    required this.option,
    required this.autofocus,
    this.selected = false,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      semanticLabel: 'Use the ${option.title.toLowerCase()} layout',
      scale: 1.015,
      borderRadius: 16,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(option.icon, color: AppColors.primaryLight, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(option.title, style: AppTheme.cardTitle),
                  const SizedBox(height: 3),
                  Text(
                    option.blurb,
                    style: AppTheme.metadata.copyWith(height: 1.35),
                  ),
                ],
              ),
            ),
            if (selected)
              const Padding(
                padding: EdgeInsets.only(left: 10, top: 10),
                child: Icon(Icons.check_circle_rounded,
                    color: AppColors.primaryLight, size: 22),
              ),
          ],
        ),
      ).animate().fadeIn(duration: 220.ms),
    );
  }
}
