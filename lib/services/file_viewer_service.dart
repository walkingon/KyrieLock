import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart' as file_picker;
import 'file_operations_service.dart';
import 'encryption_service.dart';
import '../screens/video_player_screen.dart';
import '../screens/image_viewer_screen.dart';
import '../screens/audio_player_screen.dart';
import '../screens/text_viewer_screen.dart';
import '../screens/pdf_viewer_screen.dart';

class FileViewerService {
  static Future<void> openFile(
    BuildContext context,
    String filePath, {
    String? password,
    bool isEncrypted = false,
  }) async {
    FileType fileType;
    String actualFilePath = filePath;

    if (isEncrypted && password != null) {
      final extension = FileOperationsService.getFileExtension(filePath);
      if (extension == EncryptionService.encryptedExtension) {
        final originalName = EncryptionService.removeEncryptedExtension(
          filePath,
        );
        fileType = FileOperationsService.getFileType(originalName);
      } else {
        fileType = FileOperationsService.getFileType(filePath);
      }
    } else {
      fileType = FileOperationsService.getFileType(filePath);
    }

    if (fileType == FileType.unknown) {
      if (isEncrypted) {
        throw Exception('不支持查看该文件类型。您可以通过"解密文件"功能解密后,使用其他软件查看');
      } else {
        throw Exception('不支持查看该文件类型');
      }
    }

    Widget? viewerScreen;

    switch (fileType) {
      case FileType.video:
        viewerScreen = VideoPlayerScreen(
          videoPath: actualFilePath,
          password: password,
          isEncrypted: isEncrypted,
        );
        break;
      case FileType.image:
        viewerScreen = ImageViewerScreen(
          imagePath: actualFilePath,
          password: password,
          isEncrypted: isEncrypted,
        );
        break;
      case FileType.audio:
        viewerScreen = AudioPlayerScreen(
          audioPath: actualFilePath,
          password: password,
          isEncrypted: isEncrypted,
        );
        break;
      case FileType.text:
        viewerScreen = TextViewerScreen(
          textPath: actualFilePath,
          password: password,
          isEncrypted: isEncrypted,
        );
        break;
      case FileType.pdf:
        viewerScreen = PDFViewerScreen(
          pdfPath: actualFilePath,
          password: password,
          isEncrypted: isEncrypted,
        );
        break;
      default:
        throw Exception('不支持查看该文件类型');
    }

    if (context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => viewerScreen!),
      );
      
      if (Platform.isAndroid) {
        try {
          await file_picker.FilePicker.platform.clearTemporaryFiles();
        } catch (e) {
          debugPrint('Failed to clear file_picker cache: $e');
        }
      }
    }
  }
}