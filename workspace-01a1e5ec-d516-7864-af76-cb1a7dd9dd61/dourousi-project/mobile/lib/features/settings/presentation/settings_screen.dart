import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/security/biometric_lock_service.dart';
import '../../../core/security/secure_vault_storage.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _showChangePhoneDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final loc = AppLocalizations.of(context);
    final phoneCtrl = TextEditingController();
    final otpCtrl = TextEditingController();
    bool otpSent = false;
    bool busy = false;
    String? normalizedTarget;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(loc.tr('change_phone_dialog_title')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!otpSent)
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          prefixText: '+213 ',
                          hintText: loc.tr('phone_hint'),
                          labelText: loc.tr('new_phone_label'),
                        ),
                      ),
                    )
                  else
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: TextField(
                        controller: otpCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(hintText: '••••••'),
                      ),
                    ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      dialogError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12.5),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                  child: Text(loc.tr('btn_cancel')),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(110, 42),
                  ),
                  onPressed: busy
                      ? null
                      : () async {
                          final repo = ref.read(authRepositoryProvider);
                          final lang = ref.read(uiLocaleProvider).languageCode;

                          if (!otpSent) {
                            final norm =
                                AppConfig.normalizeAlgerianMobile(phoneCtrl.text);
                            if (norm == null) {
                              setDialogState(() {
                                dialogError = loc.tr('phone_invalid_error');
                              });
                              return;
                            }
                            setDialogState(() {
                              busy = true;
                              dialogError = null;
                            });
                            try {
                              await repo.requestPhoneChangeOtp(
                                newAlgerianE164Phone: norm,
                                langCode: lang,
                              );
                              setDialogState(() {
                                normalizedTarget = norm;
                                otpSent = true;
                                busy = false;
                              });
                            } catch (e) {
                              setDialogState(() {
                                busy = false;
                                dialogError = e.toString();
                              });
                            }
                          } else {
                            if (otpCtrl.text.trim().length != 6 ||
                                normalizedTarget == null) {
                              return;
                            }
                            setDialogState(() {
                              busy = true;
                              dialogError = null;
                            });
                            try {
                              final newMasked = await repo.confirmPhoneChange(
                                newAlgerianE164Phone: normalizedTarget!,
                                otpCode: otpCtrl.text.trim(),
                              );
                              ref
                                  .read(authControllerProvider.notifier)
                                  .updatePhoneMaskedAfterChange(newMasked);
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            } catch (e) {
                              setDialogState(() {
                                busy = false;
                                dialogError = e.toString();
                              });
                            }
                          }
                        },
                  child: Text(
                    otpSent ? loc.tr('btn_confirm') : loc.tr('btn_send_otp'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showLegalSheet(BuildContext context, String title, String content) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            controller: scrollController,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Divider(height: 24),
              Text(
                content,
                style: const TextStyle(fontSize: 14.5, height: 1.65),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDestructiveAction(
    BuildContext context, {
    required String title,
    required String body,
  }) async {
    final loc = AppLocalizations.of(context);
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(loc.tr('btn_cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              minimumSize: const Size(100, 42),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.tr('btn_confirm')),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context);
    final currentLocale = ref.watch(uiLocaleProvider);
    final authState = ref.watch(authControllerProvider);
    final bioState = ref.watch(biometricLockProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.tr('settings_title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Account Section
          Text(
            loc.tr('section_account'),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.phone_android_rounded,
                      color: AppTheme.primaryEmerald),
                  title: Text(loc.tr('registered_phone')),
                  subtitle: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      authState.phoneMasked ?? '+213 *** *** **',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.swap_horiz_rounded),
                  title: Text(loc.tr('btn_change_phone')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showChangePhoneDialog(context, ref),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 2. Language & Security Section
          Text(
            loc.tr('section_security'),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.tr('language_label'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'ar', label: Text('العربية')),
                            ButtonSegment(value: 'fr', label: Text('Français')),
                            ButtonSegment(value: 'en', label: Text('English')),
                          ],
                          selected: {currentLocale.languageCode},
                          onSelectionChanged: (sel) {
                            final code = sel.first;
                            ref
                                .read(uiLocaleProvider.notifier)
                                .setLanguageCode(code);
                            ref
                                .read(secureVaultStorageProvider)
                                .setUiLanguage(code);
                            ref
                                .read(authRepositoryProvider)
                                .syncPreferences(preferredLang: code);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint_rounded,
                      color: AppTheme.primaryEmerald),
                  title: Text(loc.tr('biometric_lock_title')),
                  subtitle: Text(loc.tr('biometric_lock_subtitle')),
                  value: bioState.isEnabled,
                  onChanged: !bioState.isHardwareAvailable
                      ? null
                      : (val) {
                          ref
                              .read(biometricLockProvider.notifier)
                              .toggleBiometricLock(
                                enable: val,
                                localizedReason:
                                    loc.tr('biometric_prompt_reason'),
                              );
                        },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 3. Legal, Privacy & Developer Section ("حمزة شعيب")
          Text(
            loc.tr('section_legal_about'),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(loc.tr('privacy_policy_title')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showLegalSheet(
                    context,
                    loc.tr('privacy_policy_title'),
                    '1. لا يجمع تطبيق "دروسي" أي بيانات شخصية غير ضرورية (لا اسم، لا بريد إلكتروني، لا موقع جغرافي).\n'
                    '2. يُستخدم رقم الهاتف النقال الجزائري (+213) للتحقق لمرة واحدة عبر SMS، ويُحفظ على الخادم كبصمة مشفرة غير قابلة للعكس (HMAC-SHA256) فقط.\n'
                    '3. تُخزن رموز الجلسة ومفتاح فك التشفير المحلي داخل شريحة الأمان بالهاتف (Android Keystore / iOS Keychain).\n'
                    '4. يمكنك مسح جميع بياناتك المحلية أو حذف حسابك نهائياً في أي وقت من شاشة الإعدادات.',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.gavel_outlined),
                  title: Text(loc.tr('terms_title')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showLegalSheet(
                    context,
                    loc.tr('terms_title'),
                    '1. جميع الحقائب والمواد التدريبية (PDF / DOCX / ZIP) مخصصة للاستخدام التعليمي والتدريبي الشخصي داخل تطبيق "دروسي" فقط.\n'
                    '2. تخضع جميع الملفات المحملة لتشفير محلي (AES-256-GCM) وحماية إدارة الحقوق الرقمية (DRM) التي تمنع نسخ أو استخراج أو تصوير المحتوى خارج التطبيق.\n'
                    '3. يقتصر التسجيل والاستخدام على أرقام الهاتف النقال داخل الجمهورية الجزائرية الديمقراطية الشعبية (+213).',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.code_rounded),
                  title: Text(loc.tr('developer_label')),
                  trailing: Text(
                    loc.tr('developer_name'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text(loc.tr('app_version_label')),
                  trailing: const Text(
                    AppConfig.appVersion,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 4. Logout & Account Deletion
          OutlinedButton.icon(
            onPressed: () async {
              final confirmed = await _confirmDestructiveAction(
                context,
                title: loc.tr('btn_logout'),
                body: loc.tr('confirm_logout_desc'),
              );
              if (confirmed) {
                await ref.read(authControllerProvider.notifier).logout();
              }
            },
            icon: const Icon(Icons.logout_rounded),
            label: Text(loc.tr('btn_logout')),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () async {
              final confirmed = await _confirmDestructiveAction(
                context,
                title: loc.tr('btn_delete_account'),
                body: loc.tr('confirm_delete_desc'),
              );
              if (confirmed) {
                await ref.read(authControllerProvider.notifier).deleteAccount();
              }
            },
            icon: const Icon(Icons.person_remove_outlined,
                color: Color(0xFFDC2626)),
            label: Text(
              loc.tr('btn_delete_account'),
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
