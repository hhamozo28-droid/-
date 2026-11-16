import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/catalog_repository.dart';
import '../domain/material_entity.dart';

class CatalogState {
  final bool isLoading;
  final bool isOfflineFallback;
  final List<MaterialEntity> allMaterials;
  final String searchQuery;
  final String? selectedCategoryPrefix;
  final bool onlyDownloaded;
  final String? errorMessage;

  const CatalogState({
    this.isLoading = false,
    this.isOfflineFallback = false,
    this.allMaterials = const [],
    this.searchQuery = '',
    this.selectedCategoryPrefix,
    this.onlyDownloaded = false,
    this.errorMessage,
  });

  List<CategoryEntity> get distinctCategories {
    final map = <String, CategoryEntity>{};
    for (final m in allMaterials) {
      map.putIfAbsent(m.category.prefixCode, () => m.category);
    }
    final list = map.values.toList()
      ..sort((a, b) => a.prefixCode.compareTo(b.prefixCode));
    return list;
  }

  List<MaterialEntity> get filteredMaterials {
    final q = searchQuery.trim().toLowerCase();
    return allMaterials.where((m) {
      if (onlyDownloaded && !m.isDownloaded) return false;
      if (selectedCategoryPrefix != null &&
          m.category.prefixCode != selectedCategoryPrefix) {
        return false;
      }
      if (q.isNotEmpty) {
        return m.code.toLowerCase().contains(q) ||
            m.title.toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  CatalogState copyWith({
    bool? isLoading,
    bool? isOfflineFallback,
    List<MaterialEntity>? allMaterials,
    String? searchQuery,
    String? selectedCategoryPrefix,
    bool clearCategory = false,
    bool? onlyDownloaded,
    String? errorMessage,
  }) {
    return CatalogState(
      isLoading: isLoading ?? this.isLoading,
      isOfflineFallback: isOfflineFallback ?? this.isOfflineFallback,
      allMaterials: allMaterials ?? this.allMaterials,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategoryPrefix: clearCategory
          ? null
          : (selectedCategoryPrefix ?? this.selectedCategoryPrefix),
      onlyDownloaded: onlyDownloaded ?? this.onlyDownloaded,
      errorMessage: errorMessage,
    );
  }
}

class CatalogController extends StateNotifier<CatalogState> {
  final CatalogRepository _repo;

  CatalogController(this._repo) : super(const CatalogState(isLoading: true)) {
    loadCatalog();
  }

  Future<void> loadCatalog() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final result = await _repo.fetchMaterialsCatalog();
      state = state.copyWith(
        isLoading: false,
        allMaterials: result.materials,
        isOfflineFallback: result.isOfflineFallback,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void selectCategory(String? prefixCode) {
    if (prefixCode == null) {
      state = state.copyWith(clearCategory: true);
    } else {
      state = state.copyWith(selectedCategoryPrefix: prefixCode);
    }
  }

  void setOnlyDownloaded(bool value) {
    state = state.copyWith(onlyDownloaded: value);
  }
}

final catalogControllerProvider =
    StateNotifierProvider<CatalogController, CatalogState>((ref) {
  return CatalogController(ref.watch(catalogRepositoryProvider));
});
