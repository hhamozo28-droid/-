import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/localization/app_localizations.dart';
import 'auth_controller.dart';

class OtpVerificationScreen extends ConsumerStatefulWidget {
  const OtpVerificationScreen({super.key});

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final _otpController = TextEditingController();
  Timer? _timer;
  int _remainingExpirySeconds = 300;
  int _remainingCooldownSeconds = 60;

  @override
  void initState() {
    super.initState();
    final challenge = ref.read(authControllerProvider).activeChallenge;
    _remainingExpirySeconds = challenge?.expiresInSeconds ?? 300;
    _remainingCooldownSeconds = challenge?.resendCooldownSeconds ?? 60;
    _startTimers();
  }

  void _startTimers() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remainingExpirySeconds > 0) _remainingExpirySeconds--;
        if (_remainingCooldownSeconds > 0) _remainingCooldownSeconds--;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  String _formatClock(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _submitOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6 || _remainingExpirySeconds <= 0) return;

    final langCode = ref.read(uiLocaleProvider).languageCode;
    final success = await ref.read(authControllerProvider.notifier).verifyOtp(
          otpCode: code,
          langCode: langCode,
        );

    if (success && mounted) {
      context.go('/home');
    }
  }

  Future<void> _resendOtp() async {
    final pendingPhone = ref.read(authControllerProvider).pendingE164Phone;
    if (pendingPhone == null || _remainingCooldownSeconds > 0) return;

    final langCode = ref.read(uiLocaleProvider).languageCode;
    final ok = await ref.read(authControllerProvider.notifier).sendOtp(
          normalizedE164Phone: pendingPhone,
          langCode: langCode,
        );

    if (ok && mounted) {
      final challenge = ref.read(authControllerProvider).activeChallenge;
      setState(() {
        _otpController.clear();
        _remainingExpirySeconds = challenge?.expiresInSeconds ?? 300;
        _remainingCooldownSeconds = challenge?.resendCooldownSeconds ?? 60;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final authState = ref.watch(authControllerProvider);
    final masked = authState.activeChallenge?.phoneMasked ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.tr('otp_title')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.tr('otp_sent_to'),
                style: const TextStyle(fontSize: 15, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 6),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  masked,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 12,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    hintText: '••••••',
                  ),
                  onChanged: (val) {
                    if (val.length == 6) {
                      _submitOtp();
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              // 5-Minute Expiry Countdown
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer_outlined,
                      size: 18, color: Color(0xFF0D9488)),
                  const SizedBox(width: 6),
                  Text(
                    _remainingExpirySeconds > 0
                        ? '${loc.tr('otp_expires_in')} ${_formatClock(_remainingExpirySeconds)}'
                        : loc.tr('otp_expired'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _remainingExpirySeconds > 0
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
              if (authState.errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    authState.errorMessage!,
                    style:
                        const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed:
                    (authState.isLoading || _remainingExpirySeconds <= 0)
                        ? null
                        : _submitOtp,
                child: authState.isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(loc.tr('btn_verify_otp')),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed:
                    (_remainingCooldownSeconds > 0 || authState.isLoading)
                        ? null
                        : _resendOtp,
                child: Text(
                  _remainingCooldownSeconds > 0
                      ? '${loc.tr('resend_wait')} $_remainingCooldownSeconds ${loc.tr('seconds_short')}'
                      : loc.tr('btn_resend_otp'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
