import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/local_cache_db.dart';
import '../../../core/network/api_client.dart';
import '../../../core/security/aes_drm_cipher.dart';
import '../../../core/security/secure_vault_storage.dart';

class OtpChallengeInfo {
  final String phoneMasked;
  final int expiresInSeconds;
  final int resendCooldownSeconds;

  const OtpChallengeInfo({
    required this.phoneMasked,
    required this.expiresInSeconds,
    required this.resendCooldownSeconds,
  });
}

class AuthRepository {
  final ApiClient _apiClient;
  final SecureVaultStorage _vaultStorage;
  final AesDrmCipher _drmCipher;
  final LocalCacheDb _cacheDb;

  const AuthRepository({
    required ApiClient apiClient,
    required SecureVaultStorage vaultStorage,
    required AesDrmCipher drmCipher,
    required LocalCacheDb cacheDb,
  })  : _apiClient = apiClient,
        _vaultStorage = vaultStorage,
        _drmCipher = drmCipher,
        _cacheDb = cacheDb;

  Future<bool> hasStoredSession() async {
    final token = await _vaultStorage.getAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<String?> getStoredMaskedPhone() => _vaultStorage.getPhoneMasked();

  Future<OtpChallengeInfo> sendLoginOtp({
    required String algerianE164Phone,
    required String langCode,
  }) async {
    try {
      final res = await _apiClient.dio.post<Map<String, dynamic>>(
        '/auth/send-otp',
        data: {
          'phone': algerianE164Phone,
          'lang': langCode,
        },
      );
      final data = res.data!['data'] as Map<String, dynamic>;
      return OtpChallengeInfo(
        phoneMasked: data['phoneMasked'] as String,
        expiresInSeconds: (data['expiresInSeconds'] as num).toInt(),
        resendCooldownSeconds: (data['resendCooldownSeconds'] as num).toInt(),
      );
    } catch (e) {
      throw ApiClient.mapDioError(e);
    }
  }

  Future<String> verifyLoginOtp({
    required String algerianE164Phone,
    required String otpCode,
    required String langCode,
    String? fcmToken,
  }) async {
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      final res = await _apiClient.dio.post<Map<String, dynamic>>(
        '/auth/verify-otp',
        data: {
          'phone': algerianE164Phone,
          'otp': otpCode,
          'devicePlatform': platform,
          'lang': langCode,
          if (fcmToken != null && fcmToken.isNotEmpty) 'fcmToken': fcmToken,
        },
      );

      final data = res.data!['data'] as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>;
      final phoneMasked = user['phoneMasked'] as String;

      await _vaultStorage.saveSession(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
        userId: user['id'] as String,
        phoneMasked: phoneMasked,
        preferredLang: (user['preferredLang'] ?? langCode).toString(),
      );

      // Ensure hardware-backed AES-256 master key is initialized on login
      await _vaultStorage.getOrCreateDrmMasterKey();

      return phoneMasked;
    } catch (e) {
      throw ApiClient.mapDioError(e);
    }
  }

  Future<OtpChallengeInfo> requestPhoneChangeOtp({
    required String newAlgerianE164Phone,
    required String langCode,
  }) async {
    try {
      final res = await _apiClient.dio.post<Map<String, dynamic>>(
        '/auth/change-phone/send-otp',
        data: {
          'newPhone': newAlgerianE164Phone,
          'lang': langCode,
        },
      );
      final data = res.data!['data'] as Map<String, dynamic>;
      return OtpChallengeInfo(
        phoneMasked: data['newPhoneMasked'] as String,
        expiresInSeconds: (data['expiresInSeconds'] as num).toInt(),
        resendCooldownSeconds: (data['resendCooldownSeconds'] as num).toInt(),
      );
    } catch (e) {
      throw ApiClient.mapDioError(e);
    }
  }

  Future<String> confirmPhoneChange({
    required String newAlgerianE164Phone,
    required String otpCode,
  }) async {
    try {
      final res = await _apiClient.dio.post<Map<String, dynamic>>(
        '/auth/change-phone/confirm',
        data: {
          'newPhone': newAlgerianE164Phone,
          'otp': otpCode,
        },
      );
      final data = res.data!['data'] as Map<String, dynamic>;
      final newMasked = data['phoneMasked'] as String;
      await _vaultStorage.setPhoneMasked(newMasked);
      return newMasked;
    } catch (e) {
      throw ApiClient.mapDioError(e);
    }
  }

  Future<void> syncPreferences({String? preferredLang, String? fcmToken}) async {
    try {
      await _apiClient.dio.patch<Map<String, dynamic>>(
        '/me/preferences',
        data: {
          if (preferredLang != null) 'preferredLang': preferredLang,
          if (fcmToken != null) 'fcmToken': fcmToken,
        },
      );
    } catch (_) {
      // Non-blocking preference sync
    }
  }

  /// Logs out on server AND cryptographically wipes all local encrypted files, keys & SQLite cache.
  Future<void> logoutAndWipeLocalData() async {
    try {
      await _apiClient.dio.post<Map<String, dynamic>>('/logout');
    } catch (_) {
      // Always proceed with local wipe even if offline
    } finally {
      await _drmCipher.wipeEntireVaultDirectory();
      await _cacheDb.wipeAllTables();
      await _vaultStorage.wipeAllSessionAndDrmKeys();
    }
  }

  /// Permanently deletes account on server AND wipes all local data.
  Future<void> deleteAccountPermanently() async {
    try {
      await _apiClient.dio.delete<Map<String, dynamic>>('/me');
    } catch (e) {
      throw ApiClient.mapDioError(e);
    }
    await _drmCipher.wipeEntireVaultDirectory();
    await _cacheDb.wipeAllTables();
    await _vaultStorage.wipeAllSessionAndDrmKeys();
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    apiClient: ref.watch(apiClientProvider),
    vaultStorage: ref.watch(secureVaultStorageProvider),
    drmCipher: ref.watch(aesDrmCipherProvider),
    cacheDb: ref.watch(localCacheDbProvider),
  );
});
