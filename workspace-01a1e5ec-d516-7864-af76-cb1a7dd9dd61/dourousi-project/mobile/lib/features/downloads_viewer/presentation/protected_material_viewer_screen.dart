import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';
import '../../../core/config/app_config.dart';
import '../../../core/database/local_cache_db.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/security/aes_drm_cipher.dart';

/// Strict In-App DRM Viewer Screen for PDF, Word (.docx), and Archive (.zip).
///
/// Security Guarantees:
/// 1. Decrypts the AES-256-GCM `.drm` file strictly into memory (`Uint8List`).
/// 2. NEVER writes plaintext files to disk or external/shared directories.
/// 3. NEVER invokes external intents (`open_file` / Share sheet disabled).
/// 4. Protected by Android `FLAG_SECURE` against screenshots & screen recording.
class ProtectedMaterialViewerScreen extends ConsumerStatefulWidget {
  final String materialCode;
  final String materialTitle;
  final String fileType; // 'pdf' | 'docx' | 'zip'
  final String encryptedFilePath;
  final int downloadedVersion;
  final int initialPage;

  const ProtectedMaterialViewerScreen({
    super.key,
    required this.materialCode,
    required this.materialTitle,
    required this.fileType,
    required this.encryptedFilePath,
    required this.downloadedVersion,
    this.initialPage = 1,
  });

  @override
  ConsumerState<ProtectedMaterialViewerScreen> createState() =>
      _ProtectedMaterialViewerScreenState();
}

class _ProtectedMaterialViewerScreenState
    extends ConsumerState<ProtectedMaterialViewerScreen> {
  Uint8List? _decryptedBytes;
  String? _error;
  bool _isDecrypting = true;

  @override
  void initState() {
    super.initState();
    _decryptIntoMemory();
  }

  Future<void> _decryptIntoMemory() async {
    try {
      final bytes = await ref
          .read(aesDrmCipherProvider)
          .decryptVaultFileToMemory(
            encryptedFilePath: widget.encryptedFilePath,
            materialCode: widget.materialCode,
            version: widget.downloadedVersion,
          );
      if (!mounted) return;
      setState(() {
        _decryptedBytes = bytes;
        _isDecrypting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isDecrypting = false;
      });
    }
  }

  @override
  void dispose() {
    // Zero out in-memory plaintext buffer when closing viewer for strict DRM hygiene
    final buf = _decryptedBytes;
    if (buf != null) {
      buf.fillRange(0, buf.length, 0);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final ext = widget.fileType.toLowerCase();

    final titlePrefix = ext == 'docx'
        ? loc.tr('viewer_docx_title')
        : ext == 'zip'
            ? loc.tr('viewer_zip_title')
            : loc.tr('viewer_pdf_title');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.materialCode} · $titlePrefix',
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
            Text(
              widget.materialTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(end: 14),
            child: Icon(Icons.shield_rounded, color: Color(0xFF2DD4BF), size: 20),
          ),
        ],
      ),
      body: _isDecrypting
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _buildFormatViewer(_decryptedBytes!, ext),
    );
  }

  Widget _buildFormatViewer(Uint8List bytes, String ext) {
    switch (ext) {
      case 'docx':
        return _InMemoryDocxViewer(bytes: bytes);
      case 'zip':
        return _InMemoryZipInspectorViewer(
          bytes: bytes,
          parentCode: widget.materialCode,
        );
      case 'pdf':
      default:
        return _InMemoryPdfViewer(
          bytes: bytes,
          sourceName: '${widget.materialCode}_v${widget.downloadedVersion}.pdf',
          initialPage: widget.initialPage,
          onPageChanged: (page) {
            ref
                .read(localCacheDbProvider)
                .updateLastReadPage(widget.materialCode, page);
          },
        );
    }
  }
}

/// 1. In-Memory Protected PDF Viewer (powered by PDFium / pdfrx, handles 600+ pages smoothly)
class _InMemoryPdfViewer extends StatefulWidget {
  final Uint8List bytes;
  final String sourceName;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;

  const _InMemoryPdfViewer({
    required this.bytes,
    required this.sourceName,
    this.initialPage = 1,
    this.onPageChanged,
  });

  @override
  State<_InMemoryPdfViewer> createState() => _InMemoryPdfViewerState();
}

class _InMemoryPdfViewerState extends State<_InMemoryPdfViewer> {
  final PdfViewerController _controller = PdfViewerController();
  int _currentPage = 1;
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Stack(
      children: [
        PdfViewer.data(
          widget.bytes,
          sourceName: widget.sourceName,
          controller: _controller,
          initialPageNumber: widget.initialPage,
          params: PdfViewerParams(
            onViewerReady: (document, controller) {
              if (mounted) {
                setState(() {
                  _totalPages = document.pages.length;
                });
              }
            },
            onPageChanged: (pageNumber) {
              if (pageNumber != null && mounted) {
                setState(() => _currentPage = pageNumber);
                widget.onPageChanged?.call(pageNumber);
              }
            },
          ),
        ),
        Positioned(
          bottom: 18,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.deepSlate.withOpacity(0.86),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '${loc.tr('page_indicator')} $_currentPage ${loc.tr('of_label')} $_totalPages',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 2. In-Memory Protected Word (.docx) Viewer
/// Parses OOXML (`word/document.xml` & `word/media/*`) directly in RAM with zero external app leaks.
class _InMemoryDocxViewer extends StatefulWidget {
  final Uint8List bytes;

  const _InMemoryDocxViewer({required this.bytes});

  @override
  State<_InMemoryDocxViewer> createState() => _InMemoryDocxViewerState();
}

class _DocxBlock {
  final String? text;
  final bool isHeading;
  final Uint8List? imageBytes;

  const _DocxBlock.paragraph(this.text, {this.isHeading = false})
      : imageBytes = null;
  const _DocxBlock.image(this.imageBytes)
      : text = null,
        isHeading = false;
}

class _InMemoryDocxViewerState extends State<_InMemoryDocxViewer> {
  late final List<_DocxBlock> _blocks;

  @override
  void initState() {
    super.initState();
    _blocks = _parseDocxInMemory(widget.bytes);
  }

  List<_DocxBlock> _parseDocxInMemory(Uint8List rawBytes) {
    // Graceful fallback if sample seeded file is PDF/text rather than ZIP-OOXML
    if (rawBytes.length >= 4 &&
        rawBytes[0] == 0x25 &&
        rawBytes[1] == 0x50 &&
        rawBytes[2] == 0x44 &&
        rawBytes[3] == 0x46) {
      return const [
        _DocxBlock.paragraph('مستند تدريبي محمي بنظام دروسي (DRM)', isHeading: true),
      ];
    }

    try {
      final archive = ZipDecoder().decodeBytes(rawBytes);
      final blocks = <_DocxBlock>[];

      final docEntry = archive.findFile('word/document.xml');
      if (docEntry != null) {
        final xmlStr = utf8.decode(docEntry.content as List<int>, allowMalformed: true);
        final xmlDoc = XmlDocument.parse(xmlStr);

        for (final pNode in xmlDoc.findAllElements('w:p')) {
          final styleNode = pNode.findAllElements('w:pStyle').firstOrNull;
          final styleVal = styleNode?.getAttribute('w:val') ?? '';
          final isHeading = styleVal.toLowerCase().contains('heading') ||
              styleVal.toLowerCase().contains('title');

          final buffer = StringBuffer();
          for (final tNode in pNode.findAllElements('w:t')) {
            buffer.write(tNode.innerText);
          }
          final paragraph = buffer.toString().trim();
          if (paragraph.isNotEmpty) {
            blocks.add(_DocxBlock.paragraph(paragraph, isHeading: isHeading));
          }
        }
      }

      // Append any embedded diagrams/images from word/media/*
      for (final file in archive.files) {
        if (file.isFile &&
            file.name.startsWith('word/media/') &&
            (file.name.endsWith('.png') ||
                file.name.endsWith('.jpg') ||
                file.name.endsWith('.jpeg'))) {
          blocks.add(
            _DocxBlock.image(Uint8List.fromList(file.content as List<int>)),
          );
        }
      }

      if (blocks.isEmpty) {
        blocks.add(const _DocxBlock.paragraph('المستند خالٍ من النصوص القابلة للعرض.'));
      }
      return blocks;
    } catch (_) {
      final fallbackText = utf8.decode(rawBytes, allowMalformed: true);
      return [_DocxBlock.paragraph(fallbackText)];
    }
  }

  @override
  Widget build(BuildContext context) {
    // Selection disabled via SelectionContainer.disabled to prevent copy/paste piracy
    return SelectionContainer.disabled(
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _blocks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final block = _blocks[index];
          if (block.imageBytes != null) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(block.imageBytes!, fit: BoxFit.contain),
            );
          }
          return Text(
            block.text ?? '',
            style: TextStyle(
              fontSize: block.isHeading ? 19 : 15.5,
              fontWeight: block.isHeading ? FontWeight.w800 : FontWeight.w400,
              color: AppTheme.deepSlate,
              height: 1.65,
            ),
          );
        },
      ),
    );
  }
}

/// 3. In-Memory Protected ZIP Archive Inspector
/// Lists files inside the training `.zip` and opens inner PDFs, Word docs, images, or notes
/// strictly in RAM inside Dourousi — never extracting files to phone storage!
class _InMemoryZipInspectorViewer extends StatefulWidget {
  final Uint8List bytes;
  final String parentCode;

  const _InMemoryZipInspectorViewer({
    required this.bytes,
    required this.parentCode,
  });

  @override
  State<_InMemoryZipInspectorViewer> createState() =>
      _InMemoryZipInspectorViewerState();
}

class _InMemoryZipInspectorViewerState
    extends State<_InMemoryZipInspectorViewer> {
  List<ArchiveFile> _entries = const [];
  bool _isSamplePdfFallback = false;

  @override
  void initState() {
    super.initState();
    _decodeZipEntries();
  }

  void _decodeZipEntries() {
    if (widget.bytes.length >= 4 &&
        widget.bytes[0] == 0x25 &&
        widget.bytes[1] == 0x50 &&
        widget.bytes[2] == 0x44 &&
        widget.bytes[3] == 0x46) {
      _isSamplePdfFallback = true;
      return;
    }
    try {
      final archive = ZipDecoder().decodeBytes(widget.bytes);
      _entries = archive.files.where((f) => f.isFile).toList();
    } catch (_) {
      _entries = const [];
    }
  }

  void _openInnerEntry(ArchiveFile entry) {
    final contentBytes = Uint8List.fromList(entry.content as List<int>);
    final lower = entry.name.toLowerCase();

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(entry.name.split('/').last)),
          body: lower.endsWith('.pdf')
              ? _InMemoryPdfViewer(
                  bytes: contentBytes,
                  sourceName: entry.name,
                )
              : lower.endsWith('.docx')
                  ? _InMemoryDocxViewer(bytes: contentBytes)
                  : (lower.endsWith('.png') ||
                          lower.endsWith('.jpg') ||
                          lower.endsWith('.jpeg'))
                      ? Center(
                          child: InteractiveViewer(
                            child: Image.memory(contentBytes),
                          ),
                        )
                      : SelectionContainer.disabled(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              utf8.decode(contentBytes, allowMalformed: true),
                              style: const TextStyle(fontSize: 14.5, height: 1.6),
                            ),
                          ),
                        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isSamplePdfFallback) {
      return _InMemoryPdfViewer(
        bytes: widget.bytes,
        sourceName: '${widget.parentCode}.pdf',
      );
    }

    final loc = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Text(
            loc.tr('viewer_zip_subtitle'),
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF475569),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = _entries[index];
              final kb = (item.size / 1024).toStringAsFixed(1);
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined,
                      color: AppTheme.primaryEmerald),
                  title: Text(
                    item.name.split('/').last,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('${item.name} · $kb KB'),
                  trailing: const Icon(Icons.visibility_outlined),
                  onTap: () => _openInnerEntry(item),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
