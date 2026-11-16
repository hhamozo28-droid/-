class CategoryEntity {
  final String id;
  final String prefixCode;
  final String nameAr;
  final String nameFr;
  final String nameEn;

  const CategoryEntity({
    required this.id,
    required this.prefixCode,
    required this.nameAr,
    required this.nameFr,
    required this.nameEn,
  });

  factory CategoryEntity.fromJson(Map<String, dynamic> json) {
    return CategoryEntity(
      id: (json['id'] ?? '').toString(),
      prefixCode: (json['prefixCode'] ?? '').toString(),
      nameAr: (json['nameAr'] ?? '').toString(),
      nameFr: (json['nameFr'] ?? '').toString(),
      nameEn: (json['nameEn'] ?? '').toString(),
    );
  }

  String localizedName(String langCode) {
    switch (langCode) {
      case 'fr':
        return nameFr;
      case 'en':
        return nameEn;
      case 'ar':
      default:
        return nameAr;
    }
  }
}

class MaterialEntity {
  final String id;
  final String code;
  final String title;
  final String contentLabel;
  final CategoryEntity category;
  final int unitsCount;
  final int lessonsCount;
  final int filesCount;
  final int pagesTotal;
  final int sizeBytes;
  final double sizeMb;
  final String fileType; // 'zip' | 'pdf' | 'docx'
  final String fileChecksum;
  final int version;
  final String deepLink;
  final String updatedAt;

  // Local vault state merged from SQLite
  final int? downloadedVersion;
  final String? encryptedLocalPath;
  final int lastReadPage;

  const MaterialEntity({
    required this.id,
    required this.code,
    required this.title,
    required this.contentLabel,
    required this.category,
    required this.unitsCount,
    required this.lessonsCount,
    required this.filesCount,
    required this.pagesTotal,
    required this.sizeBytes,
    required this.sizeMb,
    required this.fileType,
    required this.fileChecksum,
    required this.version,
    required this.deepLink,
    required this.updatedAt,
    this.downloadedVersion,
    this.encryptedLocalPath,
    this.lastReadPage = 1,
  });

  bool get isDownloaded =>
      encryptedLocalPath != null && downloadedVersion != null;

  bool get hasNewUpdateAvailable =>
      downloadedVersion != null && version > downloadedVersion!;

  factory MaterialEntity.fromJson(
    Map<String, dynamic> json, {
    Map<String, Object?>? localDownloadRow,
  }) {
    return MaterialEntity(
      id: (json['id'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      contentLabel: (json['contentLabel'] ??
              'مخططات الدروس (نموذج M9-1 — Word + PDF)')
          .toString(),
      category: CategoryEntity.fromJson(
        (json['category'] as Map<String, dynamic>?) ?? const {},
      ),
      unitsCount: (json['unitsCount'] as num? ?? 1).toInt(),
      lessonsCount: (json['lessonsCount'] as num? ?? 1).toInt(),
      filesCount: (json['filesCount'] as num? ?? 1).toInt(),
      pagesTotal: (json['pagesTotal'] as num? ?? 1).toInt(),
      sizeBytes: (json['sizeBytes'] as num? ?? 0).toInt(),
      sizeMb: (json['sizeMb'] as num? ?? 0).toDouble(),
      fileType: (json['fileType'] ?? 'zip').toString().toLowerCase(),
      fileChecksum: (json['fileChecksum'] ?? '').toString(),
      version: (json['version'] as num? ?? 1).toInt(),
      deepLink: (json['deepLink'] ?? '').toString(),
      updatedAt: (json['updatedAt'] ?? '').toString(),
      downloadedVersion: localDownloadRow?['downloaded_version'] as int?,
      encryptedLocalPath: localDownloadRow?['encrypted_path'] as String?,
      lastReadPage: localDownloadRow?['last_read_page'] as int? ?? 1,
    );
  }
}
