import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/device_form.dart';
import '../../core/services/library_service.dart';
import '../../core/services/settings_service.dart';
import '../../shared/widgets/tv_focus.dart';
import '../../core/utils/clipboard_stub.dart'
    if (dart.library.js_interop) '../../core/utils/clipboard_web.dart';

class TraktAuthScreen extends StatefulWidget {
  const TraktAuthScreen({super.key});

  @override
  State<TraktAuthScreen> createState() => _TraktAuthScreenState();
}

class _TraktAuthScreenState extends State<TraktAuthScreen> {
  bool _isStarting = false;
  String? _error;
  bool _autoPopScheduled = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    // Auto-pop back to the previous screen shortly after a successful
    // connection so the underlying settings / home screen reflects the
    // new Trakt state without the user having to tap Back.
    if (auth.isLoggedIn && !_autoPopScheduled) {
      _autoPopScheduled = true;
      _pullLibrary();
      final nav = Navigator.of(context);
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        if (nav.canPop()) nav.pop();
      });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: TvButton(
          onSelect: () => Navigator.of(context).pop(),
          semanticLabel: 'Back',
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: Text('Connect Trakt', style: AppTheme.sectionTitle),
      ),
      body: auth.isLoggedIn
          ? _buildConnectedView(auth)
          : auth.isPolling
              ? _buildPollingView(auth)
              : _buildConnectView(auth),
    );
  }

  // ── Already connected ────────────────────────────────────────────────────

  /// Pairing only hands the device a token; without this the History tab stays
  /// as empty as it was before the account was connected.
  Future<void> _pullLibrary() async {
    final auth = context.read<AuthService>();
    final settings = context.read<SettingsService>();
    final token = auth.accessToken;
    if (token == null) return;
    await context.read<LibraryService>().syncFromTrakt(
          token,
          history: settings.syncWatchHistory,
          watchlist: settings.syncWatchlist,
        );
  }

  Widget _buildConnectedView(AuthService auth) {
    // A distinct key per phase: the three views are the same widget at the same
    // tree position, so Flutter would reuse one scroll position and the pairing
    // view would open scrolled to wherever the intro left it.
    return SingleChildScrollView(
      key: const ValueKey('traktConnected'),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Trakt logo area
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFED1C24), Color(0xFFB71C1C)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 40),
          ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
          const SizedBox(height: 20),
          Text('Connected!', style: AppTheme.heroTitle),
          const SizedBox(height: 8),
          Text(
            'Signed in as ${auth.username}',
            style:
                AppTheme.metadata.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 40),

          // Stats cards row
          _buildSyncStatusCard(),
          const SizedBox(height: 40),

          // Disconnect button
          SizedBox(
            width: double.infinity,
            child: TvButton(
              autofocus: true,
              onSelect: _confirmSignOut,
              semanticLabel: 'Disconnect Trakt account',
              child: OutlinedButton.icon(
                onPressed: _confirmSignOut,
                icon: const Icon(Icons.link_off_rounded, size: 18),
                label: const Text('Disconnect Trakt Account'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side:
                      BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncStatusCard() {
    final items = [
      {
        'icon': Icons.history_rounded,
        'label': 'Watch History',
        'status': 'Syncing'
      },
      {'icon': Icons.star_rounded, 'label': 'Ratings', 'status': 'Syncing'},
      {
        'icon': Icons.bookmark_rounded,
        'label': 'Watchlist',
        'status': 'Syncing'
      },
      {
        'icon': Icons.play_circle_rounded,
        'label': 'Scrobble',
        'status': 'Active'
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        children: items.asMap().entries.map((e) {
          final i = e.key;
          final item = e.value;
          return Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Icon(item['icon'] as IconData,
                        color: AppColors.primaryLight, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(item['label'] as String,
                          style: AppTheme.cardTitle),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        item['status'] as String,
                        style: AppTheme.badge.copyWith(
                            color: AppColors.primaryLight, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              if (i < items.length - 1)
                const Divider(height: 1, color: AppColors.outlineVariant),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ── Connect flow ─────────────────────────────────────────────────────────

  Widget _buildConnectView(AuthService auth) {
    return SingleChildScrollView(
      key: const ValueKey('traktConnect'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // Trakt branding
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFED1C24),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.movie_filter_rounded,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Trakt',
                      style: AppTheme.heroTitle.copyWith(fontSize: 24)),
                  Text('Track what you watch', style: AppTheme.metadata),
                ],
              ),
            ],
          ).animate().fadeIn(duration: 300.ms).slideX(begin: -0.1, end: 0),
          const SizedBox(height: 32),

          // Feature list
          ..._traktFeatures.asMap().entries.map((e) => _FeatureRow(
                icon: e.value['icon'] as IconData,
                title: e.value['title'] as String,
                subtitle: e.value['subtitle'] as String,
              ).animate().fadeIn(delay: Duration(milliseconds: 80 * e.key))),

          const SizedBox(height: 32),

          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.error.withValues(alpha: 0.4)),
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

          // Connect button
          SizedBox(
            width: double.infinity,
            child: TvButton(
              // A remote has no pointer: focus is the only way its OK button
              // has somewhere to land when this screen opens.
              autofocus: true,
              onSelect: _isStarting ? null : _startAuth,
              semanticLabel: 'Connect with Trakt',
              child: FilledButton.icon(
                onPressed: _isStarting ? null : _startAuth,
                icon: _isStarting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.link_rounded, size: 20),
                label:
                    Text(_isStarting ? 'Connecting...' : 'Connect with Trakt'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFED1C24),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: AppTheme.badge.copyWith(fontSize: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Demo connect button
          SizedBox(
            width: double.infinity,
            child: TvButton(
              onSelect: () => context.read<AuthService>().signInWithDemo(),
              semanticLabel: 'Connect the demo Trakt account',
              child: OutlinedButton.icon(
                onPressed: () => context.read<AuthService>().signInWithDemo(),
                icon: const Icon(Icons.auto_awesome_rounded,
                    size: 18, color: AppColors.primaryLight),
                label: const Text('Connect Demo Trakt Account'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryLight,
                  side: const BorderSide(color: AppColors.outlineVariant),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: AppTheme.badge.copyWith(fontSize: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: TvButton(
              onSelect: () => _openUrl('https://trakt.tv/join'),
              semanticLabel: 'Sign up for a Trakt account',
              child: TextButton(
                onPressed: () => _openUrl('https://trakt.tv/join'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryLight,
                  textStyle: AppTheme.metadata.copyWith(fontSize: 12),
                ),
                child: const Text("Don't have an account? Sign up free"),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Polling / waiting for user to authorize ───────────────────────────────

  void _showManualCopyDialog(BuildContext context, String code) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: const Text('Copy your code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Automatic copy is blocked by your browser. Long-press the code '
              'below to select and copy it manually.',
              style: AppTheme.metadata,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary, width: 1.5),
              ),
              child: SelectableText(
                code,
                textAlign: TextAlign.center,
                style: AppTheme.heroTitle.copyWith(
                  letterSpacing: 6,
                  fontSize: 28,
                  color: AppColors.primaryLight,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildPollingView(AuthService auth) {
    final onTv = deviceFormOf(context).isTv;

    final headline = Text('Waiting for authorization',
        style: AppTheme.sectionTitle, textAlign: TextAlign.center);
    final cancel = TvButton(
      onSelect: () => context.read<AuthService>().cancelPolling(),
      semanticLabel: 'Cancel pairing',
      child: OutlinedButton(
        onPressed: () {
          final a = context.read<AuthService>();
          a.cancelPolling();
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.onSurfaceVariant,
          side: const BorderSide(color: AppColors.outlineVariant),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        child: const Text('Cancel'),
      ),
    );

    if (onTv) {
      // Trakt's activation page signs people in with Google or a passkey, and
      // neither survives a TV browser: the account chooser never hands control
      // back. So on a TV the link is never opened here — it is handed to a
      // phone camera, where that same sign-in works.
      //
      // This view must not scroll. A TV box hands Flutter a canvas anywhere
      // from ~210 logical pixels tall (480p) to ~540 (1080p), so a layout sized
      // for one is off-screen on the other — and a QR below the fold is a
      // pairing flow with no way in. So the block is laid out at the size it
      // wants to be and the whole thing is scaled down to fit the canvas that
      // actually exists: QR, code and cancel button always arrive together.
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                headline,
                const SizedBox(height: 8),
                Text(
                    'Scan the QR with your phone, then enter the code beside it',
                    style: AppTheme.metadata,
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                _TvPairingBlock(
                  url: auth.verificationUrl ?? 'https://trakt.tv/activate',
                  code: auth.userCode ?? '------',
                  onCopy: () => _copyCode(context),
                ),
                const SizedBox(height: 20),
                cancel,
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      key: const ValueKey('traktPolling'),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFED1C24).withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFED1C24), width: 2),
            ),
            child: const Icon(Icons.devices_rounded,
                color: Color(0xFFED1C24), size: 40),
          )
              .animate(onPlay: (c) => c.repeat())
              .scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.08, 1.08),
                  duration: 800.ms,
                  curve: Curves.easeInOut)
              .then()
              .scale(
                  begin: const Offset(1.08, 1.08),
                  end: const Offset(1, 1),
                  duration: 800.ms,
                  curve: Curves.easeInOut),
          const SizedBox(height: 24),
          headline,
          const SizedBox(height: 8),
          Text(
            'Open the link below on any device and enter the code to connect Trakt',
            style: AppTheme.metadata,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          TvFocusable(
            autofocus: true,
            onSelect: () =>
                _openUrl(auth.verificationUrl ?? 'https://trakt.tv/activate'),
            semanticLabel: 'Open the activation link',
            scale: 1.02,
            borderRadius: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.open_in_new_rounded,
                      color: AppColors.primaryLight, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      auth.verificationUrl ?? 'trakt.tv/activate',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.cardTitle
                          .copyWith(color: AppColors.primaryLight),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Your activation code', style: AppTheme.metadata),
          const SizedBox(height: 10),
          _ActivationCode(
            code: auth.userCode ?? '------',
            onCopy: () => _copyCode(context),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.copy_rounded,
                  size: 14, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('Tap code to copy',
                  style: AppTheme.metadata.copyWith(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 40),
          SizedBox(width: double.infinity, child: cancel),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// A TV has no browser to hand a link to, so an unopenable URL must not
  /// break the pairing flow: the code on screen is what the user needs, and
  /// they type it on a phone anyway.
  Future<void> _openUrl(String url) async {
    try {
      final launched =
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (launched) return;
    } catch (_) {
      // Falls through to the same hint.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'This device can\'t open a browser. Enter the code on your phone '
            'at trakt.tv/activate',
            style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
          ),
          backgroundColor: AppColors.surfaceContainerHigh,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 5),
        ),
      );
  }

  Future<void> _copyCode(BuildContext ctx) async {
    final auth = ctx.read<AuthService>();
    final code = auth.userCode;
    if (code == null || code.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text(
            'No code yet — tap Connect first',
            style: TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          backgroundColor: AppColors.surfaceContainerHigh,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final ok = await copyToClipboard(code);
    if (!ctx.mounted) return;
    final messenger = ScaffoldMessenger.of(ctx);
    if (ok) {
      HapticFeedback.selectionClick();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Copied $code to clipboard',
              style:
                  AppTheme.badge.copyWith(color: AppColors.white, fontSize: 13),
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: AppColors.surfaceContainerHigh,
            behavior: SnackBarBehavior.floating,
          ),
        );
    } else {
      messenger.hideCurrentSnackBar();
      _showManualCopyDialog(ctx, code);
    }
  }

  Future<void> _startAuth() async {
    setState(() {
      _isStarting = true;
      _error = null;
    });
    final success = await context.read<AuthService>().startDeviceAuth();
    if (mounted) {
      setState(() => _isStarting = false);
      if (!success) {
        setState(() => _error =
            'Could not connect to Trakt. Check your credentials in Settings.');
      }
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: Text('Disconnect Trakt?', style: AppTheme.sectionTitle),
        content: Text(
          'Your watch history and ratings will no longer sync. Your data on Trakt will remain intact.',
          style: AppTheme.metadata,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AuthService>().signOut();
    }
  }

  static const _traktFeatures = [
    {
      'icon': Icons.history_rounded,
      'title': 'Watch History',
      'subtitle': 'Automatically track every movie and episode you watch',
    },
    {
      'icon': Icons.star_rounded,
      'title': 'Sync Ratings',
      'subtitle': 'Your ratings sync across all your devices and Trakt',
    },
    {
      'icon': Icons.bookmark_rounded,
      'title': 'Watchlist Sync',
      'subtitle': 'Add to watchlist on Trakt, watch here — stays in sync',
    },
    {
      'icon': Icons.live_tv_rounded,
      'title': 'Scrobbling',
      'subtitle': 'Automatically marks movies as watched when you finish',
    },
    {
      'icon': Icons.bar_chart_rounded,
      'title': 'Stats & Insights',
      'subtitle': 'See how much you watch, favorite genres, and more',
    },
  ];
}

/// The activation link as something a TV can actually hand to another device.
///
/// A white tile with hard square modules: a camera needs the quiet zone and a
/// plain black-on-white grid, and a themed rounded QR on a dark background is
/// the pattern phone scanners refuse to read.
/// The TV pairing block: a scannable QR beside the code you type on your
/// phone. Side by side rather than stacked because the pair has to be legible
/// in one glance from across the room, and because the stack is what pushed the
/// QR past the fold on a short TV canvas.
class _TvPairingBlock extends StatelessWidget {
  const _TvPairingBlock({
    required this.url,
    required this.code,
    required this.onCopy,
  });

  final String url;
  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ScanToActivate(url: url, showUrl: false),
          const SizedBox(width: 36),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your activation code', style: AppTheme.metadata),
              const SizedBox(height: 10),
              _ActivationCode(code: code, onCopy: onCopy, compact: true),
            ],
          ),
        ],
      );
}

class _ScanToActivate extends StatelessWidget {
  const _ScanToActivate({required this.url, this.showUrl = true});

  final String url;

  /// On a TV the code beside the QR already carries the story, and every pixel
  /// of the ~270-logical-pixel canvas a 480p box hands Flutter is scarce, so
  /// the link caption under the QR is dropped there.
  final bool showUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: QrImageView(
            data: url,
            size: 176,
            version: QrVersions.auto,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square, color: Colors.black),
            dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square, color: Colors.black),
          ),
        ),
        if (showUrl) ...[
          const SizedBox(height: 14),
          Text(url,
              textAlign: TextAlign.center,
              style:
                  AppTheme.cardTitle.copyWith(color: AppColors.primaryLight)),
          const SizedBox(height: 4),
          Text('or open it on any device',
              style: AppTheme.metadata.copyWith(fontSize: 12)),
        ],
      ],
    );
  }
}

class _ActivationCode extends StatelessWidget {
  const _ActivationCode({
    required this.code,
    required this.onCopy,
    this.compact = false,
  });

  final String code;
  final VoidCallback onCopy;

  /// Beside the QR on a TV there is room to spare horizontally but almost none
  /// vertically, so that pairing box carries a shorter type size.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onSelect: onCopy,
      semanticLabel: 'Copy activation code',
      scale: 1.02,
      borderRadius: 16,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCopy,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 24 : 32, vertical: compact ? 12 : 18),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary, width: 1.5),
          ),
          child: Text(
            code,
            textAlign: TextAlign.center,
            style: AppTheme.heroTitle.copyWith(
              letterSpacing: 8,
              fontSize: compact ? 26 : 32,
              color: AppColors.primaryLight,
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primaryLight, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.cardTitle.copyWith(fontSize: 14)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style:
                        AppTheme.metadata.copyWith(fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
