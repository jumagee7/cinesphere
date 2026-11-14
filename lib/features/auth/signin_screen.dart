import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../app.dart';
import '../../core/services/device_form.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../shared/widgets/tv_focus.dart';
import '../../shared/widgets/vyro_logo.dart';
import 'trakt_auth_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _isSigningIn = false;
  bool _isContinuingGuest = false;
  String? _error;
  bool _enteredApp = false;

  /// The splash route only ever *replaced* this screen, so when sign-in
  /// succeeds mid-route nothing can swap the page: without this the user gets
  /// a blank screen until they kill and relaunch the app.
  void _enterApp() {
    if (_enteredApp || !mounted) return;
    _enteredApp = true;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthenticatedAppShell()),
      (route) => false,
    );
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isSigningIn = true;
      _error = null;
    });
    final ok = await context.read<AuthService>().signInWithGoogle();
    if (!mounted) return;
    setState(() => _isSigningIn = false);
    if (!ok) {
      setState(
          () => _error = 'Could not sign in with Google. Please try again.');
    }
  }

  Future<void> _handleContinueGuest() async {
    setState(() {
      _isContinuingGuest = true;
      _error = null;
    });
    await context.read<AuthService>().continueAsGuest();
    if (!mounted) return;
    setState(() => _isContinuingGuest = false);
  }

  /// TV path: pair Trakt by entering a code on a phone, since that is the one
  /// sign-in a remote can complete. Entering a Trakt-connected seat still
  /// needs a profile, so the pairing also opens the guest door.
  Future<void> _openTraktPairing() async {
    final auth = context.read<AuthService>();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
        value: auth,
        child: const TraktAuthScreen(),
      ),
    ));
    if (auth.isTraktConnected) await auth.continueAsGuest();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    // Safety: if Google signed in OR guest mode active, don't show this screen.
    if (auth.isGoogleSignedIn || auth.isGuest) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _enterApp());
      return const SizedBox.shrink();
    }

    // Android TV ships no Google account UI and no browser to bounce into, and
    // google_sign_in has no desktop implementation either, so the Google button
    // can only ever fail there. A TV *layout* in a browser is the other case:
    // the browser can run the OAuth pop-up, so the button stays and the remote
    // reaches it with a focus ring.
    final onTv = deviceFormOf(context).isTv;
    final googleOutOfReach = nativeTvDetected || (onTv && !kIsWeb);

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Background glow ─────────────────────────────────────────
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.1, -0.4),
                      radius: 1.0,
                      colors: [
                        AppColors.primary.withValues(alpha: 0.25),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.6],
                    ),
                  ),
                ),
              ),
            ),
            // ── Content ──────────────────────────────────────────────────
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  // App logo
                  const Center(child: VyroLogo(size: 84))
                      .animate()
                      .fadeIn(duration: 600.ms)
                      .scale(duration: 600.ms, curve: Curves.elasticOut),
                  const SizedBox(height: 28),
                  Text(
                    'Welcome to Vyro',
                    style: AppTheme.heroTitle.copyWith(fontSize: 30),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 100.ms),
                  const SizedBox(height: 10),
                  Text(
                    'Your premium movie & TV experience with personalized watch tracking',
                    style: AppTheme.metadata,
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 150.ms),
                  const SizedBox(height: 52),

                  // Feature highlights
                  const _FeatureItem(
                    icon: Icons.person_outline_rounded,
                    title: 'Your personal profile',
                    subtitle:
                        'Keep your watchlist and progress synced to your Google account',
                  )
                      .animate()
                      .fadeIn(delay: 220.ms, duration: 300.ms)
                      .slideX(begin: 0.06, end: 0, duration: 300.ms),
                  const SizedBox(height: 18),
                  const _FeatureItem(
                    icon: Icons.sync_alt_rounded,
                    title: 'Trakt integration',
                    subtitle:
                        'After sign-in we\'ll help you connect Trakt for watch history & scrobbling',
                  )
                      .animate()
                      .fadeIn(delay: 300.ms, duration: 300.ms)
                      .slideX(begin: 0.06, end: 0, duration: 300.ms),
                  const SizedBox(height: 18),
                  const _FeatureItem(
                    icon: Icons.devices_rounded,
                    title: 'Any device, anywhere',
                    subtitle: 'Sign in and pick up where you left off',
                  )
                      .animate()
                      .fadeIn(delay: 380.ms, duration: 300.ms)
                      .slideX(begin: 0.06, end: 0, duration: 300.ms),
                  const SizedBox(height: 60),

                  // Error
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.error.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: AppColors.error, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(_error!,
                                    style: AppTheme.metadata
                                        .copyWith(color: AppColors.error))),
                          ],
                        ),
                      ),
                    ),

                  // ── Account buttons ──────────────────────────────────
                  if (!googleOutOfReach)
                    SizedBox(
                      width: double.infinity,
                      child: _GoogleSignInButton(
                        loading: _isSigningIn,
                        autofocus: true,
                        onPressed: _isSigningIn ? null : _handleGoogleSignIn,
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 480.ms)
                        .slideY(begin: 0.08, end: 0, duration: 400.ms),

                  if (onTv) ...[
                    const SizedBox(height: 14),
                    _TvPairingButton(
                      // Where a remote starts depends on which of the two is
                      // first: on real TV hardware the pairing button is.
                      autofocus: googleOutOfReach,
                      onPressed: _isContinuingGuest || _isSigningIn
                          ? null
                          : _openTraktPairing,
                    ),
                  ],

                  const SizedBox(height: 14),

                  // ── Guest / skip sign-in button ─────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: _GuestBypassButton(
                      loading: _isContinuingGuest,
                      onPressed: _isContinuingGuest || _isSigningIn
                          ? null
                          : _handleContinueGuest,
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 540.ms)
                      .slideY(begin: 0.08, end: 0, duration: 400.ms),

                  if (googleOutOfReach) ...[
                    const SizedBox(height: 18),
                    Text(
                      'Google sign-in needs a browser or a Google account app, and a TV has neither. Pair Trakt with your phone instead, or continue as a guest and connect it later from Settings.',
                      style: AppTheme.metadata.copyWith(
                          color: AppColors.onSurfaceVariant, height: 1.45),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'By signing in you agree to our Terms & Privacy Policy',
                      style: AppTheme.metadata.copyWith(
                          color: AppColors.onSurfaceVariant, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  final bool loading;
  final bool autofocus;
  final VoidCallback? onPressed;

  const _GoogleSignInButton({
    required this.loading,
    this.autofocus = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    const fg = AppColors.white;
    const bg = AppColors.surfaceContainerLow;
    final border = Colors.white.withValues(alpha: 0.10);

    return TvButton(
      autofocus: autofocus,
      onSelect: onPressed,
      semanticLabel: 'Continue with Google',
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          side: BorderSide(color: border, width: 1),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          textStyle: AppTheme.badge.copyWith(fontSize: 15),
        ),
        icon: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: Colors.white70),
              )
            : const _GoogleLogo(),
        label: Text(loading ? 'Signing you in...' : 'Continue with Google'),
      ),
    );
  }
}

/// The one sign-in a TV remote can finish on hardware: the app shows a code,
/// the user types it on their phone. Focus is the only way onto it there, so
/// it carries the same ring the cards use.
class _TvPairingButton extends StatelessWidget {
  final bool autofocus;
  final VoidCallback? onPressed;

  const _TvPairingButton({required this.onPressed, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TvButton(
        autofocus: autofocus,
        onSelect: onPressed,
        semanticLabel: 'Pair Trakt with your phone',
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.devices_rounded, size: 18),
          label: const Text('Pair Trakt with your phone'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFED1C24),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            textStyle: AppTheme.badge.copyWith(fontSize: 15),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999)),
          ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final s = size.width / 20.0; // scale from 20x20 design

    // Blue G stub
    final pBlue = Paint()..color = const Color(0xFF4285F4);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, w, h),
      -0.6,
      1.2,
      false,
      pBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2 * s,
    );

    // Red arc
    final pRed = Paint()..color = const Color(0xFFEA4335);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, w, h),
      0.6,
      1.4,
      false,
      pRed
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2 * s,
    );

    // Yellow arc
    final pYellow = Paint()..color = const Color(0xFFFBBC04);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, w, h),
      2.0,
      1.4,
      false,
      pYellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2 * s,
    );

    // Green arc (bottom small)
    final pGreen = Paint()..color = const Color(0xFF34A853);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, w, h),
      3.4,
      1.1,
      false,
      pGreen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2 * s,
    );

    // Blue crossbar for the G
    final cross = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.45, h * 0.44, w * 0.52, h * 0.12),
        Radius.circular(1 * s));
    canvas.drawRRect(r, cross);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GuestBypassButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onPressed;

  const _GuestBypassButton({
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    const fg = AppColors.onSurfaceVariant;
    const bg = Colors.transparent;
    final border = Colors.white.withValues(alpha: 0.08);

    return TvButton(
      onSelect: onPressed,
      semanticLabel: 'Continue without signing in',
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          side: BorderSide(color: border, width: 1),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          textStyle: AppTheme.badge.copyWith(fontSize: 14),
        ),
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: AppColors.onSurfaceVariant),
              )
            : const Icon(Icons.visibility_rounded, size: 18),
        label:
            Text(loading ? 'Entering app...' : 'Continue without signing in'),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureItem({
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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primaryLight, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(title, style: AppTheme.cardTitle.copyWith(fontSize: 14)),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: AppTheme.metadata.copyWith(fontSize: 12, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}
