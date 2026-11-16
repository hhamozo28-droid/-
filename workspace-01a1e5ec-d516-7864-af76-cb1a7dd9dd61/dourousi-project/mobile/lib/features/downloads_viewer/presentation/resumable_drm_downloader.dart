import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../core/database/local_cache_db.dart';
import '../../../core/network/api_client.dart';
import '../../../core/security/aes_drm_cipher.dart';
import '../../catalog/domain/material_entity.dart';
import '../../catalog/presentation/catalog_controller.dart';

class DownloadTaskStatus {
  final bool isDownloading;
  final bool isEncrypting;
  final double progress; // 0.0 -> 1.0
  final bool hasPartialResumeFile;
  final String? errorMessage;

  const DownloadTaskStatus({
    this.isDownloading = false,
    this.isEncrypting = false,
    this.progress = 0.0,
    this.hasPartialResumeFile = false,
    this.errorMessage,
  });

  DownloadTaskStatus copyWith({
    bool? isDownloading,
    bool? isEncrypting,
    double? progress,
    bool? hasPartialResumeFile,
    String? errorMessage,
  }) {
    return DownloadTaskStatus(
      isDownloading: isDownloading ?? this.isDownloading,
      isEncrypting: isEncrypting ?? this.isEncrypting,
      progress: progress ?? this.progress,
      hasPartialResumeFile: hasPartialResumeFile ?? this.hasPartialResumeFile,
      errorMessage: errorMessage,
    );
  }
}

/// Resumable HTTP Range Stream Downloader + SHA-256 Verifier + AES-256-GCM Encryptor.
/// Handles 120.1 MB+ files safely on unstable mobile networks without OOM crashes.
class ResumableDrmDownloadController
    extends StateNotifier<Map<String, DownloadTaskStatus>> {
  final ApiClient _apiClient;
  final AesDrmCipher _drmCipher;
  final LocalCacheDb _cacheDb;
  final Ref _ref;
  final Map<String, CancelToken> _cancelTokens = {};

  ResumableDrmDownloadController({
    required ApiClient apiClient,
    required AesDrmCipher drmCipher,
    required LocalCacheDb cacheDb,
    required Ref ref,
  })  : _apiClient = apiClient,
        _drmCipher = drmCipher,
        _cacheDb = cacheDb,
        _ref = ref,
        super(const {});

  Future<File> _getPartialTempFile(String code, int version) async {
    final vaultDir = await _drmCipher.getVaultDirectory();
    return File(p.join(vaultDir.path, '.partial_${code}_v$version.bin'));
  }

  Future<void> checkPartialState(MaterialEntity material) async {
    final partFile = await _getPartialTempFile(material.code, material.version);
    final exists = await partFile.exists() && (await partFile.length()) > 0;
    final current = state[material.code] ?? const DownloadTaskStatus();
    state = {
      ...state,
      material.code: current.copyWith(hasPartialResumeFile: exists),
    };
  }

  Future<bool> downloadAndEncryptMaterial(MaterialEntity material) async {
    final code = material.code;
    if (state[code]?.isDownloading == true) return false;

    final cancelToken = CancelToken();
    _cancelTokens[code] = cancelToken;

    state = {
      ...state,
      code: const DownloadTaskStatus(isDownloading: true, progress: 0.01),
    };

    try {
      // 1. Obtain short-lived presigned URL & authoritative checksum
      final signedRes = await _apiClient.dio
          .get<Map<String, dynamic>>('/materials/$code/download');
      final signedData = signedRes.data!['data'] as Map<String, dynamic>;
      final downloadUrl = signedData['downloadUrl'] as String;
      final expectedChecksum =
          (signedData['fileChecksum'] as String).toLowerCase();
      final totalServerBytes = (signedData['sizeBytes'] as num).toInt();
      final targetVersion = (signedData['version'] as num).toInt();

      final partFile = await _getPartialTempFile(code, targetVersion);
      int existingBytes = 0;
      if (await partFile.exists()) {
        existingBytes = await partFile.length();
        if (totalServerBytes > 0 && existingBytes > totalServerBytes) {
          await partFile.delete();
          existingBytes = 0;
        }
      }

      // 2. Stream binary with HTTP Range header if resuming partial file
      if (existingBytes < totalServerBytes || totalServerBytes == 0) {
        final streamDio = Dio();
        final response = await streamDio.get<ResponseBody>(
          downloadUrl,
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            headers: existingBytes > 0
                ? {'Range': 'bytes=$existingBytes-'}
                : null,
          ),
        );

        final isPartial206 = response.statusCode == 206;
        final raf = await partFile.open(
          mode: (existingBytes > 0 && isPartial206)
              ? FileMode.append
              : FileMode.write,
        );

        int receivedBytes = (existingBytes > 0 && isPartial206) ? existingBytes : 0;

        try {
          await for (final chunk in response.data!.stream) {
            await raf.writeFrom(chunk);
            receivedBytes += chunk.length;
            if (totalServerBytes > 0) {
              final ratio =
                  (receivedBytes / totalServerBytes).clamp(0.01, 0.95);
              state = {
                ...state,
                code: DownloadTaskStatus(
                  isDownloading: true,
                  progress: ratio,
                ),
              };
            }
          }
        } finally {
          await raf.close();
        }
      }

      // 3. Verify cryptographic SHA-256 integrity before encryption
      state = {
        ...state,
        code: const DownloadTaskStatus(
          isDownloading: true,
          isEncrypting: true,
          progress: 0.96,
        ),
      };

      final actualSha256 =
          (await _drmCipher.computeFileSha256(partFile)).toLowerCase();
      if (expectedChecksum.isNotEmpty && actualSha256 != expectedChecksum) {
        await partFile.delete();
        throw const ApiException(
          code: 'CHECKSUM_MISMATCH',
          message: 'File integrity check (SHA-256) failed. Please retry download.',
        );
      }

      // 4. Delete previous older encrypted version if updating
      if (material.encryptedLocalPath != null) {
        final oldEncrypted = File(material.encryptedLocalPath!);
        if (await oldEncrypted.exists()) {
          await oldEncrypted.delete();
        }
      }

      // 5. Encrypt into chunked AES-256-GCM `.drm` vault file & erase `.part`
      final encryptedPath = await _drmCipher.encryptFileIntoVault(
        rawTempFile: partFile,
        materialCode: code,
        version: targetVersion,
      );

      // 6. Persist encrypted record in local SQLite
      await _cacheDb.upsertEncryptedDownload(
        materialId: material.id,
        code: code,
        downloadedVersion: targetVersion,
        encryptedPath: encryptedPath,
        fileChecksum: actualSha256,
        fileType: material.fileType,
      );

      // Refresh catalog state so badges & paths update immediately
      await _ref.read(catalogControllerProvider.notifier).loadCatalog();

      state = {
        ...state,
        code: const DownloadTaskStatus(
          isDownloading: false,
          isEncrypting: false,
          progress: 1.0,
          hasPartialResumeFile: false,
        ),
      };
      return true;
    } catch (e) {
      final partFile =
          await _getPartialTempFile(material.code, material.version);
      final hasPartial =
          await partFile.exists() && (await partFile.length()) > 0;

      final mapped = ApiClient.mapDioError(e);
      state = {
        ...state,
        code: DownloadTaskStatus(
          isDownloading: false,
          isEncrypting: false,
          hasPartialResumeFile: hasPartial,
          errorMessage: mapped.message,
        ),
      };
      return false;
    } finally {
      _cancelTokens.remove(code);
    }
  }

  Future<void> deleteLocalEncryptedCopy(MaterialEntity material) async {
    if (material.encryptedLocalPath != null) {
      final f = File(material.encryptedLocalPath!);
      if (await f.exists()) {
        await f.delete();
      }
    }
    await _cacheDb.removeEncryptedDownloadRecord(material.code);
    await _ref.read(catalogControllerProvider.notifier).loadCatalog();
  }
}

final resumableDrmDownloadProvider = StateNotifierProvider<
    ResumableDrmDownloadController, Map<String, DownloadTaskStatus>>((ref) {
  return ResumableDrmDownloadController(
    apiClient: ref.watch(apiClientProvider),
    drmCipher: ref.watch(aesDrmCipherProvider),
    cacheDb: ref.watch(localCacheDbProvider),
    ref: ref,
  );
});
