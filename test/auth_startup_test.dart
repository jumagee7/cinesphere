import 'package:cinesphere/core/services/auth_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// flutter_secure_storage's native side. On Android every read here decrypts
/// through the device KeyStore, which can fail outright on the first launch
/// after an update — and `AuthService.initialize` runs before `runApp`, so an
/// exception escaping it leaves the app with no UI at all.
const _storageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> mockStore(
      Future<Object?> Function(MethodCall call) handler) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, handler);
  }

  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, null));

  test('an unreadable secure store starts the app signed out', () async {
    var reads = 0;
    await mockStore((call) async {
      if (call.method == 'read') reads++;
      throw PlatformException(code: 'keystore_unavailable');
    });

    final auth = AuthService();
    await auth.initialize();

    expect(reads, greaterThan(0), reason: 'the reads must be the failing part');
    expect(auth.isGuest, isFalse);
    expect(auth.isGoogleSignedIn, isFalse);
    expect(auth.isTraktConnected, isFalse);
  });

  test('a session that IS readable still loads', () async {
    await mockStore((call) async {
      if (call.method != 'read') return null;
      final key = (call.arguments as Map)['key'] as String;
      return switch (key) {
        'trakt_access_token' => 'token',
        'trakt_username' => 'JumaGee',
        _ => null,
      };
    });

    final auth = AuthService();
    await auth.initialize();

    expect(auth.isTraktConnected, isTrue);
    expect(auth.traktUsername, 'JumaGee');
  });
}
