import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/config/app_config.dart';
import '../../../core/database/local_cache_db.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/network/api_client.dart';

class NotificationItemModel {
  final String id;
  final String type;
  final Map<String, String> titleByLang;
  final Map<String, String> bodyByLang;
  final String? materialCode;
  final String? deepLink;
  final DateTime createdAt;
  final bool isRead;

  const NotificationItemModel({
    required this.id,
    required this.type,
    required this.titleByLang,
    required this.bodyByLang,
    required this.createdAt,
    required this.isRead,
    this.materialCode,
    this.deepLink,
  });

  String localizedTitle(String lang) =>
      titleByLang[lang] ?? titleByLang['ar'] ?? '';
  String localizedBody(String lang) =>
      bodyByLang[lang] ?? bodyByLang['ar'] ?? '';
}

final notificationsListProvider =
    FutureProvider.autoDispose<List<NotificationItemModel>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final cacheDb = ref.watch(localCacheDbProvider);
  final readIds = await cacheDb.getReadNotificationIds();

  final res = await apiClient.dio.get<Map<String, dynamic>>('/notifications');
  final rawList = (res.data?['data'] as List<dynamic>? ?? const [])
      .cast<Map<String, dynamic>>();

  return rawList.map((json) {
    final id = (json['id'] ?? '').toString();
    final titleMap = (json['title'] as Map<String, dynamic>? ?? const {})
        .map((k, v) => MapEntry(k, v.toString()));
    final bodyMap = (json['body'] as Map<String, dynamic>? ?? const {})
        .map((k, v) => MapEntry(k, v.toString()));
    final mat = json['material'] as Map<String, dynamic>?;

    return NotificationItemModel(
      id: id,
      type: (json['type'] ?? 'SYSTEM').toString(),
      titleByLang: titleMap,
      bodyByLang: bodyMap,
      materialCode: mat?['code']?.toString(),
      deepLink: json['deepLink']?.toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      isRead: readIds.contains(id),
    );
  }).toList();
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context);
    final langCode = ref.watch(uiLocaleProvider).languageCode;
    final asyncItems = ref.watch(notificationsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.tr('notifications_title')),
      ),
      body: asyncItems.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              loc.tr('error_network'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text(
                loc.tr('notifications_empty'),
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 15),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(notificationsListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = items[index];
                final formattedDate =
                    DateFormat('yyyy-MM-dd HH:mm').format(item.createdAt.toLocal());

                return Card(
                  color: item.isRead ? Colors.white : const Color(0xFFF0FDFA),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      await ref
                          .read(localCacheDbProvider)
                          .markNotificationAsRead(item.id);
                      ref.invalidate(notificationsListProvider);
                      if (item.materialCode != null && context.mounted) {
                        context.push('/m/${item.materialCode}');
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                item.type == 'MATERIAL_UPDATED'
                                    ? Icons.system_update_alt_rounded
                                    : Icons.fiber_new_rounded,
                                color: AppTheme.primaryEmerald,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.localizedTitle(langCode),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              if (!item.isRead)
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.primaryEmerald,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.localizedBody(langCode),
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: Color(0xFF475569),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                formattedDate,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                              if (item.materialCode != null)
                                Text(
                                  '${loc.tr('btn_open_material')} (${item.materialCode}) →',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryEmerald,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
