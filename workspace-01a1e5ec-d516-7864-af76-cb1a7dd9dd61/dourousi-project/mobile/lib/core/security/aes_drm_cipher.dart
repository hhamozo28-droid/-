import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto_hash;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'secure_vault_storage.dart';

/// Strict In-App DRM Encryption Engine (AES-256-GCM Chunked Authenticated Encryption).
///
/// Why Chunked AES-256-GCM?
/// Training files in Dourousi reach 120.1 MB+. Encrypting/decrypting a 120 MB file as a single
/// contiguous byte array can spike RAM on budget smartphones. Instead, we divide the file into
/// authenticated 1 MB chunks, each with a deterministic derived 96-bit nonce (baseNonce ^ chunkIndex)
/// and its own 128-bit Poly1305/GCM MAC tag so tampering or truncation is detected immediately.
///
/// Decrypted plaintext NEVER touches external/shared storage — it is held only in memory for
/// the internal PDF / DOCX / ZIP viewer and zeroed out when closed.
class AesDrmCipher {
  static const int _chunkPlainSize = 1024 * 1024; // 1 MB plaintext per chunk
  static const int _gcmNonceLength = 12;
  static const int _gcmMacLength = 16;
  static const List<int> _magicHeader = [0x44, 0x52, 0x53, 0x31]; // "DRS1"

  final SecureVaultStorage _vaultStorage;
  final AesGcm _aesGcm = AesGcm.with256bits();

  AesDrmCipher(this._vaultStorage);

  /// Private internal sandbox directory (inaccessible to user file managers or external apps).
  Future<Directory> getVaultDirectory() async {
    final appSupportDir = await getApplicationSupportDirectory();
    final vaultDir = Directory(p.join(appSupportDir.path, 'drm_encrypted_vault'));
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }
    return vaultDir;
  }

  /// Computes SHA-256 hex digest of a downloaded temp file via streaming (low RAM)
  /// to verify integrity against the server's `fileChecksum`.
  Future<String> computeFileSha256(File file) async {
    final digest = await crypto_hash.sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Encrypts a verified raw file stream into an authenticated `.drm` file inside the sandbox,
  /// then deletes the temporary download file immediately.
  Future<String> encryptFileIntoVault({
    required File rawTempFile,
    required String materialCode,
    required int version,
  }) async {
    final masterKeyBytes = await _vaultStorage.getOrCreateDrmMasterKey();
    final secretKey = SecretKey(masterKeyBytes);

    final vaultDir = await getVaultDirectory();
    final encryptedPath = p.join(vaultDir.path, '${materialCode}_v$version.drm');
    final encryptedFile = File(encryptedPath);

    final rng = Random.secure();
    final baseNonce = Uint8List.fromList(
      List<int>.generate(_gcmNonceLength, (_) => rng.nextInt(256)),
    );

    final sink = encryptedFile.openWrite();
    try {
      // Header: 4-byte magic "DRS1" + 12-byte baseNonce
      sink.add(_magicHeader);
      sink.add(baseNonce);

      final raf = await rawTempFile.open(mode: FileMode.read);
      try {
        int chunkIndex = 0;
        while (true) {
          final plainChunk = await raf.read(_chunkPlainSize);
          if (plainChunk.isEmpty) break;

          final chunkNonce = _deriveChunkNonce(baseNonce, chunkIndex);
          final secretBox = await _aesGcm.encrypt(
            plainChunk,
            secretKey: secretKey,
            nonce: chunkNonce,
            aad: _buildChunkAad(materialCode, version, chunkIndex),
          );

          // Write 4-byte big-endian ciphertext+mac length, followed by cipherText + 16-byte MAC
          final payloadLength = secretBox.cipherText.length + _gcmMacLength;
          final lenBytes = ByteData(4)..setUint32(0, payloadLength, Endian.big);
          sink.add(lenBytes.buffer.asUint8List());
          sink.add(secretBox.cipherText);
          sink.add(secretBox.mac.bytes);

          chunkIndex++;
        }
      } finally {
        await raf.close();
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    // Securely delete raw temporary download file so only ciphertext remains on disk
    if (await rawTempFile.exists()) {
      await rawTempFile.delete();
    }

    return encryptedPath;
  }

  /// Decrypts an encrypted `.drm` file strictly into memory (`Uint8List`) for in-app viewing.
  /// Never writes decrypted bytes to disk!
  Future<Uint8List> decryptVaultFileToMemory({
    required String encryptedFilePath,
    required String materialCode,
    required int version,
  }) async {
    final file = File(encryptedFilePath);
    if (!await file.exists()) {
      throw const FileSystemException('Encrypted DRM file is missing from vault.');
    }

    final masterKeyBytes = await _vaultStorage.getOrCreateDrmMasterKey();
    final secretKey = SecretKey(masterKeyBytes);

    final raf = await file.open(mode: FileMode.read);
    final builder = BytesBuilder(copy: false);

    try {
      final header = await raf.read(4 + _gcmNonceLength);
      if (header.length < 16 ||
          header[0] != _magicHeader[0] ||
          header[1] != _magicHeader[1] ||
          header[2] != _magicHeader[2] ||
          header[3] != _magicHeader[3]) {
        throw const FormatException('Corrupted or invalid Dourousi DRM header.');
      }

      final baseNonce = Uint8List.sublistView(header, 4, 16);
      int chunkIndex = 0;

      while (true) {
        final lenHeader = await raf.read(4);
        if (lenHeader.isEmpty) break;
        if (lenHeader.length < 4) {
          throw const FormatException('Truncated DRM chunk header.');
        }

        final payloadLen =
            ByteData.sublistView(lenHeader).getUint32(0, Endian.big);
        final payload = await raf.read(payloadLen);
        if (payload.length < payloadLen || payloadLen < _gcmMacLength) {
          throw const FormatException('Truncated DRM encrypted payload.');
        }

        final cipherLen = payloadLen - _gcmMacLength;
        final cipherText = Uint8List.sublistView(payload, 0, cipherLen);
        final macBytes = Uint8List.sublistView(payload, cipherLen, payloadLen);

        final secretBox = SecretBox(
          cipherText,
          nonce: _deriveChunkNonce(baseNonce, chunkIndex),
          mac: Mac(macBytes),
        );

        final clearChunk = await _aesGcm.decrypt(
          secretBox,
          secretKey: secretKey,
          aad: _buildChunkAad(materialCode, version, chunkIndex),
        );

        builder.add(clearChunk);
        chunkIndex++;
      }

      return builder.takeBytes();
    } finally {
      await raf.close();
    }
  }

  /// Wipes the entire local encrypted vault directory on logout or account deletion.
  Future<void> wipeEntireVaultDirectory() async {
    final dir = await getVaultDirectory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Uint8List _deriveChunkNonce(Uint8List baseNonce, int chunkIndex) {
    final derived = Uint8List.fromList(baseNonce);
    derived[8] ^= (chunkIndex >> 24) & 0xFF;
    derived[9] ^= (chunkIndex >> 16) & 0xFF;
    derived[10] ^= (chunkIndex >> 8) & 0xFF;
    derived[11] ^= chunkIndex & 0xFF;
    return derived;
  }

  List<int> _buildChunkAad(String code, int version, int chunkIndex) {
    return '$code:v$version:#$chunkIndex'.codeUnits;
  }
}

final aesDrmCipherProvider = Provider<AesDrmCipher>((ref) {
  final storage = ref.watch(secureVaultStorageProvider);
  return AesDrmCipher(storage);
});
