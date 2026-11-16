import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite database powering:
/// 1. Instant offline catalog browsing of all 55+ materials & categories (<50ms load).
/// 2. Encrypted local file registry (`local_downloads`) tracking downloaded version,
///    encrypted `.drm` path, SHA-256 checksum, and last read page (`last_page`).
/// 3. Read/unread tracking for in-app update notifications.
class LocalCacheDb {
  static const String _dbName = 'dourousi_local_cache.db';
  static const int _dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbDir = await getDatabasesPath();
    final fullPath = p.join(dbDir, _dbName);

    _db = await openDatabase(
      fullPath,
      version: _dbVersion,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE cached_materials (
            id TEXT PRIMARY KEY,
            code TEXT UNIQUE NOT NULL,
            category_prefix TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE local_downloads (
            material_id TEXT PRIMARY KEY,
            code TEXT UNIQUE NOT NULL,
            downloaded_version INTEGER NOT NULL,
            encrypted_path TEXT NOT NULL,
            file_checksum TEXT NOT NULL,
            file_type TEXT NOT NULL,
            last_read_page INTEGER NOT NULL DEFAULT 1,
            downloaded_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE read_notifications (
            notification_id TEXT PRIMARY KEY,
            read_at TEXT NOT NULL
          )
        ''');
      },
    );

    return _db!;
  }

  Future<void> cacheMaterialsJsonList(List<Map<String, dynamic>> rawItems) async {
    final db = await database;
    final batch = db.batch();
    for (final item in rawItems) {
      final category = item['category'] as Map<String, dynamic>? ?? const {};
      batch.insert(
        'cached_materials',
        {
          'id': item['id'].toString(),
          'code': item['code'].toString(),
          'category_prefix': (category['prefixCode'] ?? '').toString(),
          'payload_json': jsonEncode(item),
          'updated_at': (item['updatedAt'] ?? DateTime.now().toIso8601String()).toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedMaterialsJsonList() async {
    final db = await database;
    final rows = await db.query('cached_materials', orderBy: 'code ASC');
    return rows
        .map((r) => jsonDecode(r['payload_json'] as String) as Map<String, dynamic>)
        .toList();
  }

  Future<void> upsertEncryptedDownload({
    required String materialId,
    required String code,
    required int downloadedVersion,
    required String encryptedPath,
    required String fileChecksum,
    required String fileType,
  }) async {
    final db = await database;
    final existing = await getEncryptedDownloadByCode(code);
    final preservedPage = existing?['last_read_page'] as int? ?? 1;

    await db.insert(
      'local_downloads',
      {
        'material_id': materialId,
        'code': code,
        'downloaded_version': downloadedVersion,
        'encrypted_path': encryptedPath,
        'file_checksum': fileChecksum,
        'file_type': fileType,
        'last_read_page': preservedPage,
        'downloaded_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, Object?>?> getEncryptedDownloadByCode(String code) async {
    final db = await database;
    final rows = await db.query(
      'local_downloads',
      where: 'code = ?',
      whereArgs: [code.toUpperCase()],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Map<String, Object?>>> getAllEncryptedDownloadsByCode() async {
    final db = await database;
    final rows = await db.query('local_downloads');
    return {
      for (final row in rows) (row['code'] as String): row,
    };
  }

  Future<void> updateLastReadPage(String code, int pageNumber) async {
    final db = await database;
    await db.update(
      'local_downloads',
      {'last_read_page': pageNumber < 1 ? 1 : pageNumber},
      where: 'code = ?',
      whereArgs: [code.toUpperCase()],
    );
  }

  Future<void> removeEncryptedDownloadRecord(String code) async {
    final db = await database;
    await db.delete(
      'local_downloads',
      where: 'code = ?',
      whereArgs: [code.toUpperCase()],
    );
  }

  Future<Set<String>> getReadNotificationIds() async {
    final db = await database;
    final rows = await db.query('read_notifications');
    return rows.map((r) => r['notification_id'] as String).toSet();
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    final db = await database;
    await db.insert(
      'read_notifications',
      {
        'notification_id': notificationId,
        'read_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Clears all cached records on logout or account deletion.
  Future<void> wipeAllTables() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('local_downloads');
      await txn.delete('cached_materials');
      await txn.delete('read_notifications');
    });
  }
}

final localCacheDbProvider = Provider<LocalCacheDb>((ref) {
  return LocalCacheDb();
});
