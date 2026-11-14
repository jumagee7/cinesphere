import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/vyro_logo.dart';
import '../auth/signin_screen.dart';
import '../../app.dart';

/// Startup: the VYRO mark behaves like a projector powering up — the V draws
/// itself in emerald light, a highlight sweeps the stroke like a film scanline,
/// then the wordmark settles in.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();
    _navTimer = Timer(const Duration(milliseconds: 2700), _navigateToHome);
  }

  /// Normalised 0→1 progress for one beat of the animation.
  double _phase(double start, double end, {Curve curve = Curves.easeOutCubic}) {
    final t = ((_controller.value - start) / (end - start)).clamp(0.0, 1.0);
    return curve.transform(t);
  }

  void _navigateToHome() {
    if (!mounted) return;
    final auth = context.read<AuthService>();
    final Widget destination = (auth.isGoogleSignedIn || auth.isGuest)
        ? const AuthenticatedAppShell()
        : const SignInScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 650),
        pageBuilder: (_, animation, __) => destination,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutCubic,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Projector bloom behind the mark.
            Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, __) {
                  final glow = _phase(0.05, 0.7);
                  final scale = 0.6 + glow * 0.5;
                  return Container(
                    width: 460 * scale,
                    height: 460 * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.emerald.withValues(alpha: 0.18 * glow),
                          AppColors.deepForest.withValues(alpha: 0.06 * glow),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.45, 0.75],
                      ),
                    ),
                  );
                },
              ),
            ),
            // The mark + wordmark + tagline stack is a fixed ~225px tall; a
            // short canvas (browser window, split-screen phone) would overflow
            // it. Scale the whole lockup down rather than clipping the mark.
            Center(
              child: SafeArea(
                minimum:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        label: 'Vyro',
                        image: true,
                        child: AnimatedBuilder(
                          animation: _controller,
                          builder: (_, __) {
                            final draw = _phase(0.0, 0.34);
                            final settle = _phase(0.28, 0.6);
                            return Transform.scale(
                              scale: 0.94 + 0.06 * settle,
                              child: VyroMark(
                                size: 136,
                                draw: draw,
                                sweep: _phase(0.36, 0.72,
                                    curve: Curves.easeInOutCubic),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 26),
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (_, __) {
                          final reveal = _phase(0.5, 0.78);
                          return Opacity(
                            opacity: reveal,
                            child: Transform.translate(
                              offset: Offset(0, 10 * (1 - reveal)),
                              child: Text(
                                'VYRO',
                                style: GoogleFonts.montserrat(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 14 - 8 * reveal,
                                  color: AppColors.pureWhite,
                                  shadows: [
                                    Shadow(
                                      color: AppColors.emerald
                                          .withValues(alpha: 0.55 * reveal),
                                      blurRadius: 22,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (_, __) {
                          final reveal = _phase(0.64, 0.88);
                          return Opacity(
                            opacity: reveal,
                            child: Text(
                              'STREAM BEYOND',
                              style: GoogleFonts.montserrat(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 5.5,
                                color: AppColors.mutedSilver,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
