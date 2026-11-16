import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/app_config.dart';
import 'core/localization/app_localizations.dart';
import 'core/router/app_router.dart';
import 'core/security/biometric_lock_service.dart';
import 'core/security/secure_vault_storage.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/notifications/presentation/push_deep_link_coordinator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final vaultStorage = SecureVaultStorage.createDefault();
  final savedLang = await vaultStorage.getUiLanguage();

  runApp(
    ProviderScope(
      overrides: [
        secureVaultStorageProvider.overrideWithValue(vaultStorage),
      ],
      child: DourousiAppBootstrap(initialLanguageCode: savedLang),
    ),
  );
}

class DourousiAppBootstrap extends ConsumerStatefulWidget {
  final String initialLanguageCode;

  const DourousiAppBootstrap({
    super.key,
    required this.initialLanguageCode,
  });

  @override
  ConsumerState<DourousiAppBootstrap> createState() =>
      _DourousiAppBootstrapState();
}

class _DourousiAppBootstrapState extends ConsumerState<DourousiAppBootstrap>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref
          .read(uiLocaleProvider.notifier)
          .setLanguageCode(widget.initialLanguageCode);
      await ref.read(authControllerProvider.notifier).bootstrapSession();
      final router = ref.read(appRouterProvider);
      await ref.read(pushAndDeepLinkCoordinatorProvider).initialize(router);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bioNotifier = ref.read(biometricLockProvider.notifier);
    final isAuthenticated = ref.read(authControllerProvider).isAuthenticated;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      bioNotifier.onAppBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      bioNotifier.onAppResumed(hasActiveSession: isAuthenticated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(uiLocaleProvider);
    final router = ref.watch(appRouterProvider);
    final authState = ref.watch(authControllerProvider);
    final bioState = ref.watch(biometricLockProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: AppConfig.appName,
      theme: AppTheme.lightTheme(),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) {
        if (!authState.isInitialized) {
          return const Scaffold(
            backgroundColor: AppTheme.deepSlate,
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.primaryEmerald),
            ),
          );
        }

        // Biometric / Face ID Privacy Shield Overlay when locked
        if (authState.isAuthenticated && bioState.isCurrentlyLocked) {
          return _BiometricShieldOverlay(
            onUnlockPressed: () {
              final loc = AppLocalizations.of(context);
              ref.read(biometricLockProvider.notifier).authenticateUser(
                    localizedReason: loc.tr('biometric_prompt_reason'),
                  );
            },
          );
        }

        return child ?? const SizedBox.shrink();
      },
    );
  }
}

class _BiometricShieldOverlay extends StatelessWidget {
  final VoidCallback onUnlockPressed;

  const _BiometricShieldOverlay({required this.onUnlockPressed});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppTheme.deepSlate,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.fingerprint_rounded,
                size: 82,
                color: Color(0xFF2DD4BF),
              ),
              const SizedBox(height: 24),
              Text(
                loc.tr('locked_screen_title'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: onUnlockPressed,
                icon: const Icon(Icons.lock_open_rounded),
                label: Text(loc.tr('btn_unlock_biometric')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
