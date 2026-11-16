import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import '../config/app_config.dart';
import 'secure_vault_storage.dart';

class BiometricLockState {
  final bool isEnabled;
  final bool isHardwareAvailable;
  final bool isCurrentlyLocked;

  const BiometricLockState({
    required this.isEnabled,
    required this.isHardwareAvailable,
    required this.isCurrentlyLocked,
  });

  BiometricLockState copyWith({
    bool? isEnabled,
    bool? isHardwareAvailable,
    bool? isCurrentlyLocked,
  }) {
    return BiometricLockState(
      isEnabled: isEnabled ?? this.isEnabled,
      isHardwareAvailable: isHardwareAvailable ?? this.isHardwareAvailable,
      isCurrentlyLocked: isCurrentlyLocked ?? this.isCurrentlyLocked,
    );
  }
}

class BiometricLockController extends StateNotifier<BiometricLockState> {
  final LocalAuthentication _localAuth;
  final SecureVaultStorage _vaultStorage;
  DateTime? _backgroundedAt;

  BiometricLockController(this._localAuth, this._vaultStorage)
      : super(const BiometricLockState(
          isEnabled: false,
          isHardwareAvailable: false,
          isCurrentlyLocked: false,
        ));

  Future<void> initialize({required bool hasActiveSession}) async {
    bool supported = false;
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      supported = canCheck || isSupported;
    } on PlatformException {
      supported = false;
    }

    final enabled = supported && await _vaultStorage.isBiometricEnabled();
    state = BiometricLockState(
      isEnabled: enabled,
      isHardwareAvailable: supported,
      isCurrentlyLocked: enabled && hasActiveSession,
    );
  }

  Future<bool> toggleBiometricLock({
    required bool enable,
    required String localizedReason,
  }) async {
    if (!state.isHardwareAvailable) return false;

    final authenticated = await authenticateUser(localizedReason: localizedReason);
    if (!authenticated) return false;

    await _vaultStorage.setBiometricEnabled(enable);
    state = state.copyWith(
      isEnabled: enable,
      isCurrentlyLocked: false,
    );
    return true;
  }

  Future<bool> authenticateUser({required String localizedReason}) async {
    try {
      final didAuth = await _localAuth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (didAuth) {
        state = state.copyWith(isCurrentlyLocked: false);
      }
      return didAuth;
    } on PlatformException {
      return false;
    }
  }

  void onAppBackgrounded() {
    if (state.isEnabled) {
      _backgroundedAt = DateTime.now();
    }
  }

  void onAppResumed({required bool hasActiveSession}) {
    if (!state.isEnabled || !hasActiveSession) return;
    final bgTime = _backgroundedAt;
    _backgroundedAt = null;
    if (bgTime != null &&
        DateTime.now().difference(bgTime) >= AppConfig.backgroundLockGracePeriod) {
      state = state.copyWith(isCurrentlyLocked: true);
    }
  }

  void clearLockOnLogout() {
    state = state.copyWith(isCurrentlyLocked: false);
  }
}

final biometricLockProvider =
    StateNotifierProvider<BiometricLockController, BiometricLockState>((ref) {
  final storage = ref.watch(secureVaultStorageProvider);
  return BiometricLockController(LocalAuthentication(), storage);
});
