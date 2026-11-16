import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/local_cache_db.dart';
import '../../../core/network/api_client.dart';
import '../domain/material_entity.dart';

class CatalogRepository {
  final ApiClient _apiClient;
  final LocalCacheDb _cacheDb;

  const CatalogRepository({
    required ApiClient apiClient,
    required LocalCacheDb cacheDb,
  })  : _apiClient = apiClient,
        _cacheDb = cacheDb;

  /// Offline-first catalog fetch: syncs with server if reachable, otherwise seamlessly
  /// serves cached materials merged with locally encrypted `.drm` download statuses.
  Future<({List<MaterialEntity> materials, bool isOfflineFallback})>
      fetchMaterialsCatalog() async {
    final localMap = await _cacheDb.getAllEncryptedDownloadsByCode();

    try {
      final res = await _apiClient.dio.get<Map<String, dynamic>>('/materials');
      final rawList = (res.data?['data'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();

      await _cacheDb.cacheMaterialsJsonList(rawList);

      final items = rawList
          .map(
            (json) => MaterialEntity.fromJson(
              json,
              localDownloadRow: localMap[(json['code'] ?? '').toString()],
            ),
          )
          .toList();

      return (materials: items, isOfflineFallback: false);
    } catch (_) {
      final cachedRaw = await _cacheDb.getCachedMaterialsJsonList();
      final items = cachedRaw
          .map(
            (json) => MaterialEntity.fromJson(
              json,
              localDownloadRow: localMap[(json['code'] ?? '').toString()],
            ),
          )
          .toList();
      return (materials: items, isOfflineFallback: true);
    }
  }

  Future<MaterialEntity> fetchSingleMaterialByCodeOrId(String idOrCode) async {
    final upperCode = idOrCode.toUpperCase();
    final localMap = await _cacheDb.getAllEncryptedDownloadsByCode();

    try {
      final res = await _apiClient.dio
          .get<Map<String, dynamic>>('/materials/$idOrCode');
      final json = res.data!['data'] as Map<String, dynamic>;
      await _cacheDb.cacheMaterialsJsonList([json]);
      return MaterialEntity.fromJson(
        json,
        localDownloadRow: localMap[(json['code'] ?? upperCode).toString()],
      );
    } catch (e) {
      final cached = await _cacheDb.getCachedMaterialsJsonList();
      final match = cached.where((m) =>
          (m['code'] ?? '').toString().toUpperCase() == upperCode ||
          (m['id'] ?? '').toString() == idOrCode);
      if (match.isNotEmpty) {
        final json = match.first;
        return MaterialEntity.fromJson(
          json,
          localDownloadRow: localMap[(json['code'] ?? upperCode).toString()],
        );
      }
      throw ApiClient.mapDioError(e);
    }
  }
}

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepository(
    apiClient: ref.watch(apiClientProvider),
    cacheDb: ref.watch(localCacheDbProvider),
  );
});
