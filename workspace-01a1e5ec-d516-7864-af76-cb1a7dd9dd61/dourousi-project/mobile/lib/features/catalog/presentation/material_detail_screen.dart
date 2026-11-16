import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../../core/localization/app_localizations.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/domain/material_entity.dart';
import '../../catalog/presentation/catalog_controller.dart';
import '../../downloads_viewer/presentation/protected_material_viewer_screen.dart';
import '../../downloads_viewer/presentation/resumable_drm_downloader.dart';

class MaterialDetailScreen extends ConsumerStatefulWidget {
  final String materialCode;

  const MaterialDetailScreen({
    super.key,
    required this.materialCode,
  });

  @override
  ConsumerState<MaterialDetailScreen> createState() =>
      _MaterialDetailScreenState();
}

class _MaterialDetailScreenState extends ConsumerState<MaterialDetailScreen> {
  MaterialEntity? _remoteFallback;
  bool _loadingSingle = false;
  String? _fetchError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureMaterialLoaded();
    });
  }

  Future<void> _ensureMaterialLoaded() async {
    final existing = _findInCatalogState();
    if (existing != null) {
      await ref
          .read(resumableDrmDownloadProvider.notifier)
          .checkPartialState(existing);
      return;
    }

    setState(() {
      _loadingSingle = true;
      _fetchError = null;
    });

    try {
      final fetched = await ref
          .read(catalogRepositoryProvider)
          .fetchSingleMaterialByCodeOrId(widget.materialCode);
      if (!mounted) return;
      setState(() {
        _remoteFallback = fetched;
        _loadingSingle = false;
      });
      await ref
          .read(resumableDrmDownloadProvider.notifier)
          .checkPartialState(fetched);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchError = e.toString();
        _loadingSingle = false;
      });
    }
  }

  MaterialEntity? _findInCatalogState() {
    final upper = widget.materialCode.toUpperCase();
    final list = ref.read(catalogControllerProvider).allMaterials;
    for (final m in list) {
      if (m.code.toUpperCase() == upper) return m;
    }
    return null;
  }

  void _openProtectedViewer(MaterialEntity material) {
    final encryptedPath = material.encryptedLocalPath;
    final dlVer = material.downloadedVersion;
    if (encryptedPath == null || dlVer == null) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProtectedMaterialViewerScreen(
          materialCode: material.code,
          materialTitle: material.title,
          fileType: material.fileType,
          encryptedFilePath: encryptedPath,
          downloadedVersion: dlVer,
          initialPage: material.lastReadPage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final langCode = ref.watch(uiLocaleProvider).languageCode;
    final catalogState = ref.watch(catalogControllerProvider);

    MaterialEntity? material;
    final upper = widget.materialCode.toUpperCase();
    for (final m in catalogState.allMaterials) {
      if (m.code.toUpperCase() == upper) {
        material = m;
        break;
      }
    }
    material ??= _remoteFallback;

    if (_loadingSingle) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.materialCode)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (material == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.materialCode)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_fetchError ?? 'Material not found'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _ensureMaterialLoaded,
                  child: Text(loc.tr('retry')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final dlStatus = ref.watch(resumableDrmDownloadProvider)[material.code] ??
        const DownloadTaskStatus();
    final dlController = ref.read(resumableDrmDownloadProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.tr('detail_title')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.deepSlate,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            material.code,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Chip(
                          label: Text(material.fileType.toUpperCase()),
                          visualDensity: VisualDensity.compact,
                        ),
                        const Spacer(),
                        Text(
                          '${loc.tr('version_label')} v${material.version}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0D9488),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      material.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.deepSlate,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      loc.tr('m91_badge'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.primaryEmerald,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${material.category.prefixCode} — ${material.category.localizedName(langCode)}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Divider(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _DetailMetric(
                          value: '${material.unitsCount}',
                          label: loc.tr('units_label'),
                        ),
                        _DetailMetric(
                          value: '${material.lessonsCount}',
                          label: loc.tr('lessons_label'),
                        ),
                        _DetailMetric(
                          value: '${material.filesCount}',
                          label: loc.tr('files_label'),
                        ),
                        _DetailMetric(
                          value: '${material.sizeMb}',
                          label: loc.tr('size_mb_label'),
                        ),
                      ],
                    ),
                    if (material.isDownloaded &&
                        material.fileType == 'pdf') ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.bookmark_outline,
                                size: 18, color: AppTheme.primaryEmerald),
                            const SizedBox(width: 8),
                            Text(
                              '${loc.tr('last_read_page')} ${material.lastReadPage} / ${material.pagesTotal}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Strict DRM Security Notice Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFCCFBF1).withOpacity(0.55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF5EEAD4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.security_rounded,
                      color: Color(0xFF0F766E), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      loc.tr('detail_drm_notice'),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF134E4A),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Resumable Download Progress Indicator
            if (dlStatus.isDownloading) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.tr('downloading_progress'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: dlStatus.progress,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(dlStatus.progress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryEmerald,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

            if (dlStatus.errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  dlStatus.errorMessage!,
                  style:
                      const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Primary Action Buttons
            if (material.isDownloaded) ...[
              ElevatedButton.icon(
                onPressed: () => _openProtectedViewer(material!),
                icon: const Icon(Icons.menu_book_rounded),
                label: Text(loc.tr('btn_open_inside_app')),
              ),
              const SizedBox(height: 12),
            ],

            if (!material.isDownloaded || material.hasNewUpdateAvailable)
              ElevatedButton.icon(
                style: material.isDownloaded
                    ? ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                      )
                    : null,
                onPressed: dlStatus.isDownloading
                    ? null
                    : () async {
                        final ok = await dlController
                            .downloadAndEncryptMaterial(material!);
                        if (ok && mounted) {
                          final refreshed = _findInCatalogState();
                          if (refreshed != null) {
                            _openProtectedViewer(refreshed);
                          }
                        }
                      },
                icon: Icon(
                  dlStatus.hasPartialResumeFile
                      ? Icons.play_arrow_rounded
                      : Icons.download_for_offline_outlined,
                ),
                label: Text(
                  dlStatus.hasPartialResumeFile
                      ? loc.tr('btn_resume_download')
                      : material.hasNewUpdateAvailable
                          ? '${loc.tr('btn_update_encrypted')} (v${material.version})'
                          : loc.tr('btn_download_encrypted'),
                ),
              ),

            if (material.isDownloaded) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: dlStatus.isDownloading
                    ? null
                    : () => dlController.deleteLocalEncryptedCopy(material!),
                icon: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFDC2626)),
                label: Text(
                  loc.tr('btn_delete_local_copy'),
                  style: const TextStyle(color: Color(0xFFDC2626)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailMetric extends StatelessWidget {
  final String value;
  final String label;

  const _DetailMetric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppTheme.deepSlate,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}
