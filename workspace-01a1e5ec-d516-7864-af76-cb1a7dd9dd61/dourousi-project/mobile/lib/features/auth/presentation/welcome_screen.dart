import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_config.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/security/secure_vault_storage.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context);
    final currentLocale = ref.watch(uiLocaleProvider);

    return Scaffold(
      backgroundColor: AppTheme.deepSlate,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Language Selector Pill (AR / FR / EN)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryEmerald.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      loc.tr('algeria_only_badge'),
                      style: const TextStyle(
                        color: Color(0xFF5EEAD4),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SegmentedButton<String>(
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: WidgetStateProperty.all(Colors.white),
                    ),
                    segments: const [
                      ButtonSegment(value: 'ar', label: Text('عربي')),
                      ButtonSegment(value: 'fr', label: Text('FR')),
                      ButtonSegment(value: 'en', label: Text('EN')),
                    ],
                    selected: {currentLocale.languageCode},
                    onSelectionChanged: (selection) {
                      final code = selection.first;
                      ref.read(uiLocaleProvider.notifier).setLanguageCode(code);
                      ref.read(secureVaultStorageProvider).setUiLanguage(code);
                    },
                  ),
                ],
              ),
              const Spacer(),
              // App Identity
              Container(
                width: 84,
                height: 84,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primaryEmerald,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: Colors.white,
                  size: 46,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                loc.tr('app_name'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                loc.tr('app_tagline'),
                style: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 32),
              _FeatureTile(
                icon: Icons.sms_outlined,
                text: loc.tr('welcome_feature_otp'),
              ),
              const SizedBox(height: 14),
              _FeatureTile(
                icon: Icons.enhanced_encryption_outlined,
                text: loc.tr('welcome_feature_drm'),
              ),
              const SizedBox(height: 14),
              _FeatureTile(
                icon: Icons.notifications_active_outlined,
                text: loc.tr('welcome_feature_updates'),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => context.go('/login'),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(loc.tr('btn_get_started')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureTile({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2DD4BF), size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFE2E8F0),
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
