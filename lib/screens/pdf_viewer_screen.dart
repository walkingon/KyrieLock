import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import '../services/encryption_service.dart';

class PDFViewerScreen extends StatefulWidget {
  final String pdfPath;
  final String? password;
  final bool isEncrypted;

  const PDFViewerScreen({
    super.key,
    required this.pdfPath,
    this.password,
    required this.isEncrypted,
  });

  @override
  State<PDFViewerScreen> createState() => _PDFViewerScreenState();
}

class _PDFViewerScreenState extends State<PDFViewerScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  String? _pdfFilePath;
  int _currentPage = 0;
  int _totalPages = 0;
  File? _tempPdfFile;

  @override
  void initState() {
    super.initState();
    _loadPDF();
  }

  Future<void> _loadPDF() async {
    try {
      String pdfPath;

      if (widget.isEncrypted && widget.password != null) {
        final decryptResult = await EncryptionService.decryptFile(
          widget.pdfPath,
          widget.password!,
        );

        if (decryptResult.isLargeFile && decryptResult.tempFilePath != null) {
          pdfPath = decryptResult.tempFilePath!;
          _tempPdfFile = File(pdfPath);
        } else if (decryptResult.data != null) {
          final tempDir = Directory.systemTemp;
          _tempPdfFile = File(
            '${tempDir.path}/temp_pdf_${DateTime.now().millisecondsSinceEpoch}.pdf',
          );
          await _tempPdfFile!.writeAsBytes(decryptResult.data!);
          pdfPath = _tempPdfFile!.path;
        } else {
          throw Exception('Invalid decrypt result');
        }
      } else {
        pdfPath = widget.pdfPath;
      }

      setState(() {
        _pdfFilePath = pdfPath;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'PDF Viewer ${_totalPages > 0 ? '($_currentPage/$_totalPages)' : ''}',
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error: $_errorMessage',
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _pdfFilePath != null
          ? PDFView(
              filePath: _pdfFilePath!,
              enableSwipe: true,
              swipeHorizontal: false,
              autoSpacing: true,
              pageFling: true,
              onRender: (pages) {
                setState(() {
                  _totalPages = pages ?? 0;
                });
              },
              onPageChanged: (page, total) {
                setState(() {
                  _currentPage = (page ?? 0) + 1;
                  _totalPages = total ?? 0;
                });
              },
              onError: (error) {
                setState(() {
                  _errorMessage = error.toString();
                });
              },
            )
          : const Center(child: Text('No PDF loaded')),
    );
  }

  @override
  void dispose() {
    _cleanupTempFile();
    super.dispose();
  }

  void _cleanupTempFile() {
    if (_tempPdfFile != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        try {
          if (_tempPdfFile!.existsSync()) {
            _tempPdfFile!.deleteSync();
          }
        } catch (_) {
        }
      });
    }
  }
}