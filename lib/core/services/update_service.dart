import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// A newer build published on GitHub.
class AppUpdate {
  final String version;
  final String currentVersion;
  final String notes;
  final String url;

  const AppUpdate({
    required this.version,
    required this.currentVersion,
    required this.notes,
    required this.url,
  });
}

/// Checks GitHub for a newer Vyro build when the app starts.
///
/// The repo is public, so the anonymous API works without a token. A release
/// is the preferred source (its APK asset is handed to the browser / package
/// installer); when the repo has no release yet the version on `main` is read
/// from `pubspec.yaml` and the releases page is offered instead.
class UpdateService {
  UpdateService._();

  static const String repo = 'jumagee7/cinesphere';
  static const String _releasesLatest =
      'https://api.github.com/repos/$repo/releases/latest';
  static const String _releasesPage = 'https://github.com/$repo/releases';
  static const String _mainPubspec =
      'https://raw.githubusercontent.com/$repo/main/pubspec.yaml';

  static Future<AppUpdate?> check(
      {Duration timeout = const Duration(seconds: 8)}) async {
    final current = await _currentVersion();
    if (current == null) return null;

    final release = await _latestRelease(timeout);
    if (release != null) {
      if (!isNewer(release.$1, current)) return null;
      return AppUpdate(
        version: release.$1,
        currentVersion: current,
        notes: release.$2,
        url: release.$3,
      );
    }

    final mainVersion = await _mainVersion(timeout);
    if (mainVersion == null || !isNewer(mainVersion, current)) return null;
    return AppUpdate(
      version: mainVersion,
      currentVersion: current,
      notes: '',
      url: _releasesPage,
    );
  }

  static Future<String?> _currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      return version.isEmpty ? null : version;
    } catch (_) {
      return null;
    }
  }

  /// `(version, notes, url)` for the latest published release.
  static Future<(String, String, String)?> _latestRelease(
    Duration timeout,
  ) async {
    try {
      final res = await http.get(
        Uri.parse(_releasesLatest),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(timeout);
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['draft'] == true || json['prerelease'] == true) return null;

      final tag = (json['tag_name'] as String? ?? '').trim();
      if (tag.isEmpty) return null;

      String url = (json['html_url'] as String? ?? _releasesPage);
      final assets = (json['assets'] as List?) ?? const [];
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final download = asset['browser_download_url'] as String?;
        if (name.endsWith('.apk') && download != null && download.isNotEmpty) {
          url = download;
          // Prefer the universal / arm64 build when several are attached.
          if (name.contains('universal') || name.contains('arm64')) break;
        }
      }

      final notes = (json['body'] as String? ?? '').trim();
      return (_cleanVersion(tag), notes, url);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _mainVersion(Duration timeout) async {
    try {
      final res = await http.get(Uri.parse(_mainPubspec)).timeout(timeout);
      if (res.statusCode != 200) return null;
      final match =
          RegExp(r'^version:\s*([0-9]+(?:\.[0-9]+)*)', multiLine: true)
              .firstMatch(res.body);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  static String _cleanVersion(String raw) =>
      raw.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;

  /// Numeric semver comparison; `1.2.0` is newer than `1.1.9`.
  static bool isNewer(String latest, String current) {
    List<int> parts(String v) => _cleanVersion(v)
        .split('.')
        .map((p) => int.tryParse(RegExp(r'^\d+').stringMatch(p) ?? '') ?? 0)
        .toList();

    final a = parts(latest);
    final b = parts(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}
