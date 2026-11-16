import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_config.dart';
import '../../../core/localization/app_localizations.dart';
import '../domain/material_entity.dart';
import 'catalog_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context);
    final langCode = ref.watch(uiLocaleProvider).languageCode;
    final catalogState = ref.watch(catalogControllerProvider);
    final controller = ref.read(catalogControllerProvider.notifier);
    final materials = catalogState.filteredMaterials;
    final categories = catalogState.distinctCategories;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.tr('home_title')),
        actions: [
          IconButton(
            tooltip: loc.tr('notifications_title'),
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            tooltip: loc.tr('settings_title'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (catalogState.isOfflineFallback)
            Container(
              width: double.infinity,
              color: const Color(0xFFFEF3C7),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      size: 18, color: Color(0xFF92400E)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      loc.tr('error_network'),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Search Bar & Category Filter Strip
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  onChanged: controller.setSearchQuery,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: loc.tr('search_hint'),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: Text(loc.tr('filter_all')),
                        selected: catalogState.selectedCategoryPrefix == null &&
                            !catalogState.onlyDownloaded,
                        onSelected: (_) {
                          controller.selectCategory(null);
                          controller.setOnlyDownloaded(false);
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        avatar: const Icon(Icons.lock_outline, size: 16),
                        label: Text(loc.tr('filter_downloaded')),
                        selected: catalogState.onlyDownloaded,
                        onSelected: (v) => controller.setOnlyDownloaded(v),
                      ),
                      const SizedBox(width: 8),
                      for (final cat in categories) ...[
                        FilterChip(
                          label: Text(
                            '${cat.prefixCode} · ${cat.localizedName(langCode)}',
                          ),
                          selected: catalogState.selectedCategoryPrefix ==
                              cat.prefixCode,
                          onSelected: (selected) => controller.selectCategory(
                            selected ? cat.prefixCode : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Count Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${materials.length} ${loc.tr('materials_count_label')}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: controller.loadCatalog,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
              ],
            ),
          ),

          // Materials List (55+ items)
          Expanded(
            child: catalogState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: controller.loadCatalog,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: materials.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = materials[index];
                        return _MaterialCard(
                          material: item,
                          langCode: langCode,
                          onTap: () => context.push('/m/${item.code}'),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MaterialCard extends StatelessWidget {
  final MaterialEntity material;
  final String langCode;
  final VoidCallback onTap;

  const _MaterialCard({
    required this.material,
    required this.langCode,
    required this.onTap,
  });

  Color _fileTypeColor(String ext) {
    switch (ext) {
      case 'docx':
        return const Color(0xFF2563EB);
      case 'zip':
        return const Color(0xFFD97706);
      case 'pdf':
      default:
        return const Color(0xFFDC2626);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final badgeColor = _fileTypeColor(material.fileType);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.deepSlate,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      material.code,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      material.fileType.toUpperCase(),
                      style: TextStyle(
                        color: badgeColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (material.hasNewUpdateAvailable)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        loc.tr('badge_update_available'),
                        style: const TextStyle(
                          color: Color(0xFFB45309),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else if (material.isDownloaded)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFCCFBF1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_rounded,
                              size: 13, color: Color(0xFF0F766E)),
                          const SizedBox(width: 4),
                          Text(
                            loc.tr('badge_downloaded'),
                            style: const TextStyle(
                              color: Color(0xFF0F766E),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                material.title,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.deepSlate,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                material.category.localizedName(langCode),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _MetaStat(
                    icon: Icons.folder_copy_outlined,
                    text: '${material.unitsCount} ${loc.tr('units_label')}',
                  ),
                  _MetaStat(
                    icon: Icons.menu_book_outlined,
                    text: '${material.lessonsCount} ${loc.tr('lessons_label')}',
                  ),
                  _MetaStat(
                    icon: Icons.description_outlined,
                    text: '${material.filesCount} ${loc.tr('files_label')}',
                  ),
                  _MetaStat(
                    icon: Icons.sd_storage_outlined,
                    text: '${material.sizeMb} ${loc.tr('size_mb_label')}',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaStat extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaStat({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: const Color(0xFF64748B)),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12.5,
            color: Color(0xFF475569),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
