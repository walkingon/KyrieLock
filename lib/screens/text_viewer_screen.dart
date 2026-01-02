import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/encryption_service.dart';

class TextViewerScreen extends StatefulWidget {
  final String textPath;
  final String? password;
  final bool isEncrypted;

  const TextViewerScreen({
    super.key,
    required this.textPath,
    this.password,
    required this.isEncrypted,
  });

  @override
  State<TextViewerScreen> createState() => _TextViewerScreenState();
}

class _TextViewerScreenState extends State<TextViewerScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  String? _textContent;

  @override
  void initState() {
    super.initState();
    _loadText();
  }

  Future<void> _loadText() async {
    try {
      String textContent;

      if (widget.isEncrypted && widget.password != null) {
        final decryptResult = await EncryptionService.decryptFile(
          widget.textPath,
          widget.password!,
        );
        
        if (decryptResult.data != null) {
          textContent = utf8.decode(decryptResult.data!);
        } else if (decryptResult.tempFilePath != null) {
          final tempFile = File(decryptResult.tempFilePath!);
          textContent = await tempFile.readAsString(encoding: utf8);
          await tempFile.delete();
        } else {
          throw Exception('Invalid decrypt result');
        }
      } else {
        final file = File(widget.textPath);
        textContent = await file.readAsString();
      }

      setState(() {
        _textContent = textContent;
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
        title: const Text('Text Viewer'),
        backgroundColor: Colors.teal,
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
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: SelectableText(
                _textContent ?? '',
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
    );
  }
}