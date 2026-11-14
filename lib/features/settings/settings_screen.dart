import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/library_service.dart';
import '../../core/services/device_form.dart';
import '../../shared/widgets/tv_focus.dart';
import '../../shared/widgets/update_dialog.dart';
import '../../core/services/update_service.dart';
import '../auth/trakt_auth_screen.dart';
import 'layout_choice_prompt.dart';
import 'diagnostics_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ScrollController _scroll = ScrollController();
  bool _checkingUpdate = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        controller: _scroll,
        // A remote can only walk to switches that are already built, so TV
        // layout keeps the sections further down the page alive.
        scrollCacheExtent: ScrollCacheExtent.pixels(
          context.select((SettingsService s) => s.useTvLayout) ? 2000 : 250,
        ),
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(child: _buildAccountSection(context)),
          SliverToBoxAdapter(child: _buildPlaybackSection(context)),
          SliverToBoxAdapter(child: _buildSubtitlesSection(context)),
          SliverToBoxAdapter(child: _buildDownloadsSection(context)),
          SliverToBoxAdapter(child: _buildNotificationsSection(context)),
          SliverToBoxAdapter(child: _buildTraktSection(context)),
          SliverToBoxAdapter(child: _buildDisplaySection(context)),
          SliverToBoxAdapter(child: _buildPrivacySection(context)),
          SliverToBoxAdapter(child: _buildAboutSection(context)),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  // ─── App Bar ──────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      floating: false,
      snap: false,
      primary: true,
      backgroundColor: AppColors.background.withValues(alpha: 0.94),
      surfaceTintColor: AppColors.surfaceContainerHigh,
      scrolledUnderElevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.6),
      toolbarHeight: 60,
      titleSpacing: 0,
      leading: TvChrome(
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: TvButton(
            onSelect: () => Navigator.of(context).pop(),
            semanticLabel: 'Back',
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppColors.white, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
      title: Text('Settings',
          style: AppTheme.sectionTitle
              .copyWith(fontSize: 20, letterSpacing: -0.3)),
    );
  }

  // ─── Account ─────────────────────────────────────────────────────────────

  Widget _buildAccountSection(BuildContext context) {
    final hasGoogle =
        context.select<AuthService, bool>((a) => a.isGoogleSignedIn);
    final isGuest = context.select<AuthService, bool>((a) => a.isGuest);
    final hasTrakt =
        context.select<AuthService, bool>((a) => a.isTraktConnected);
    final photoUrl =
        context.select<AuthService, String?>((a) => a.googlePhotoUrl);
    final displayName =
        context.select<AuthService, String?>((a) => a.googleDisplayName);
    final email = context.select<AuthService, String?>((a) => a.googleEmail);

    final List<Widget> children = [];

    // Signed-in Google account header (avatar + name + email)
    if (hasGoogle) {
      children.add(_AccountHeaderTile(
        photoUrl: photoUrl,
        displayName: displayName ?? 'Vyro User',
        email: email ?? '',
      ));
      children.add(const Divider(
          height: 1, indent: 72, color: AppColors.outlineVariant));
      children.add(_SettingsTile(
        icon: Icons.workspace_premium_rounded,
        iconColor: const Color(0xFFFFD54F),
        title: 'Manage Subscription',
        subtitle: 'Premium · Renews Dec 2026',
        trailing: const Icon(Icons.open_in_new_rounded,
            color: AppColors.onSurfaceVariant, size: 18),
        onTap: () {},
      ));
    } else if (isGuest) {
      children.add(const _AccountHeaderTile(
        photoUrl: null,
        displayName: 'Browsing as Guest',
        email: 'Sign in to sync watch history & watchlist',
        isGuest: true,
      ));
      children.add(const Divider(
          height: 1, indent: 72, color: AppColors.outlineVariant));
      children.add(_GuestCtaBanner(
        onSignIn: () {
          context.read<AuthService>().exitGuestModeAndSignOut();
        },
      ));
    } else {
      children.add(_SettingsTile(
        icon: Icons.person_add_rounded,
        iconColor: AppColors.primaryLight,
        title: 'Sign In',
        subtitle: 'Sign in with Google to sync your watchlist',
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppColors.onSurfaceVariant),
        onTap: () {},
      ));
    }

    // Sign-out actions
    if (hasGoogle) {
      children.add(const Divider(
          height: 1, indent: 56, color: AppColors.outlineVariant));
      children.add(_DangerTile(
        icon: Icons.logout_rounded,
        title: 'Sign out of Vyro',
        subtitle: 'Signs out of Google and disconnects Trakt on this device',
        onTap: () => _confirmSignOutAll(context),
      ));
      if (hasTrakt) {
        children.add(_DangerTile(
          icon: Icons.link_off_rounded,
          title: 'Disconnect Trakt only',
          subtitle: 'Keep your Google account signed in on this device',
          onTap: () => _confirmDisconnectTrakt(context),
        ));
      }
    } else if (isGuest) {
      children.add(const Divider(
          height: 1, indent: 56, color: AppColors.outlineVariant));
      children.add(_DangerTile(
        icon: Icons.logout_rounded,
        title: 'Exit Guest Mode',
        subtitle: 'Return to the sign-in screen',
        onTap: () => _confirmExitGuest(context),
      ));
    }

    return _Section(
      title: 'Account',
      icon: Icons.person_rounded,
      children: children,
    );
  }

  Future<void> _confirmSignOutAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: Text('Sign out?', style: AppTheme.sectionTitle),
        content: Text(
          'You will need to sign in with Google again to use Vyro. Your Trakt data on trakt.tv will remain intact.',
          style: AppTheme.metadata,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign Out',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AuthService>().signOut();
    }
  }

  Future<void> _confirmExitGuest(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: Text('Exit Guest Mode?', style: AppTheme.sectionTitle),
        content: Text(
          'You will return to the sign-in screen. Any local browsing state is preserved.',
          style: AppTheme.metadata,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Exit', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AuthService>().exitGuestModeAndSignOut();
    }
  }

  Future<void> _confirmDisconnectTrakt(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: Text('Disconnect Trakt?', style: AppTheme.sectionTitle),
        content: Text(
          'Watch history and watchlist will stop syncing. You remain signed in with your Google account.',
          style: AppTheme.metadata,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Disconnect',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AuthService>().signOutTrakt();
    }
  }

  // ─── Playback ─────────────────────────────────────────────────────────────

  Widget _buildPlaybackSection(BuildContext context) {
    final s = context.watch<SettingsService>();
    return _Section(
      title: 'Playback',
      icon: Icons.play_circle_rounded,
      children: [
        _DropdownTile<VideoQuality>(
          icon: Icons.hd_rounded,
          title: 'Streaming Quality',
          subtitle: 'Affects data usage',
          value: s.streamQuality,
          items: videoQualityChoices
              .map((q) => DropdownMenuItem(value: q, child: Text(q.label)))
              .toList(),
          onChanged: (v) => s.setStreamQuality(v!),
        ),
        _DropdownTile<DownloadQuality>(
          icon: Icons.download_rounded,
          title: 'Download Quality',
          subtitle: 'Ask first, or pin a quality for every download',
          value: s.downloadQuality,
          items: downloadQualityChoices
              .map((q) => DropdownMenuItem(value: q, child: Text(q.label)))
              .toList(),
          onChanged: (v) => s.setDownloadQuality(v!),
        ),
        _SwitchTile(
          icon: Icons.skip_next_rounded,
          title: 'Auto-play Next Episode',
          subtitle: 'Automatically play the next episode',
          value: s.autoNextEpisode,
          onChanged: s.setAutoNextEpisode,
        ),
        _SwitchTile(
          icon: Icons.fast_forward_rounded,
          title: 'Skip Intro',
          subtitle: 'Automatically skip show intros',
          value: s.skipIntro,
          onChanged: s.setSkipIntro,
        ),
        _DropdownTile<double>(
          icon: Icons.speed_rounded,
          title: 'Default Speed',
          value: s.playbackSpeed,
          items: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
              .map((sp) => DropdownMenuItem(
                  value: sp, child: Text(sp == 1.0 ? 'Normal' : '$sp×')))
              .toList(),
          onChanged: (v) => s.setPlaybackSpeed(v!),
        ),
        _SwitchTile(
          icon: Icons.bolt_rounded,
          title: 'Quick Play',
          subtitle: 'Automatically select the fastest streaming server',
          value: s.quickPlay,
          onChanged: s.setQuickPlay,
        ),
        _DropdownTile<int>(
          icon: Icons.alt_route_rounded,
          title: 'Parallel Stream Sources',
          subtitle:
              'Higher speeds up resolution, lower saves network & battery',
          value: s.parallelSourceCount,
          items: [1, 2, 3, 4]
              .map((cnt) => DropdownMenuItem(
                  value: cnt,
                  child: Text(cnt == 1
                      ? '1 source (Sequential)'
                      : '$cnt sources (Parallel)')))
              .toList(),
          onChanged: (v) => s.setParallelSourceCount(v!),
        ),
        _SwitchTile(
          icon: Icons.picture_in_picture_alt_rounded,
          title: 'Picture-in-Picture',
          subtitle: 'Continue watching in a floating window when leaving app',
          value: s.enablePip,
          onChanged: s.setEnablePip,
        ),
        _SwitchTile(
          icon: Icons.open_in_new_rounded,
          title: 'Use External Player',
          subtitle: 'Open videos in a third-party player',
          value: s.useExternalPlayer,
          onChanged: s.setUseExternalPlayer,
        ),
      ],
    );
  }

  // ─── Subtitles ────────────────────────────────────────────────────────────

  Widget _buildSubtitlesSection(BuildContext context) {
    final s = context.watch<SettingsService>();
    return _Section(
      title: 'Subtitles',
      icon: Icons.subtitles_rounded,
      children: [
        _SwitchTile(
          icon: Icons.closed_caption_rounded,
          title: 'Show Subtitles',
          value: s.subtitlesEnabled,
          onChanged: s.setSubtitlesEnabled,
        ),
        _DropdownTile<String>(
          icon: Icons.language_rounded,
          title: 'Subtitle Language',
          value: s.subtitleLanguage,
          items: [
            'English',
            'Spanish',
            'French',
            'German',
            'Japanese',
            'Arabic'
          ].map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
          onChanged: (v) => s.setSubtitleLanguage(v!),
        ),
        _DropdownTile<SubtitleSize>(
          icon: Icons.format_size_rounded,
          title: 'Subtitle Size',
          value: s.subtitleSize,
          items: SubtitleSize.values
              .map((sz) => DropdownMenuItem(value: sz, child: Text(sz.label)))
              .toList(),
          onChanged: (v) => s.setSubtitleSize(v!),
        ),
      ],
    );
  }

  // ─── Downloads ────────────────────────────────────────────────────────────

  Widget _buildDownloadsSection(BuildContext context) {
    final s = context.watch<SettingsService>();
    return _Section(
      title: 'Downloads',
      icon: Icons.download_rounded,
      children: [
        _SwitchTile(
          icon: Icons.wifi_rounded,
          title: 'Download on Wi-Fi Only',
          subtitle: 'Prevent downloads using mobile data',
          value: s.downloadOnWifiOnly,
          onChanged: s.setDownloadOnWifiOnly,
        ),
        _SwitchTile(
          icon: Icons.queue_play_next_rounded,
          title: 'Auto-download Next Episode',
          subtitle: 'Pre-download while watching',
          value: s.autoDownloadNextEpisode,
          onChanged: s.setAutoDownloadNextEpisode,
        ),
        _SwitchTile(
          icon: Icons.view_stream_rounded,
          title: 'Sequential Downloads',
          subtitle: 'Download one at a time (uses less battery)',
          value: s.sequentialDownloads,
          onChanged: s.setSequentialDownloads,
        ),
        _SliderTile(
          icon: Icons.storage_rounded,
          title: 'Max Download Storage',
          subtitle: '${s.maxStorageGB} GB',
          value: s.maxStorageGB.toDouble(),
          min: 2,
          max: 32,
          divisions: 15,
          onChanged: (v) => s.setMaxStorageGB(v.toInt()),
        ),
      ],
    );
  }

  // ─── Notifications ────────────────────────────────────────────────────────

  Widget _buildNotificationsSection(BuildContext context) {
    final s = context.watch<SettingsService>();
    return _Section(
      title: 'Notifications',
      icon: Icons.notifications_rounded,
      children: [
        _SwitchTile(
          icon: Icons.notifications_active_rounded,
          title: 'Enable Notifications',
          subtitle: 'Master switch for the in-app notification center',
          value: s.notificationsEnabled,
          onChanged: s.setNotificationsEnabled,
        ),
        if (s.notificationsEnabled) ...[
          _SwitchTile(
            icon: Icons.movie_rounded,
            title: 'New Movie Releases',
            value: s.notifyNewMovies,
            onChanged: s.setNotifyNewMovies,
          ),
          _SwitchTile(
            icon: Icons.tv_rounded,
            title: 'New Episodes',
            value: s.notifyNewEpisodes,
            onChanged: s.setNotifyNewEpisodes,
          ),
          _SwitchTile(
            icon: Icons.new_releases_rounded,
            title: 'Premiere Reminders',
            value: s.notifyPremiere,
            onChanged: s.setNotifyPremiere,
          ),
          _SwitchTile(
            icon: Icons.download_done_rounded,
            title: 'Download Completed',
            value: s.notifyDownloads,
            onChanged: s.setNotifyDownloads,
          ),
          _SwitchTile(
            icon: Icons.bookmark_add_rounded,
            title: 'Watchlist Updates',
            value: s.notifyWatchlist,
            onChanged: s.setNotifyWatchlist,
          ),
          _SwitchTile(
            icon: Icons.play_for_work_rounded,
            title: 'Jump Back In Reminders',
            value: s.notifyContinueWatching,
            onChanged: s.setNotifyContinueWatching,
          ),
        ],
      ],
    );
  }

  // ─── Trakt ────────────────────────────────────────────────────────────────

  Future<void> _syncTraktNow(BuildContext context) async {
    final token = context.read<AuthService>().accessToken;
    final settings = context.read<SettingsService>();
    final library = context.read<LibraryService>();
    final messenger = ScaffoldMessenger.of(context);
    if (token == null) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Syncing with Trakt…')),
    );
    await library.syncFromTrakt(
      token,
      history: settings.syncWatchHistory,
      watchlist: settings.syncWatchlist,
    );
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Synced — ${library.history.length} in history, '
            '${library.continueWatching.length} in progress'),
      ),
    );
  }

  Widget _buildTraktSection(BuildContext context) {
    final s = context.watch<SettingsService>();
    final auth = context.watch<AuthService>();
    return _Section(
      title: 'Trakt Sync',
      icon: Icons.sync_rounded,
      iconColor: const Color(0xFFED1C24),
      children: [
        // Connect button — the one entry point to Trakt sign-in.
        _SettingsTile(
          icon:
              auth.isLoggedIn ? Icons.check_circle_rounded : Icons.link_rounded,
          iconColor:
              auth.isLoggedIn ? Colors.greenAccent : const Color(0xFFED1C24),
          title: auth.isLoggedIn
              ? 'Trakt: ${auth.traktUsername ?? auth.username}'
              : 'Connect Trakt Account',
          subtitle: auth.isLoggedIn
              ? 'Watch history & watchlist are syncing'
              : 'Track what you watch on trakt.tv',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (auth.isLoggedIn)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                      color: Colors.green, shape: BoxShape.circle),
                ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.onSurfaceVariant),
            ],
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider.value(
                    value: context.read<AuthService>(),
                    child: const TraktAuthScreen())),
          ),
        ),
        const Divider(height: 1, color: AppColors.outlineVariant),
        if (auth.isLoggedIn) ...[
          _SettingsTile(
            icon: Icons.sync_rounded,
            title: 'Sync Now',
            subtitle: 'Pull history, continue watching & watchlist from Trakt',
            trailing: const Icon(Icons.refresh_rounded,
                color: AppColors.onSurfaceVariant),
            onTap: () => _syncTraktNow(context),
          ),
          const Divider(height: 1, color: AppColors.outlineVariant),
          _SwitchTile(
            icon: Icons.history_rounded,
            title: 'Sync Watch History',
            subtitle: 'Pull watch history and continue-watching from Trakt',
            value: s.syncWatchHistory,
            onChanged: s.setSyncWatchHistory,
          ),
          _SwitchTile(
            icon: Icons.bookmark_rounded,
            title: 'Sync Watchlist',
            subtitle: 'Keep your watchlist in sync',
            value: s.syncWatchlist,
            onChanged: s.setSyncWatchlist,
          ),
          _SwitchTile(
            icon: Icons.play_circle_rounded,
            title: 'Scrobble Automatically',
            subtitle: 'Mark as watched when you finish',
            value: s.scrobbleAutomatically,
            onChanged: s.setScrobbleAutomatically,
          ),
        ],
      ],
    );
  }

  // ─── Display ─────────────────────────────────────────────────────────────

  static String _densityLabel(double v) {
    if (v <= -0.6) return 'Compact';
    if (v <= -0.2) return 'Semi Compact';
    if (v < 0.2) return 'Default';
    if (v < 0.6) return 'Semi Cozy';
    return 'Cozy';
  }

  Widget _buildDisplaySection(BuildContext context) {
    final s = context.watch<SettingsService>();
    return _Section(
      title: 'Display',
      icon: Icons.palette_rounded,
      children: [
        _SwitchTile(
          icon: Icons.brightness_low_rounded,
          title: 'OLED Black Mode',
          subtitle: 'True black backgrounds for OLED screens',
          value: s.useOledBlack,
          onChanged: s.setUseOledBlack,
        ),
        _SettingsTile(
          icon: Icons.dashboard_rounded,
          title: 'Interface layout',
          subtitle:
              '${s.forcedLayout?.label ?? 'Automatic'} — cards, navigation and '
              'focus are sized for it',
          trailing: const Icon(Icons.chevron_right_rounded,
              color: AppColors.onSurfaceVariant),
          onTap: () => showLayoutPicker(context),
        ),
        _SwitchTile(
          icon: Icons.label_rounded,
          title: 'Show Format Badges',
          subtitle: '4K, HDR, IMAX labels on cards',
          value: s.showBadges,
          onChanged: s.setShowBadges,
        ),
        _SwitchTile(
          icon: Icons.star_rounded,
          title: 'Show Ratings',
          subtitle: 'Display star ratings on posters',
          value: s.showRatings,
          onChanged: s.setShowRatings,
        ),
        _SwitchTile(
          icon: Icons.timer_rounded,
          title: 'Show Runtime',
          subtitle: 'Display duration on cards',
          value: s.showRuntime,
          onChanged: s.setShowRuntime,
        ),
        _DropdownTile<String>(
          icon: Icons.language_rounded,
          title: 'Content Language',
          subtitle: 'Preferred metadata language',
          value: s.contentLanguage,
          items: ['English', 'Spanish', 'French', 'German', 'Japanese']
              .map((l) => DropdownMenuItem(value: l, child: Text(l)))
              .toList(),
          onChanged: (v) => s.setContentLanguage(v!),
        ),
        const Divider(height: 1, indent: 56, color: AppColors.outlineVariant),
        _SliderTile(
          icon: Icons.crop_rounded,
          title: 'Poster Corner Radius',
          subtitle: '${s.posterRadius.toStringAsFixed(0)} px',
          value: s.posterRadius,
          min: 4,
          max: 32,
          divisions: 14,
          onChanged: s.setPosterRadius,
        ),
        _SliderTile(
          icon: Icons.density_medium_rounded,
          title: 'Content Density',
          subtitle: _densityLabel(s.densityLevel),
          value: s.densityLevel,
          min: -1.0,
          max: 1.0,
          divisions: 10,
          onChanged: s.setDensityLevel,
        ),
      ],
    );
  }

  // ─── Privacy ─────────────────────────────────────────────────────────────

  Widget _buildPrivacySection(BuildContext context) {
    final s = context.watch<SettingsService>();
    return _Section(
      title: 'Privacy',
      icon: Icons.shield_rounded,
      children: [
        _SwitchTile(
          icon: Icons.recommend_rounded,
          title: 'Personalized Recommendations',
          subtitle: 'Uses watch history to tailor content',
          value: s.personalizedRecommendations,
          onChanged: s.setPersonalizedRecommendations,
        ),
        _SwitchTile(
          icon: Icons.bug_report_rounded,
          title: 'Crash Reporting',
          subtitle: 'Save crash details to Diagnostics',
          value: s.crashReportingEnabled,
          onChanged: s.setCrashReportingEnabled,
        ),
        _SettingsTile(
          icon: Icons.delete_forever_rounded,
          iconColor: AppColors.error,
          title: 'Clear Watch History',
          subtitle: 'Remove all local watch data',
          onTap: () => _confirmClearHistory(context, s),
        ),
      ],
    );
  }

  // ─── About ───────────────────────────────────────────────────────────────

  Future<void> _checkForUpdates() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final update = await UpdateService.check(
        timeout: const Duration(seconds: 10),
      );
      if (!mounted) return;
      if (update == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Vyro is up to date.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      } else {
        await showAppUpdateDialog(context, update);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not reach the update server.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Widget _buildAboutSection(BuildContext context) {
    return _Section(
      title: 'About',
      icon: Icons.info_rounded,
      children: [
        _SettingsTile(
          icon: Icons.description_rounded,
          title: 'Terms of Service',
          trailing: const Icon(Icons.open_in_new_rounded,
              size: 16, color: AppColors.onSurfaceVariant),
          onTap: () {},
        ),
        _SettingsTile(
          icon: Icons.privacy_tip_rounded,
          title: 'Privacy Policy',
          trailing: const Icon(Icons.open_in_new_rounded,
              size: 16, color: AppColors.onSurfaceVariant),
          onTap: () {},
        ),
        _SettingsTile(
          icon: Icons.help_outline_rounded,
          title: 'Help & Support',
          trailing: const Icon(Icons.chevron_right_rounded,
              color: AppColors.onSurfaceVariant),
          onTap: () {},
        ),
        _SettingsTile(
          icon: Icons.star_rate_rounded,
          iconColor: const Color(0xFFFFD700),
          title: 'Rate Vyro',
          trailing: const Icon(Icons.chevron_right_rounded,
              color: AppColors.onSurfaceVariant),
          onTap: () {},
        ),
        _SettingsTile(
          icon: Icons.terminal_rounded,
          iconColor: AppColors.secondary,
          title: 'Diagnostics & Logs',
          subtitle:
              'View live resolver logs, network errors, and debug telemetry',
          trailing: const Icon(Icons.chevron_right_rounded,
              color: AppColors.onSurfaceVariant),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
            );
          },
        ),
        _SettingsTile(
          icon: Icons.system_update_rounded,
          iconColor: AppColors.primaryLight,
          title: 'Check for Updates',
          subtitle: 'Look for a newer version of Vyro on GitHub',
          trailing: _checkingUpdate
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryLight,
                  ),
                )
              : const Icon(Icons.refresh_rounded,
                  color: AppColors.onSurfaceVariant),
          onTap: _checkingUpdate ? null : _checkForUpdates,
        ),
        const _VersionTile(),
      ],
    );
  }

  // ─── Dialogs ─────────────────────────────────────────────────────────────

  void _confirmClearHistory(BuildContext context, SettingsService s) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: Text('Clear Watch History?', style: AppTheme.sectionTitle),
        content: Text(
          'This will remove all local watch progress. This cannot be undone.',
          style: AppTheme.metadata,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              s.resetAll();
            },
            child:
                const Text('Clear', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable setting widgets ─────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? iconColor;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.icon,
    this.iconColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor ?? AppColors.primaryLight, size: 16),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: AppTheme.badge.copyWith(
                    color: iconColor ?? AppColors.primaryLight,
                    letterSpacing: 1.2),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: children.asMap().entries.map((e) {
                final isLast = e.key == children.length - 1;
                return Column(
                  children: [
                    e.value,
                    if (!isLast)
                      Divider(
                          height: 1,
                          indent: 56,
                          color:
                              AppColors.outlineVariant.withValues(alpha: 0.5)),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0);
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TvButton(
      onSelect: onTap,
      semanticLabel: title,
      borderRadius: 14,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color:
                (iconColor ?? AppColors.primaryLight).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child:
              Icon(icon, color: iconColor ?? AppColors.primaryLight, size: 18),
        ),
        title: Text(title, style: AppTheme.cardTitle.copyWith(fontSize: 14)),
        subtitle: subtitle != null
            ? Text(subtitle!, style: AppTheme.metadata.copyWith(fontSize: 12))
            : null,
        trailing: trailing,
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final void Function(bool) onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TvButton(
      onSelect: () => onChanged(!value),
      semanticLabel: '$title, ${value ? 'on' : 'off'}',
      borderRadius: 14,
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        secondary: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primaryLight, size: 18),
        ),
        title: Text(title, style: AppTheme.cardTitle.copyWith(fontSize: 14)),
        subtitle: subtitle != null
            ? Text(subtitle!, style: AppTheme.metadata.copyWith(fontSize: 12))
            : null,
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.primary,
        activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
      ),
    );
  }
}

class _DropdownTile<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?) onChanged;

  const _DropdownTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  String _labelOf(T? v) {
    for (final item in items) {
      if (item.value == v) {
        final child = item.child;
        return child is Text ? (child.data ?? '$v') : '$v';
      }
    }
    return '$v';
  }

  /// The choices sheet. A bare [DropdownButton] never receives the D-pad ring,
  /// so on a remote the row looked dead; this turns the whole tile into one
  /// focus target and lists the options as focusable rows.
  void _openChoices(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(title, style: AppTheme.sectionTitle.copyWith(fontSize: 18)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style:
                      AppTheme.metadata.copyWith(color: AppColors.primaryLight),
                ),
              ],
              const SizedBox(height: 12),
              for (final item in items)
                TvButton(
                  autofocus: item.value == value,
                  borderRadius: 12,
                  semanticLabel: _labelOf(item.value),
                  onSelect: () {
                    Navigator.pop(ctx);
                    onChanged(item.value);
                  },
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _labelOf(item.value),
                      style: AppTheme.cardTitle.copyWith(fontSize: 15),
                    ),
                    trailing: item.value == value
                        ? const Icon(Icons.check_rounded,
                            color: AppColors.primaryLight)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      onChanged(item.value);
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = _labelOf(value);
    return TvButton(
      onSelect: () => _openChoices(context),
      semanticLabel: '$title: $label',
      borderRadius: 14,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primaryLight, size: 18),
        ),
        title: Text(title, style: AppTheme.cardTitle.copyWith(fontSize: 14)),
        subtitle: subtitle != null
            ? Text(subtitle!, style: AppTheme.metadata.copyWith(fontSize: 12))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: AppTheme.cardTitle.copyWith(fontSize: 13),
                overflow: TextOverflow.ellipsis),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.onSurfaceVariant),
          ],
        ),
        onTap: () => _openChoices(context),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final void Function(double) onChanged;

  const _SliderTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  double get _step =>
      divisions > 0 ? (max - min) / divisions : (max - min) / 20;

  void _nudge(double delta) {
    final next = (value + delta).clamp(min, max);
    final snapped =
        divisions > 0 ? min + ((next - min) / _step).round() * _step : next;
    final clamped = snapped.clamp(min, max).toDouble();
    if ((clamped - value).abs() > 0.0001) onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primaryLight, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: AppTheme.cardTitle.copyWith(fontSize: 14)),
                    ),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: AppTheme.metadata.copyWith(
                              fontSize: 12, color: AppColors.primaryLight)),
                  ],
                ),
                SliderTheme(
                  data: const SliderThemeData(
                    trackHeight: 2,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: AppColors.outlineVariant,
                    thumbColor: AppColors.primary,
                  ),
                  child: Slider(
                    value: value,
                    min: min,
                    max: max,
                    divisions: divisions,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // The Slider's own focus node draws no ring and swallows the D-pad, so the
    // row becomes the focus target: Left/Right adjusts the value in place.
    return TvFocusable(
      borderRadius: 14,
      semanticLabel: subtitle == null ? title : '$title, $subtitle',
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _nudge(_step);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _nudge(-_step);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ExcludeFocusTraversal(child: content),
    );
  }
}

class _VersionTile extends StatefulWidget {
  const _VersionTile();

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Vyro', style: AppTheme.cardTitle.copyWith(fontSize: 14)),
              FutureBuilder<PackageInfo>(
                future: _info,
                builder: (context, snapshot) {
                  final package = snapshot.data;
                  final label = package == null
                      ? 'Version'
                      : 'Version ${package.version} (Build ${package.buildNumber})';
                  return Text(label,
                      style: AppTheme.metadata.copyWith(fontSize: 12));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Account section specific widgets ───────────────────────────────────

/// User account header: shows Google avatar + name + email. For guest users
/// it renders a generic silhouette with a "GUEST" badge instead of PREMIUM.
class _AccountHeaderTile extends StatelessWidget {
  final String? photoUrl;
  final String displayName;
  final String email;
  final bool isGuest;

  const _AccountHeaderTile({
    required this.photoUrl,
    required this.displayName,
    required this.email,
    this.isGuest = false,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor =
        isGuest ? AppColors.onSurfaceVariant : AppColors.primary;
    final badgeIcon =
        isGuest ? Icons.visibility_rounded : Icons.workspace_premium_rounded;
    final badgeLabel = isGuest ? 'GUEST' : 'PREMIUM';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accentColor, width: 2),
            ),
            child: ClipOval(
              child: (photoUrl != null && photoUrl!.isNotEmpty)
                  ? Image.network(
                      photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.surfaceContainerHigh,
                        child: const Icon(Icons.person_rounded,
                            color: AppColors.onSurfaceVariant, size: 22),
                      ),
                    )
                  : Container(
                      color:
                          accentColor.withValues(alpha: isGuest ? 0.12 : 0.2),
                      child: Icon(
                          isGuest
                              ? Icons.person_outline_rounded
                              : Icons.person_rounded,
                          color: isGuest
                              ? AppColors.onSurfaceVariant
                              : AppColors.primaryLight,
                          size: 22),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(displayName,
                    style: AppTheme.cardTitle.copyWith(fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(email,
                    style: AppTheme.metadata.copyWith(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: isGuest
                  ? null
                  : LinearGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.9),
                        AppColors.primaryLight.withValues(alpha: 0.9),
                      ],
                    ),
              color: isGuest ? AppColors.surfaceContainerHighest : null,
              border: isGuest
                  ? Border.all(color: AppColors.outlineVariant, width: 1)
                  : null,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(badgeIcon,
                    color: isGuest
                        ? AppColors.onSurfaceVariant.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.95),
                    size: 12),
                const SizedBox(width: 4),
                Text(badgeLabel,
                    style: TextStyle(
                        color: isGuest
                            ? AppColors.onSurfaceVariant.withValues(alpha: 0.9)
                            : Colors.white.withValues(alpha: 0.95),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Prominent banner shown when the user is browsing as a guest, encouraging
/// them to sign in with Google to unlock sync and watchlist.
class _GuestCtaBanner extends StatelessWidget {
  final VoidCallback onSignIn;

  const _GuestCtaBanner({required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary.withValues(alpha: 0.18),
              AppColors.primaryLight.withValues(alpha: 0.06),
            ],
          ),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      color: AppColors.primaryLight, size: 18),
                  const SizedBox(width: 8),
                  Text('Unlock the full experience',
                      style: AppTheme.cardTitle.copyWith(fontSize: 14)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in with Google to sync your watch history '
                'and watchlist across devices with Trakt.',
                style: AppTheme.metadata.copyWith(
                    fontSize: 12,
                    height: 1.45,
                    color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TvButton(
                  onSelect: onSignIn,
                  semanticLabel: 'Sign in with Google',
                  borderRadius: 12,
                  child: FilledButton.icon(
                    onPressed: onSignIn,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('Sign In with Google',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A settings tile styled as a destructive / sign-out action.
class _DangerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _DangerTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TvButton(
      onSelect: onTap,
      semanticLabel: title,
      borderRadius: 14,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.error, size: 18),
        ),
        title: Text(title,
            style: AppTheme.cardTitle
                .copyWith(fontSize: 14, color: AppColors.error)),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: AppTheme.metadata
                    .copyWith(fontSize: 12, color: AppColors.onSurfaceVariant))
            : null,
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppColors.onSurfaceVariant),
      ),
    );
  }
}
