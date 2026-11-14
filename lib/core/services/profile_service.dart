import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/profile.dart';

/// Manages the local profiles list and which one is active. Profiles are
/// stored in SharedPreferences and are independent of Trakt auth.
class ProfileService extends ChangeNotifier {
  static const String _keyProfiles = 'profiles_list_v1';
  static const String _keyCurrent = 'profiles_current_v1';
  static const int maxProfiles = 6;

  SharedPreferences? _prefs;
  List<Profile> _profiles = [];
  String? _currentId;

  List<Profile> get profiles => List.unmodifiable(_profiles);

  Profile get current {
    final match = _profiles.where((p) => p.id == _currentId);
    return match.isNotEmpty ? match.first : _profiles.first;
  }

  String get currentId => current.id;
  bool get hasMultiple => _profiles.length > 1;
  bool get canAddMore => _profiles.length < maxProfiles;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _load();
    if (_profiles.isEmpty) {
      await _seedDefault();
    }
    notifyListeners();
  }

  Future<void> _load() async {
    final p = _prefs;
    if (p == null) return;
    final raw = p.getString(_keyProfiles);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _profiles = list
            .map((j) => Profile.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _profiles = [];
      }
    }
    _currentId = p.getString(_keyCurrent);
    if (_currentId != null && !_profiles.any((p) => p.id == _currentId)) {
      _currentId = null;
    }
  }

  Future<void> _seedDefault() async {
    final rng = Random();
    final now = DateTime.now();
    _profiles = [
      Profile(
        id: 'p_${now.microsecondsSinceEpoch}',
        name: 'You',
        colorSeed: rng.nextInt(360),
        emoji: Profile.randomEmoji(rng),
        createdAt: now,
      ),
    ];
    _currentId = _profiles.first.id;
    await _persist();
  }

  Future<void> _persist() async {
    final p = _prefs;
    if (p == null) return;
    await p.setString(
      _keyProfiles,
      jsonEncode(_profiles.map((e) => e.toJson()).toList()),
    );
    if (_currentId != null) {
      await p.setString(_keyCurrent, _currentId!);
    }
  }

  Future<void> switchTo(String profileId) async {
    if (!_profiles.any((p) => p.id == profileId)) return;
    if (_currentId == profileId) return;
    _currentId = profileId;
    await _persist();
    notifyListeners();
  }

  Future<Profile?> addProfile({
    required String name,
    String? emoji,
    int? colorSeed,
    bool isKids = false,
  }) async {
    if (!canAddMore) return null;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final rng = Random();
    final now = DateTime.now();
    final profile = Profile(
      id: 'p_${now.microsecondsSinceEpoch}',
      name: trimmed,
      colorSeed: colorSeed ?? rng.nextInt(360),
      emoji: emoji ?? Profile.randomEmoji(rng),
      isKids: isKids,
      createdAt: now,
    );
    _profiles.add(profile);
    await _persist();
    notifyListeners();
    return profile;
  }

  Future<void> renameProfile(String id, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final idx = _profiles.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _profiles[idx] = _profiles[idx].copyWith(name: trimmed);
    await _persist();
    notifyListeners();
  }

  Future<void> updateProfile(
    String id, {
    String? name,
    String? emoji,
    int? colorSeed,
    bool? isKids,
    List<String>? preferredGenres,
    List<String>? blockedGenres,
    String? maxMaturity,
    bool clearMaturity = false,
  }) async {
    final idx = _profiles.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _profiles[idx] = _profiles[idx].copyWith(
      name: name,
      emoji: emoji,
      colorSeed: colorSeed,
      isKids: isKids,
      preferredGenres: preferredGenres,
      blockedGenres: blockedGenres,
      maxMaturity: maxMaturity,
      clearMaturity: clearMaturity,
    );
    await _persist();
    notifyListeners();
  }

  Future<void> setPreferredGenres(String id, List<String> genres) =>
      updateProfile(id, preferredGenres: List.unmodifiable(genres));

  Future<void> setBlockedGenres(String id, List<String> genres) =>
      updateProfile(id, blockedGenres: List.unmodifiable(genres));

  Future<void> setMaxMaturity(String id, String? level) => level == null
      ? updateProfile(id, clearMaturity: true)
      : updateProfile(id, maxMaturity: level);

  Future<void> deleteProfile(String id) async {
    if (_profiles.length <= 1) return;
    _profiles.removeWhere((p) => p.id == id);
    if (_currentId == id) {
      _currentId = _profiles.first.id;
    }
    await _persist();
    notifyListeners();
  }
}
