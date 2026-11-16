import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/security/biometric_lock_service.dart';
import '../data/auth_repository.dart';

class AuthState {
  final bool isInitialized;
  final bool isAuthenticated;
  final bool isLoading;
  final String? phoneMasked;
  final String? pendingE164Phone;
  final OtpChallengeInfo? activeChallenge;
  final String? errorMessage;

  const AuthState({
    required this.isInitialized,
    required this.isAuthenticated,
    this.isLoading = false,
    this.phoneMasked,
    this.pendingE164Phone,
    this.activeChallenge,
    this.errorMessage,
  });

  factory AuthState.initial() => const AuthState(
        isInitialized: false,
        isAuthenticated: false,
      );

  AuthState copyWith({
    bool? isInitialized,
    bool? isAuthenticated,
    bool? isLoading,
    String? phoneMasked,
    String? pendingE164Phone,
    OtpChallengeInfo? activeChallenge,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      isInitialized: isInitialized ?? this.isInitialized,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      phoneMasked: phoneMasked ?? this.phoneMasked,
      pendingE164Phone: pendingE164Phone ?? this.pendingE164Phone,
      activeChallenge: activeChallenge ?? this.activeChallenge,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  final AuthRepository _repo;
  final Ref _ref;

  AuthController(this._repo, this._ref) : super(AuthState.initial()) {
    _ref.listen<int>(sessionInvalidatedCounterProvider, (_, __) {
      state = const AuthState(
        isInitialized: true,
        isAuthenticated: false,
      );
    });
  }

  Future<void> bootstrapSession() async {
    final hasSession = await _repo.hasStoredSession();
    final masked = hasSession ? await _repo.getStoredMaskedPhone() : null;

    await _ref
        .read(biometricLockProvider.notifier)
        .initialize(hasActiveSession: hasSession);

    state = AuthState(
      isInitialized: true,
      isAuthenticated: hasSession,
      phoneMasked: masked,
    );
  }

  Future<bool> sendOtp({
    required String normalizedE164Phone,
    required String langCode,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final challenge = await _repo.sendLoginOtp(
        algerianE164Phone: normalizedE164Phone,
        langCode: langCode,
      );
      state = state.copyWith(
        isLoading: false,
        pendingE164Phone: normalizedE164Phone,
        activeChallenge: challenge,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    }
  }

  Future<bool> verifyOtp({
    required String otpCode,
    required String langCode,
    String? fcmToken,
  }) async {
    final phone = state.pendingE164Phone;
    if (phone == null) return false;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final masked = await _repo.verifyLoginOtp(
        algerianE164Phone: phone,
        otpCode: otpCode,
        langCode: langCode,
        fcmToken: fcmToken,
      );
      state = AuthState(
        isInitialized: true,
        isAuthenticated: true,
        phoneMasked: masked,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    }
  }

  void updatePhoneMaskedAfterChange(String newMasked) {
    state = state.copyWith(phoneMasked: newMasked);
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    await _repo.logoutAndWipeLocalData();
    _ref.read(biometricLockProvider.notifier).clearLockOnLogout();
    state = const AuthState(
      isInitialized: true,
      isAuthenticated: false,
    );
  }

  Future<bool> deleteAccount() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repo.deleteAccountPermanently();
      _ref.read(biometricLockProvider.notifier).clearLockOnLogout();
      state = const AuthState(
        isInitialized: true,
        isAuthenticated: false,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    }
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return AuthController(repo, ref);
});
