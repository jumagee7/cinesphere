import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/update_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Presents the launch-time update prompt. On Android, offers a full
/// in-app download with progress bar and direct APK install. On other
/// platforms falls back to opening the GitHub releases page.
Future<void> showAppUpdateDialog(BuildContext context, AppUpdate update) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AppUpdateDialog(update: update),
  );
}

// ─── States ───────────────────────────────────────────────────────────────────

enum _UpdateState {
  idle,
  downloading,
  downloaded,
  permissionNeeded,
  error,
}

// ─── Dialog ───────────────────────────────────────────────────────────────────

class AppUpdateDialog extends StatefulWidget {
  final AppUpdate update;

  const AppUpdateDialog({super.key, required this.update});

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  _UpdateState _state = _UpdateState.idle;
  double _progress = 0;
  String? _apkPath;
  String? _errorMessage;
  CancelToken? _cancelToken;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // The url is an APK direct-download when it ends in .apk; otherwise it
  // links to the GitHub releases page and we can't do an in-app install.
  bool get _canDownload =>
      _isAndroid && widget.update.url.toLowerCase().endsWith('.apk');

  @override
  void dispose() {
    _cancelToken?.cancel('Dialog closed');
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _startDownload() async {
    setState(() {
      _state = _UpdateState.downloading;
      _progress = 0;
      _errorMessage = null;
    });

    _cancelToken = CancelToken();

    try {
      final path = await UpdateService.downloadApk(
        widget.update.url,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        cancelToken: _cancelToken,
      );
      if (!mounted) return;
      setState(() {
        _apkPath = path;
        _state = _UpdateState.downloaded;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.type == DioExceptionType.cancel) {
        setState(() => _state = _UpdateState.idle);
      } else {
        setState(() {
          _state = _UpdateState.error;
          _errorMessage = 'Download failed: ${e.message}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _UpdateState.error;
        _errorMessage = e.toString();
      });
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel('User cancelled');
    if (mounted) setState(() => _state = _UpdateState.idle);
  }

  Future<void> _install() async {
    final path = _apkPath;
    if (path == null) return;

    final hasPermission = await UpdateService.hasInstallPermission();
    if (!mounted) return;

    if (!hasPermission) {
      setState(() => _state = _UpdateState.permissionNeeded);
      return;
    }

    try {
      await UpdateService.installApk(path);
      // The installer is now in the foreground; dismiss the dialog so it
      // isn't sitting behind the system prompt.
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _UpdateState.error;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _openPermissionSettings() async {
    await UpdateService.openInstallPermissionSettings();
    if (!mounted) return;
    // Poll until the user comes back and grants the permission, then
    // proceed straight to install.
    _waitForPermissionAndInstall();
  }

  void _waitForPermissionAndInstall() {
    Future.delayed(const Duration(milliseconds: 800), () async {
      if (!mounted) return;
      final granted = await UpdateService.hasInstallPermission();
      if (!mounted) return;
      if (granted) {
        setState(() => _state = _UpdateState.downloaded);
        await _install();
      } else {
        // Keep polling while the dialog is open.
        _waitForPermissionAndInstall();
      }
    });
  }

  Future<void> _openReleasePage() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(widget.update.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop();
    if (!launched) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open the download page. '
            'Visit ${UpdateService.repo} on GitHub.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.secondary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.system_update_rounded,
          color: AppColors.secondary,
          size: 28,
        ),
      ),
      title: Text(
        'Update available',
        style: AppTheme.sectionTitle,
        textAlign: TextAlign.center,
      ),
      content: _buildContent(),
      actions: _buildActions(),
    );
  }

  Widget _buildContent() {
    final notes = widget.update.notes.trim();
    final excerpt =
        notes.length > 600 ? '${notes.substring(0, 600).trimRight()}…' : notes;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vyro ${widget.update.version} is out'
          ' — you are on ${widget.update.currentVersion}.',
          style:
              AppTheme.metadata.copyWith(color: AppColors.onSurfaceVariant),
        ),
        if (excerpt.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.maxFinite,
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: Text(
                excerpt,
                style: AppTheme.metadata.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
        // ── Progress / status area ───────────────────────────────────────
        if (_state == _UpdateState.downloading) ...[
          const SizedBox(height: 20),
          _DownloadProgress(progress: _progress),
        ],
        if (_state == _UpdateState.downloaded) ...[
          const SizedBox(height: 16),
          _StatusRow(
            icon: Icons.check_circle_rounded,
            color: AppColors.primary,
            text: 'Download complete — ready to install.',
          ),
        ],
        if (_state == _UpdateState.permissionNeeded) ...[
          const SizedBox(height: 16),
          _StatusRow(
            icon: Icons.lock_open_rounded,
            color: const Color(0xFFFFB300),
            text: 'Allow Vyro to install apps from unknown sources in '
                'Settings, then come back here.',
          ),
        ],
        if (_state == _UpdateState.error && _errorMessage != null) ...[
          const SizedBox(height: 16),
          _StatusRow(
            icon: Icons.error_outline_rounded,
            color: AppColors.error,
            text: _errorMessage!,
          ),
        ],
      ],
    );
  }

  List<Widget> _buildActions() {
    switch (_state) {
      case _UpdateState.idle:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          if (_canDownload)
            FilledButton.icon(
              onPressed: _startDownload,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
              ),
            )
          else
            FilledButton.icon(
              onPressed: _openReleasePage,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Get update'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
              ),
            ),
        ];

      case _UpdateState.downloading:
        return [
          TextButton(
            onPressed: _cancelDownload,
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: null, // disabled while downloading
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
            ),
            child: Text('${(_progress * 100).toStringAsFixed(0)}%'),
          ),
        ];

      case _UpdateState.downloaded:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: _install,
            icon: const Icon(Icons.install_mobile_rounded, size: 18),
            label: const Text('Install now'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
            ),
          ),
        ];

      case _UpdateState.permissionNeeded:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: _openPermissionSettings,
            icon: const Icon(Icons.settings_rounded, size: 18),
            label: const Text('Open Settings'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFB300),
              foregroundColor: Colors.black,
            ),
          ),
        ];

      case _UpdateState.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () => setState(() => _state = _UpdateState.idle),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
            ),
          ),
        ];
    }
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────

class _DownloadProgress extends StatelessWidget {
  final double progress;
  const _DownloadProgress({required this.progress});

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).toStringAsFixed(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.download_rounded,
                size: 14, color: AppColors.primaryLight),
            const SizedBox(width: 6),
            Text(
              'Downloading… $pct%',
              style: AppTheme.metadata.copyWith(
                color: AppColors.primaryLight,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: AppColors.outlineVariant,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _StatusRow(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTheme.metadata.copyWith(fontSize: 12, color: color),
          ),
        ),
      ],
    );
  }
}
