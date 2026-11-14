import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'trakt_service.dart';

class AuthState {
  // ── Guest Mode (bypasses Google sign-in requirement) ──
  final bool isGuest;

  // ── Google Sign-In (primary app auth) ──
  final bool isGoogleSignedIn;
  final String? googleEmail;
  final String? googleDisplayName;
  final String? googlePhotoUrl;
  final String? googleId;

  // ── Trakt Integration (secondary, post-signin) ──
  final bool isTraktConnected;
  final String? traktUsername;
  final String? traktUserSlug;
  final String? traktAvatarUrl;
  final String? traktAccessToken;

  // ── UX Flow ──
  final bool hasDismissedTraktPrompt;

  const AuthState({
    this.isGuest = false,
    this.isGoogleSignedIn = false,
    this.googleEmail,
    this.googleDisplayName,
    this.googlePhotoUrl,
    this.googleId,
    this.isTraktConnected = false,
    this.traktUsername,
    this.traktUserSlug,
    this.traktAvatarUrl,
    this.traktAccessToken,
    this.hasDismissedTraktPrompt = false,
  });

  AuthState copyWith({
    bool? isGuest,
    bool? isGoogleSignedIn,
    String? googleEmail,
    String? googleDisplayName,
    String? googlePhotoUrl,
    String? googleId,
    bool? isTraktConnected,
    String? traktUsername,
    String? traktUserSlug,
    String? traktAvatarUrl,
    String? traktAccessToken,
    bool? hasDismissedTraktPrompt,
  }) {
    return AuthState(
      isGuest: isGuest ?? this.isGuest,
      isGoogleSignedIn: isGoogleSignedIn ?? this.isGoogleSignedIn,
      googleEmail: googleEmail ?? this.googleEmail,
      googleDisplayName: googleDisplayName ?? this.googleDisplayName,
      googlePhotoUrl: googlePhotoUrl ?? this.googlePhotoUrl,
      googleId: googleId ?? this.googleId,
      isTraktConnected: isTraktConnected ?? this.isTraktConnected,
      traktUsername: traktUsername ?? this.traktUsername,
      traktUserSlug: traktUserSlug ?? this.traktUserSlug,
      traktAvatarUrl: traktAvatarUrl ?? this.traktAvatarUrl,
      traktAccessToken: traktAccessToken ?? this.traktAccessToken,
      hasDismissedTraktPrompt:
          hasDismissedTraktPrompt ?? this.hasDismissedTraktPrompt,
    );
  }
}

class AuthService extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();

  // ── Storage keys ──────────────────────────────────────────────────────
  // Guest
  static const _keyIsGuest = 'is_guest';
  // Google
  static const _keyGoogleSignedIn = 'google_signed_in';
  static const _keyGoogleEmail = 'google_email';
  static const _keyGoogleDisplayName = 'google_display_name';
  static const _keyGooglePhotoUrl = 'google_photo_url';
  static const _keyGoogleId = 'google_id';
  // Trakt
  static const _keyTraktAccessToken = 'trakt_access_token';
  static const _keyTraktRefreshToken = 'trakt_refresh_token';
  static const _keyTraktUsername = 'trakt_username';
  static const _keyTraktUserSlug = 'trakt_user_slug';
  static const _keyTraktAvatarUrl = 'trakt_avatar_url';
  // UX
  static const _keyDismissedTraktPrompt = 'dismissed_trakt_prompt';

  // Google Sign-In instance.
  // Value = client_type 3 (WEB) entry from google-services.json.
  //
  // * On Web: the google_sign_in_web plugin requires `clientId` and asserts
  //   `serverClientId == null`. Also set via <meta name="google-signin-client_id">
  //   in web/index.html as a fallback.
  // * On Android/iOS: `serverClientId` requests an idToken/serverAuthCode
  //   scoped to this client; auto-injection from google-services.json via the
  //   Google Services Gradle plugin is preferred but hardcoding here makes it
  //   work even when that injection fails.
  static const _kGoogleWebClientId =
      '190184825728-15flv3a0pt8ubcm83trsud0unspjuo68.apps.googleusercontent.com';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'profile',
    ],
    clientId: kIsWeb ? _kGoogleWebClientId : null,
    serverClientId: kIsWeb ? null : _kGoogleWebClientId,
  );

  AuthState _state = const AuthState();
  AuthState get state => _state;

  // Google getters
  bool get isGoogleSignedIn => _state.isGoogleSignedIn;
  String? get googleEmail => _state.googleEmail;
  String? get googleDisplayName => _state.googleDisplayName;
  String? get googlePhotoUrl => _state.googlePhotoUrl;
  String? get googleId => _state.googleId;

  // Guest mode
  bool get isGuest => _state.isGuest;

  // Trakt getters (backward-compat: isLoggedIn aliases isTraktConnected)
  bool get isLoggedIn => _state.isTraktConnected;
  bool get isTraktConnected => _state.isTraktConnected;
  String? get accessToken => _state.traktAccessToken;
  String? get traktAccessToken => _state.traktAccessToken;
  String? get username => _state.traktUsername;
  String? get traktUsername => _state.traktUsername;
  String? get userSlug => _state.traktUserSlug;
  String? get traktUserSlug => _state.traktUserSlug;
  String? get avatarUrl => _state.traktAvatarUrl;
  String? get traktAvatarUrl => _state.traktAvatarUrl;

  // UX flow
  bool get hasDismissedTraktPrompt => _state.hasDismissedTraktPrompt;

  // Device auth polling data
  String? _deviceCode;
  String? _userCode;
  String? _verificationUrl;
  int _pollInterval = 5;
  bool _isPolling = false;

  String? get userCode => _userCode;
  String? get verificationUrl => _verificationUrl;
  bool get isPolling => _isPolling;

  /// Android decrypts every one of these through the device KeyStore, and that
  /// can fail outright on the first launch after an update — a rotated signing
  /// key, a KeyStore the box never finished initialising, a prefs file the
  /// plugin clears and rebuilds. A store we cannot read means signed out; the
  /// normal sign-in path writes through it again.
  Future<String?> _readTolerant(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (error) {
      debugPrint('[Auth] secure storage unreadable ($key): $error');
      return null;
    }
  }

  /// Load persisted sessions for BOTH Google and Trakt on app start
  ///
  /// Every read goes through [_readTolerant]: this runs before the first frame,
  /// so an exception here leaves the app with no UI at all.
  Future<void> initialize() async {
    // Load Guest state
    final guestStr = await _readTolerant(_keyIsGuest);
    final isGuest = guestStr == 'true';

    // Load Google state
    final googleSignedInStr = await _readTolerant(_keyGoogleSignedIn);
    final isGoogleSignedIn = googleSignedInStr == 'true';
    final googleEmail = await _readTolerant(_keyGoogleEmail);
    final googleDisplayName = await _readTolerant(_keyGoogleDisplayName);
    final googlePhotoUrl = await _readTolerant(_keyGooglePhotoUrl);
    final googleId = await _readTolerant(_keyGoogleId);

    // Load Trakt state
    final traktToken = await _readTolerant(_keyTraktAccessToken);
    final isTraktConnected = traktToken != null && traktToken.isNotEmpty;
    final traktUsername = await _readTolerant(_keyTraktUsername);
    final traktUserSlug = await _readTolerant(_keyTraktUserSlug);
    final traktAvatarUrl = await _readTolerant(_keyTraktAvatarUrl);

    // Load UX flags
    final dismissedStr = await _readTolerant(_keyDismissedTraktPrompt);
    final hasDismissedTraktPrompt = dismissedStr == 'true';

    // Try silent Google sign-in to keep GoogleSignIn plugin in sync.
    // Cap at 5 s: on some devices (Play Services IPC cold-start, first boot
    // after an update) this future never resolves, which blocks main() and
    // prevents runApp() from being called — leaving the app frozen on the OS
    // splash. We trust the persisted flag regardless of the outcome.
    if (isGoogleSignedIn) {
      try {
        await _googleSignIn
            .signInSilently()
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Silent sign-in can fail or time out; we still trust our persisted state
      }
    }

    _state = AuthState(
      isGuest: isGuest,
      isGoogleSignedIn: isGoogleSignedIn,
      googleEmail: googleEmail,
      googleDisplayName: googleDisplayName,
      googlePhotoUrl: googlePhotoUrl,
      googleId: googleId,
      isTraktConnected: isTraktConnected,
      traktAccessToken: isTraktConnected ? traktToken : null,
      traktUsername: traktUsername,
      traktUserSlug: traktUserSlug,
      traktAvatarUrl: traktAvatarUrl,
      hasDismissedTraktPrompt: hasDismissedTraktPrompt,
    );
    notifyListeners();
  }

  // ─── Guest Mode Methods ──────────────────────────────────────────────────

  /// Bypass sign-in and enter the app as a guest user.
  /// Guest users can browse and play content; signing in later promotes them.
  Future<void> continueAsGuest() async {
    await _storage.write(key: _keyIsGuest, value: 'true');
    _state = _state.copyWith(isGuest: true);
    notifyListeners();
  }

  /// Exit guest mode AND clear every other auth state. Equivalent to a full
  /// sign-out that also removes the guest bypass flag.
  /// Routes the app back to the sign-in gate when the listener rebuilds.
  Future<void> exitGuestModeAndSignOut() async {
    await signOut();
  }

  // ─── Google Sign-In Methods ────────────────────────────────────────────

  /// Trigger the Google sign-in flow. Returns true if sign-in succeeded.
  Future<bool> signInWithGoogle() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        // User canceled the sign-in flow
        return false;
      }
      final GoogleSignInAuthentication auth = await account.authentication;

      // Persist Google data
      await _storage.write(key: _keyGoogleSignedIn, value: 'true');
      await _storage.write(key: _keyGoogleEmail, value: account.email);
      await _storage.write(
          key: _keyGoogleDisplayName, value: account.displayName ?? '');
      await _storage.write(
          key: _keyGooglePhotoUrl, value: account.photoUrl ?? '');
      await _storage.write(key: _keyGoogleId, value: account.id);

      // Promote: if the user was a guest, clear the guest flag now that we
      // have a real Google identity.
      await _storage.delete(key: _keyIsGuest);

      // Update state — preserve any existing Trakt state
      _state = _state.copyWith(
        isGuest: false,
        isGoogleSignedIn: true,
        googleEmail: account.email,
        googleDisplayName: account.displayName,
        googlePhotoUrl: account.photoUrl,
        googleId: account.id,
        // Reset prompt dismissal so the newly signed-in user sees the Trakt prompt
        hasDismissedTraktPrompt: false,
      );
      await _storage.write(key: _keyDismissedTraktPrompt, value: 'false');
      notifyListeners();

      debugPrint(
          'Google sign-in OK: ${account.email} (idToken exists: ${auth.idToken != null})');
      return true;
    } catch (e) {
      debugPrint('Google sign-in error: $e');
      return false;
    }
  }

  /// Sign out from Google only (keeps Trakt tokens intact, though they
  /// won't be accessible once Google state prevents app access).
  Future<void> signOutGoogle() async {
    try {
      await _googleSignIn.signOut();
      await _googleSignIn.disconnect();
    } catch (_) {}

    // Clear Google storage keys only
    await _storage.delete(key: _keyGoogleSignedIn);
    await _storage.delete(key: _keyGoogleEmail);
    await _storage.delete(key: _keyGoogleDisplayName);
    await _storage.delete(key: _keyGooglePhotoUrl);
    await _storage.delete(key: _keyGoogleId);

    // Reset Google portion of state (preserve Trakt/UX in case they sign back in)
    _state = _state.copyWith(
      isGoogleSignedIn: false,
      googleEmail: null,
      googleDisplayName: null,
      googlePhotoUrl: null,
      googleId: null,
    );
    notifyListeners();
  }

  /// Remember that the user chose to skip the Trakt onboarding prompt.
  Future<void> setDismissedTraktPrompt(bool dismissed) async {
    await _storage.write(
        key: _keyDismissedTraktPrompt, value: dismissed ? 'true' : 'false');
    _state = _state.copyWith(hasDismissedTraktPrompt: dismissed);
    notifyListeners();
  }

  // ─── Trakt Device Auth (same flow, now coexists with Google) ──────────

  /// Step 1: Request a device code from Trakt
  Future<bool> startDeviceAuth() async {
    try {
      final result = await TraktService.requestDeviceCode();
      _deviceCode = result['device_code'];
      _userCode = result['user_code'];
      _verificationUrl = result['verification_url'];
      _pollInterval = result['interval'] ?? 5;
      notifyListeners();
      _pollForToken();
      return true;
    } catch (e) {
      debugPrint('Device auth error: $e');
      return false;
    }
  }

  /// Step 2: Poll Trakt until the user authorizes
  Future<void> _pollForToken() async {
    _isPolling = true;
    notifyListeners();

    for (int i = 0; i < 60; i++) {
      await Future.delayed(Duration(seconds: _pollInterval));
      if (!_isPolling) break;

      try {
        final result = await TraktService.pollDeviceToken(_deviceCode!);
        if (result != null) {
          final accessToken = result['access_token'] as String;
          final refreshToken = result['refresh_token'] as String;

          // Fetch user profile
          final profile = await TraktService.getUserProfile(accessToken);
          final username = profile?['username'] as String? ?? 'Trakt User';
          final slug = profile?['ids']?['slug'] as String? ?? '';
          final avatarUrl =
              profile?['images']?['avatar']?['full'] as String? ?? '';

          // Persist
          await _storage.write(key: _keyTraktAccessToken, value: accessToken);
          await _storage.write(key: _keyTraktRefreshToken, value: refreshToken);
          await _storage.write(key: _keyTraktUsername, value: username);
          await _storage.write(key: _keyTraktUserSlug, value: slug);
          await _storage.write(key: _keyTraktAvatarUrl, value: avatarUrl);

          // Merge Trakt state with potentially-existing Google state
          _state = _state.copyWith(
            isTraktConnected: true,
            traktAccessToken: accessToken,
            traktUsername: username,
            traktUserSlug: slug,
            traktAvatarUrl: avatarUrl,
            hasDismissedTraktPrompt: true,
          );
          await _storage.write(key: _keyDismissedTraktPrompt, value: 'true');
          _isPolling = false;
          notifyListeners();
          return;
        }
      } catch (_) {
        // 400 = waiting, 404 = expired, 410 = denied
      }
    }

    _isPolling = false;
    notifyListeners();
  }

  /// Sign out of EVERYTHING (Google + Trakt) and wipe local auth state.
  Future<void> signOut() async {
    // Revoke Trakt token if present
    if (_state.traktAccessToken != null) {
      try {
        await TraktService.revokeToken(_state.traktAccessToken!);
      } catch (_) {}
    }
    // Sign out Google
    try {
      await _googleSignIn.signOut();
      await _googleSignIn.disconnect();
    } catch (_) {}

    await _storage.deleteAll();
    _state = const AuthState();
    _isPolling = false;
    notifyListeners();
  }

  /// Sign out of Trakt only (disconnect integration, keep Google account).
  Future<void> signOutTrakt() async {
    if (_state.traktAccessToken != null) {
      try {
        await TraktService.revokeToken(_state.traktAccessToken!);
      } catch (_) {}
    }
    // Delete Trakt keys only
    await _storage.delete(key: _keyTraktAccessToken);
    await _storage.delete(key: _keyTraktRefreshToken);
    await _storage.delete(key: _keyTraktUsername);
    await _storage.delete(key: _keyTraktUserSlug);
    await _storage.delete(key: _keyTraktAvatarUrl);

    _state = _state.copyWith(
      isTraktConnected: false,
      traktAccessToken: null,
      traktUsername: null,
      traktUserSlug: null,
      traktAvatarUrl: null,
    );
    _isPolling = false;
    notifyListeners();
  }

  /// Quick demo sign-in for preview and testing without Trakt API keys.
  /// Connects a demo Trakt account without revoking / touching Google state.
  Future<void> signInWithDemo({
    String username = 'Alex Morgan',
    String slug = 'alex-morgan',
  }) async {
    const demoToken = 'trakt_demo_token_authenticated';
    const demoAvatar =
        'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=100&q=80';
    await _storage.write(key: _keyTraktAccessToken, value: demoToken);
    await _storage.write(key: _keyTraktUsername, value: username);
    await _storage.write(key: _keyTraktUserSlug, value: slug);
    await _storage.write(key: _keyTraktAvatarUrl, value: demoAvatar);

    // Preserve existing Google state; only apply Trakt demo state
    _state = _state.copyWith(
      isTraktConnected: true,
      traktAccessToken: demoToken,
      traktUsername: username,
      traktUserSlug: slug,
      traktAvatarUrl: demoAvatar,
      hasDismissedTraktPrompt: true,
    );
    await _storage.write(key: _keyDismissedTraktPrompt, value: 'true');
    _isPolling = false;
    notifyListeners();
  }

  void cancelPolling() {
    _isPolling = false;
    _userCode = null;
    _deviceCode = null;
    notifyListeners();
  }
}
