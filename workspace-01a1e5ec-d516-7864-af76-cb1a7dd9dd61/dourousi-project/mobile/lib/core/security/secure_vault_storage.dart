import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Hardware-backed secure storage (Android EncryptedSharedPreferences/Keystore & iOS Keychain).
/// Holds JWT session tokens, masked phone display, biometric preference, and the per-install
/// 256-bit AES-GCM DRM Master Key used to encrypt downloaded training files inside the sandbox.
class SecureVaultStorage {
  static const _keyAccessToken = 'dourousi_access_token';
  static const _keyRefreshToken = 'dourousi_refresh_token';
  static const _keyUserId = 'dourousi_user_id';
  static const _keyPhoneMasked = 'dourousi_phone_masked';
  static const _keyUiLang = 'dourousi_ui_lang';
  static const _keyBiometricEnabled = 'dourousi_biometric_enabled';
  static const _keyAes256MasterKey = 'dourousi_drm_aes256_master_key';

  final FlutterSecureStorage _storage;

  const SecureVaultStorage(this._storage);

  factory SecureVaultStorage.createDefault() {
    const androidOptions = AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    );
    const iosOptions = IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    );
    return const SecureVaultStorage(
      FlutterSecureStorage(aOptions: androidOptions, iOptions: iosOptions),
    );
  }

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String phoneMasked,
    required String preferredLang,
  }) async {
    await Future.wait([
      _storage.write(key: _keyAccessToken, value: accessToken),
      _storage.write(key: _keyRefreshToken, value: refreshToken),
      _storage.write(key: _keyUserId, value: userId),
      _storage.write(key: _keyPhoneMasked, value: phoneMasked),
      _storage.write(key: _keyUiLang, value: preferredLang),
    ]);
  }

  Future<String?> getAccessToken() => _storage.read(key: _keyAccessToken);
  Future<String?> getRefreshToken() => _storage.read(key: _keyRefreshToken);
  Future<String?> getUserId() => _storage.read(key: _keyUserId);
  Future<String?> getPhoneMasked() => _storage.read(key: _keyPhoneMasked);

  Future<void> setPhoneMasked(String masked) =>
      _storage.write(key: _keyPhoneMasked, value: masked);

  Future<String> getUiLanguage() async {
    return (await _storage.read(key: _keyUiLang)) ?? 'ar';
  }

  Future<void> setUiLanguage(String langCode) =>
      _storage.write(key: _keyUiLang, value: langCode);

  Future<bool> isBiometricEnabled() async {
    final val = await _storage.read(key: _keyBiometricEnabled);
    return val == 'true';
  }

  Future<void> setBiometricEnabled(bool enabled) =>
      _storage.write(key: _keyBiometricEnabled, value: enabled ? 'true' : 'false');

  /// Retrieves or generates a cryptographically random 32-byte (256-bit) DRM key.
  /// Stored exclusively in hardware Keystore/Keychain; destroying it renders all
  /// encrypted local files permanently unreadable.
  Future<Uint8List> getOrCreateDrmMasterKey() async {
    final existingBase64 = await _storage.read(key: _keyAes256MasterKey);
    if (existingBase64 != null && existingBase64.isNotEmpty) {
      final decoded = base64Decode(existingBase64);
      if (decoded.length == 32) {
        return Uint8List.fromList(decoded);
      }
    }

    final rng = Random.secure();
    final keyBytes = Uint8List.fromList(
      List<int>.generate(32, (_) => rng.nextInt(256)),
    );
    await _storage.write(
      key: _keyAes256MasterKey,
      value: base64Encode(keyBytes),
    );
    return keyBytes;
  }

  /// Cryptographic erasure + session wipe upon logout or account deletion.
  Future<void> wipeAllSessionAndDrmKeys() async {
    final preservedLang = await getUiLanguage();
    await _storage.deleteAll();
    await setUiLanguage(preservedLang);
  }
}

final secureVaultStorageProvider = Provider<SecureVaultStorage>((ref) {
  return SecureVaultStorage.createDefault();
});
