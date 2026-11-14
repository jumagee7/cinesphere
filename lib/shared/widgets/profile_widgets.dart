import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/profile.dart';
import '../../core/services/profile_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../features/settings/settings_screen.dart';
import 'tv_focus.dart';

/// Circular profile avatar used across app bars. Tapping opens the profile
/// switcher sheet. Matches the visual style of the home app-bar button.
class ProfileAvatarButton extends StatelessWidget {
  final double size;

  const ProfileAvatarButton({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final profile = context.select<ProfileService, Profile>((s) => s.current);
    final color =
        HSVColor.fromAHSV(1, profile.colorSeed.toDouble(), 0.65, 0.9).toColor();
    void open() {
      HapticFeedback.selectionClick();
      showProfileSwitcher(context);
    }

    // A remote has no other way into Settings: this avatar is the only entry
    // point to the profile sheet that offers it.
    return TvFocusable(
      onSelect: open,
      semanticLabel: 'Profile',
      scale: 1.08,
      borderRadius: size / 2,
      child: GestureDetector(
        onTap: open,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.35),
                AppColors.surfaceContainerHigh,
              ],
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            profile.emoji,
            style: TextStyle(fontSize: size * 0.5),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet that lets the user switch, add, rename, or delete profiles.
Future<void> showProfileSwitcher(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceContainerHigh,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _ProfileSwitcherSheet(),
  );
}

class _ProfileSwitcherSheet extends StatefulWidget {
  const _ProfileSwitcherSheet();

  @override
  State<_ProfileSwitcherSheet> createState() => _ProfileSwitcherSheetState();
}

class _ProfileSwitcherSheetState extends State<_ProfileSwitcherSheet> {
  bool _managing = false;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ProfileService>();
    void openSettings() {
      HapticFeedback.selectionClick();
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _managing ? 'Manage profiles' : 'Who\'s watching?',
                    style: AppTheme.cardTitle.copyWith(color: Colors.white),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _managing = !_managing),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryLight,
                  ),
                  child: Text(_managing ? 'Done' : 'Manage'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    ...service.profiles.map(
                      (p) => _ProfileRow(
                        profile: p,
                        isActive: p.id == service.currentId,
                        managing: _managing,
                        canDelete: service.profiles.length > 1,
                        onTap: () async {
                          HapticFeedback.selectionClick();
                          final nav = Navigator.of(context);
                          await service.switchTo(p.id);
                          if (mounted) nav.pop();
                        },
                        onRename: () => _promptRename(context, service, p),
                        onDelete: () => _confirmDelete(context, service, p),
                        onPreferences: () =>
                            _openPreferences(context, service, p),
                      ),
                    ),
                    if (service.canAddMore)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          onPressed: () => _promptAdd(context, service),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add profile'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryLight,
                            side: const BorderSide(
                                color: AppColors.outlineVariant),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                    if (!_managing) ...[
                      const SizedBox(height: 16),
                      const Divider(color: AppColors.outlineVariant, height: 1),
                      TvButton(
                        semanticLabel: 'Settings',
                        borderRadius: 14,
                        onSelect: openSettings,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.settings_rounded,
                              color: AppColors.onSurfaceVariant),
                          title: const Text(
                            'Settings',
                            style: TextStyle(color: Colors.white),
                          ),
                          subtitle: const Text(
                            'App preferences, playback, Trakt',
                            style: TextStyle(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded,
                              color: AppColors.onSurfaceVariant),
                          onTap: openSettings,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptAdd(BuildContext context, ProfileService service) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: const Text('New profile', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Profile name',
            hintStyle: TextStyle(color: AppColors.onSurfaceVariant),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.onSurfaceVariant),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style:
                TextButton.styleFrom(foregroundColor: AppColors.primaryLight),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await service.addProfile(name: name);
    }
  }

  Future<void> _promptRename(
      BuildContext context, ProfileService service, Profile p) async {
    final controller = TextEditingController(text: p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title:
            const Text('Rename profile', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.onSurfaceVariant),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style:
                TextButton.styleFrom(foregroundColor: AppColors.primaryLight),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await service.renameProfile(p.id, name);
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, ProfileService service, Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: Text('Delete ${p.name}?',
            style: const TextStyle(color: Colors.white)),
        content: const Text(
          'This profile\'s watchlist, favorites, and history will be removed from this device. Trakt activity is not affected.',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.onSurfaceVariant),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await service.deleteProfile(p.id);
    }
  }

  Future<void> _openPreferences(
      BuildContext context, ProfileService service, Profile p) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ChangeNotifierProvider.value(
        value: service,
        child: _ProfilePreferencesSheet(profile: p),
      ),
    );
  }
}

class _ProfilePreferencesSheet extends StatefulWidget {
  final Profile profile;
  const _ProfilePreferencesSheet({required this.profile});

  @override
  State<_ProfilePreferencesSheet> createState() =>
      _ProfilePreferencesSheetState();
}

class _ProfilePreferencesSheetState extends State<_ProfilePreferencesSheet> {
  late final Set<String> _preferred = widget.profile.preferredGenres.toSet();
  late final Set<String> _blocked = widget.profile.blockedGenres.toSet();
  late String? _maturity =
      widget.profile.isKids ? 'PG' : widget.profile.maxMaturity;
  late bool _isKids = widget.profile.isKids;

  @override
  Widget build(BuildContext context) {
    final service = context.read<ProfileService>();
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.profile.name}\'s preferences',
                      style: AppTheme.cardTitle.copyWith(color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Kids profile',
                            style: TextStyle(color: Colors.white)),
                        subtitle: const Text(
                          'Restricts to G/PG and hides mature genres',
                          style: TextStyle(
                              color: AppColors.onSurfaceVariant, fontSize: 12),
                        ),
                        value: _isKids,
                        onChanged: (v) => setState(() {
                          _isKids = v;
                          if (v) _maturity = 'PG';
                        }),
                      ),
                      const SizedBox(height: 8),
                      Text('Max maturity rating',
                          style: AppTheme.metadata
                              .copyWith(color: AppColors.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChoiceChip(
                            label: 'No limit',
                            selected: _maturity == null && !_isKids,
                            enabled: !_isKids,
                            onSelected: (_) => setState(() => _maturity = null),
                          ),
                          ...Profile.maturityLadder.map(
                            (m) => _ChoiceChip(
                              label: m,
                              selected: _maturity == m,
                              enabled: !_isKids || m == 'PG' || m == 'G',
                              onSelected: (_) => setState(() => _maturity = m),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('Preferred genres',
                          style: AppTheme.metadata
                              .copyWith(color: AppColors.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      const Text(
                        'Boost these to the top of the feed',
                        style: TextStyle(
                            color: AppColors.onSurfaceVariant, fontSize: 11),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: Profile.allGenres.map((g) {
                          final isBlocked = _blocked.contains(g);
                          return _ChoiceChip(
                            label: g,
                            selected: _preferred.contains(g),
                            enabled: !isBlocked,
                            onSelected: (_) => setState(() {
                              if (_preferred.contains(g)) {
                                _preferred.remove(g);
                              } else {
                                _preferred.add(g);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      Text('Blocked genres',
                          style: AppTheme.metadata
                              .copyWith(color: AppColors.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      const Text(
                        'Never show titles in these genres',
                        style: TextStyle(
                            color: AppColors.onSurfaceVariant, fontSize: 11),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: Profile.allGenres.map((g) {
                          final isPreferred = _preferred.contains(g);
                          return _ChoiceChip(
                            label: g,
                            selected: _blocked.contains(g),
                            selectedColor:
                                AppColors.error.withValues(alpha: 0.25),
                            borderColor: AppColors.error.withValues(alpha: 0.5),
                            enabled: !isPreferred,
                            onSelected: (_) => setState(() {
                              if (_blocked.contains(g)) {
                                _blocked.remove(g);
                              } else {
                                _blocked.add(g);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    await service.updateProfile(
                      widget.profile.id,
                      isKids: _isKids,
                      preferredGenres: _preferred.toList(),
                      blockedGenres: _blocked.toList(),
                      maxMaturity: _maturity,
                      clearMaturity: _maturity == null,
                    );
                    if (mounted) nav.pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text('Save preferences'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onSelected;
  final Color? selectedColor;
  final Color? borderColor;

  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.selectedColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? (selectedColor ?? AppColors.primary.withValues(alpha: 0.25))
        : AppColors.surfaceContainerHighest;
    final border = selected
        ? (borderColor ?? AppColors.primary)
        : AppColors.outlineVariant;
    final fg = enabled
        ? (selected ? Colors.white : AppColors.onSurface)
        : AppColors.onSurfaceDisabled;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: TvFocusable(
        onSelect: enabled ? () => onSelected(!selected) : null,
        semanticLabel: label,
        enabled: enabled,
        scale: 1.06,
        borderRadius: 999,
        child: GestureDetector(
          onTap: enabled ? () => onSelected(!selected) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
            ),
            child: Text(label,
                style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400)),
          ),
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final Profile profile;
  final bool isActive;
  final bool managing;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onPreferences;

  const _ProfileRow({
    required this.profile,
    required this.isActive,
    required this.managing,
    required this.canDelete,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onPreferences,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        HSVColor.fromAHSV(1, profile.colorSeed.toDouble(), 0.65, 0.9).toColor();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          TvFocusable(
            onSelect: managing ? null : onTap,
            semanticLabel: profile.name,
            enabled: !managing,
            scale: 1.08,
            borderRadius: 22,
            child: GestureDetector(
              onTap: managing ? null : onTap,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isActive ? color : color.withValues(alpha: 0.4),
                    width: isActive ? 2.5 : 1.5,
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: isActive ? 0.5 : 0.25),
                      AppColors.surfaceContainerHighest,
                    ],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(profile.emoji,
                    style: const TextStyle(fontSize: 20)),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.cardTitle.copyWith(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (profile.isKids) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('KIDS',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryLight,
                            )),
                      ),
                    ],
                  ],
                ),
                if (isActive)
                  Text(
                    'Active now',
                    style: AppTheme.metadata.copyWith(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (managing) ...[
            IconButton(
              tooltip: 'Preferences',
              onPressed: onPreferences,
              icon: const Icon(Icons.tune_rounded,
                  color: AppColors.onSurfaceVariant, size: 20),
            ),
            IconButton(
              tooltip: 'Rename',
              onPressed: onRename,
              icon: const Icon(Icons.edit_rounded,
                  color: AppColors.onSurfaceVariant, size: 18),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: canDelete ? onDelete : null,
              icon: Icon(
                Icons.delete_outline_rounded,
                color:
                    canDelete ? AppColors.error : AppColors.onSurfaceDisabled,
                size: 20,
              ),
            ),
          ] else if (isActive)
            Icon(Icons.check_circle_rounded, color: color, size: 20),
        ],
      ),
    );
  }
}
