import 'dart:io';
import 'package:file_picker/file_picker.dart' as file_picker;
import '../services/encryption_service.dart';

class FileOperationsService {
  static Future<List<String>> pickFilesForDecryption() async {
    file_picker.FilePickerResult? result = await file_picker.FilePicker.platform
        .pickFiles(type: file_picker.FileType.any, allowMultiple: true);

    if (result != null && result.files.isNotEmpty) {
      return result.files
          .where((file) => file.path != null)
          .map((file) => file.path!)
          .toList();
    }
    return [];
  }

  static Future<String?> pickFile() async {
    file_picker.FilePickerResult? result = await file_picker.FilePicker.platform
        .pickFiles(type: file_picker.FileType.any, allowMultiple: false);

    if (result != null && result.files.isNotEmpty) {
      return result.files.single.path;
    }
    return null;
  }

  static Future<List<String>> pickMultipleFiles() async {
    file_picker.FilePickerResult? result = await file_picker.FilePicker.platform
        .pickFiles(type: file_picker.FileType.any, allowMultiple: true);

    if (result != null && result.files.isNotEmpty) {
      return result.files
          .where((file) => file.path != null)
          .map((file) => file.path!)
          .toList();
    }
    return [];
  }

  static Future<String?> pickOutputDirectory() async {
    String? outputPath = await file_picker.FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Output Directory',
    );
    return outputPath;
  }

  static Future<void> encryptFile(
    String inputPath,
    String outputDirectory,
    String password, {
    String? hint,
  }) async {
    final file = File(inputPath);
    final fileName = file.path.split(Platform.pathSeparator).last;

    final outputName = EncryptionService.addEncryptedExtension(fileName);
    final outputPath = '$outputDirectory${Platform.pathSeparator}$outputName';

    await EncryptionService.encryptFile(
      inputPath,
      outputPath,
      password,
      hint: hint,
    );
  }

  static Future<void> decryptFile(
    String inputPath,
    String outputDirectory,
    String password,
  ) async {
    final file = File(inputPath);
    final fileName = file.path.split(Platform.pathSeparator).last;

    final outputName = EncryptionService.removeEncryptedExtension(fileName);
    final outputPath = '$outputDirectory${Platform.pathSeparator}$outputName';

    await EncryptionService.decryptFileToPath(inputPath, outputPath, password);
  }

  static String getFileExtension(String filePath) {
    return filePath.split('.').last.toLowerCase();
  }

  static FileType getFileType(String filePath) {
    final ext = getFileExtension(filePath);

    if (['mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv'].contains(ext)) {
      return FileType.video;
    } else if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext)) {
      return FileType.image;
    } else if (['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg'].contains(ext)) {
      return FileType.audio;
    } else if (['txt', 'md', 'json', 'xml', 'csv'].contains(ext)) {
      return FileType.text;
    } else if (ext == 'pdf') {
      return FileType.pdf;
    } else {
      return FileType.unknown;
    }
  }
}

enum FileType { video, image, audio, text, pdf, unknown }