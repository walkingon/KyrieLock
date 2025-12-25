import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/encryption_service.dart';

class ImageViewerScreen extends StatefulWidget {
  final String imagePath;
  final String? password;
  final bool isEncrypted;

  const ImageViewerScreen({
    super.key,
    required this.imagePath,
    this.password,
    required this.isEncrypted,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  Uint8List? _imageData;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      Uint8List imageData;

      if (widget.isEncrypted && widget.password != null) {
        final decryptResult = await EncryptionService.decryptFile(
          widget.imagePath,
          widget.password!,
        );
        
        if (decryptResult.data != null) {
          imageData = decryptResult.data!;
        } else if (decryptResult.tempFilePath != null) {
          final tempFile = File(decryptResult.tempFilePath!);
          imageData = await tempFile.readAsBytes();
          await tempFile.delete();
        } else {
          throw Exception('Invalid decrypt result');
        }
      } else {
        final file = File(widget.imagePath);
        imageData = await file.readAsBytes();
      }

      setState(() {
        _imageData = imageData;
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
        title: const Text('Image Viewer'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : _errorMessage != null
                ? Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Error: $_errorMessage',
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _imageData != null
                    ? InteractiveViewer(
                        panEnabled: true,
                        boundaryMargin: const EdgeInsets.all(80),
                        minScale: 0.5,
                        maxScale: 4,
                        child: Image.memory(_imageData!),
                      )
                    : const Text('No image loaded'),
      ),
      backgroundColor: Colors.black,
    );
  }
}