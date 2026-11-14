import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/settings_service.dart';
import '../../shared/widgets/tv_focus.dart';
import 'trakt_auth_screen.dart';

/// Overlay prompt shown immediately after Google sign-in whenever Trakt
/// is not yet connected AND the user has not previously dismissed the prompt.
///
/// The prompt is dismissible via "Maybe Later" (remembers choice) or the
/// user can tap "Connect with Trakt" to jump straight into the device auth flow.
class TraktOnboardingPrompt extends StatelessWidget {
  const TraktOnboardingPrompt({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    // Don't show if:
    //  - the first-launch layout question is still unanswered (it decides which
    //    interface this card would even be drawn in), OR
    //  - Trakt is already connected, OR
    //  - User already dismissed the prompt
    if (!context.watch<SettingsService>().hasChosenLayout) {
      return const SizedBox.shrink();
    }
    if (auth.isTraktConnected || auth.hasDismissedTraktPrompt) {
      return const SizedBox.shrink();
    }

    void connect() {
      auth.setDismissedTraktPrompt(true);
      Navigator.of(context, rootNavigator: false).push(
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(
            value: auth,
            child: const TraktAuthScreen(),
          ),
        ),
      );
    }

    return Positioned.fill(
      child: GestureDetector(
        onTap: () => context.read<AuthService>().setDismissedTraktPrompt(true),
        // Material, not a plain Container: this overlay is a sibling of the
        // Scaffold rather than a child of it, so without a Material ancestor
        // every Text here draws Flutter's debug "missing Material" style —
        // bold and yellow-underlined.
        child: Material(
          color: Colors.black54,
          child: Dismissible(
            key: const ValueKey('trakt_prompt'),
            direction: DismissDirection.down,
            onDismissed: (_) =>
                context.read<AuthService>().setDismissedTraktPrompt(true),
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                child: GestureDetector(
                  onTap: () {}, // absorb inner taps
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(24),
                      border:
                          Border.all(color: AppColors.outlineVariant, width: 1),
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Supercharge Vyro',
                                style: AppTheme.badge.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                    letterSpacing: 0.8)),
                            TvFocusable(
                              semanticLabel: 'Close',
                              borderRadius: 999,
                              onSelect: () => context
                                  .read<AuthService>()
                                  .setDismissedTraktPrompt(true),
                              child: GestureDetector(
                                onTap: () => context
                                    .read<AuthService>()
                                    .setDismissedTraktPrompt(true),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.close_rounded,
                                    color: AppColors.onSurfaceVariant,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Hero: Trakt branding
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFED1C24),
                                Color(0xFFB71C1C),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.movie_filter_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        )
                            .animate()
                            .fadeIn(duration: 400.ms)
                            .scale(duration: 500.ms, curve: Curves.elasticOut),
                        const SizedBox(height: 18),
                        Text(
                          'Connect Trakt to get the most out of Vyro',
                          style: AppTheme.sectionTitle.copyWith(height: 1.25),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Trakt automatically tracks what you watch, syncs your ratings across devices, and powers your watchlist and recommendations.',
                          style: AppTheme.metadata.copyWith(height: 1.45),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        // Feature list
                        const _BenefitRow(
                            icon: Icons.history_rounded,
                            title: 'Watch History',
                            subtitle:
                                'Every movie and show — marked watched for you'),
                        const SizedBox(height: 14),
                        const _BenefitRow(
                            icon: Icons.star_rounded,
                            title: 'Sync Ratings & Reviews',
                            subtitle:
                                'Your ratings on Trakt appear here, and vice versa'),
                        const SizedBox(height: 14),
                        const _BenefitRow(
                            icon: Icons.bookmark_rounded,
                            title: 'Unified Watchlist',
                            subtitle:
                                'Add on Trakt.tv, stream on Vyro instantly'),
                        const SizedBox(height: 14),
                        const _BenefitRow(
                            icon: Icons.play_circle_fill_rounded,
                            title: 'Auto Scrobbling',
                            subtitle:
                                'End credits roll → marked watched. No extra taps'),
                        const SizedBox(height: 28),
                        // Primary CTA
                        SizedBox(
                          width: double.infinity,
                          child: TvButton(
                            // Overlay prompts appear on top of a screen that
                            // already has focus; without this a remote's OK
                            // button stays on the card underneath the barrier.
                            autofocus: true,
                            onSelect: connect,
                            semanticLabel: 'Connect with Trakt',
                            child: FilledButton.icon(
                              onPressed: connect,
                              icon: const Icon(Icons.link_rounded, size: 18),
                              label: const Text('Connect with Trakt'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFED1C24),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15),
                                textStyle:
                                    AppTheme.badge.copyWith(fontSize: 15),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Secondary CTA: maybe later
                        SizedBox(
                          width: double.infinity,
                          child: TvButton(
                            onSelect: () => context
                                .read<AuthService>()
                                .setDismissedTraktPrompt(true),
                            semanticLabel: 'Skip and go to the app',
                            child: TextButton(
                              onPressed: () => context
                                  .read<AuthService>()
                                  .setDismissedTraktPrompt(true),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.onSurfaceVariant,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                textStyle:
                                    AppTheme.metadata.copyWith(fontSize: 13),
                              ),
                              child: const Text('Maybe later, go to the app'),
                            ),
                          ),
                        ),
                      ],
                    ),
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

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primaryLight, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(title, style: AppTheme.cardTitle.copyWith(fontSize: 13.5)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: AppTheme.metadata.copyWith(fontSize: 12, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}
