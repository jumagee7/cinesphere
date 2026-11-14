import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/update_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Presents the launch-time update prompt for a newer GitHub build.
Future<void> showAppUpdateDialog(BuildContext context, AppUpdate update) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AppUpdateDialog(update: update),
  );
}

class AppUpdateDialog extends StatelessWidget {
  final AppUpdate update;

  const AppUpdateDialog({super.key, required this.update});

  Future<void> _openRelease(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(update.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
    if (!launched) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open the download page. Visit ${UpdateService.repo} on GitHub.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = update.notes.trim();
    final excerpt =
        notes.length > 600 ? '${notes.substring(0, 600).trimRight()}…' : notes;

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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vyro ${update.version} is out — you are on ${update.currentVersion}.',
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Later'),
        ),
        FilledButton.icon(
          onPressed: () => _openRelease(context),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Update'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
