import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'rust_crypto.dart';

bool get _isMobilePlatform {
  return Platform.isAndroid || Platform.isIOS;
}

class DecryptResult {
  final Uint8List? data;
  final String? tempFilePath;
  final bool isLargeFile;

  DecryptResult._({this.data, this.tempFilePath, required this.isLargeFile});

  factory DecryptResult.inMemory(Uint8List data) {
    return DecryptResult._(data: data, isLargeFile: false);
  }

  factory DecryptResult.tempFile(String path) {
    return DecryptResult._(tempFilePath: path, isLargeFile: true);
  }
}

class EncryptionService {
  static const String magicString = 'KYRIE_LOCK';
  static const String encryptedExtension = 'kyl';
  static const int version = 1;
  static const int headerSize = 14;
  static const int maxHintLength = 32;

  static int get chunkSize {
    return _isMobilePlatform
        ? 128 * 1048576
        : 256 * 1048576;
  }

  static Future<void> encryptFile(
    String inputPath,
    String outputPath,
    String password, {
    String? hint,
  }) async {
    final startTime = DateTime.now();
    final inputFile = File(inputPath);

    if (!await inputFile.exists()) {
      throw Exception('Input file does not exist');
    }

    final fileSize = await inputFile.length();
    if (kDebugMode) {
      debugPrint(
        '[ENCRYPT] Starting encryption: fileSize=$fileSize',
      );
    }

    final passwordBytes = utf8.encode(password);
    
    try {
      RustCrypto.encryptFile(
        inputPath,
        outputPath,
        Uint8List.fromList(passwordBytes),
        hint: hint,
        isMobile: _isMobilePlatform,
      );

      if (kDebugMode) {
        final duration = DateTime.now().difference(startTime);
        debugPrint(
          '[ENCRYPT] Encryption completed in ${duration.inMilliseconds}ms',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ENCRYPT] Encryption failed: $e');
      }
      rethrow;
    }
  }

  static Future<bool> isEncryptedFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return false;
    }

    try {
      final bytes = await file.openRead(0, magicString.length).first;
      final magic = String.fromCharCodes(bytes);
      return magic == magicString;
    } catch (e) {
      return false;
    }
  }

  static Future<String?> getPasswordHint(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return null;
    }

    try {
      final hint = RustCrypto.getHintFromFile(filePath);
      return hint.isEmpty ? null : hint;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[HINT] Failed to get hint: $e');
      }
      return null;
    }
  }

  static Future<DecryptResult> decryptFile(
    String filePath,
    String password,
  ) async {
    final startTime = DateTime.now();
    final file = File(filePath);

    if (!await file.exists()) {
      throw Exception('File does not exist');
    }

    final fileSize = await file.length();
    final encryptedSize = fileSize - headerSize - 1;
    
    if (kDebugMode) {
      debugPrint('[DECRYPT] Starting decryption: fileSize=$fileSize');
    }

    final passwordBytes = utf8.encode(password);
    
    try {
      final isLargeFile = encryptedSize > chunkSize;
      
      if (isLargeFile) {
        final tempDir = await getTemporaryDirectory();
        final originalExtension = _getOriginalExtension(filePath);
        final tempFile = File(
          path.join(
            tempDir.path,
            'kyrie_${DateTime.now().millisecondsSinceEpoch}$originalExtension',
          ),
        );

        if (kDebugMode) {
          debugPrint('[DECRYPT] Large file, decrypting to temp file: ${tempFile.path}');
        }

        RustCrypto.decryptFile(
          filePath,
          tempFile.path,
          Uint8List.fromList(passwordBytes),
          isMobile: _isMobilePlatform,
        );

        if (kDebugMode) {
          final duration = DateTime.now().difference(startTime);
          debugPrint(
            '[DECRYPT] Decryption to temp file completed in ${duration.inMilliseconds}ms',
          );
        }

        return DecryptResult.tempFile(tempFile.path);
      } else {
        if (kDebugMode) {
          debugPrint('[DECRYPT] Small file, decrypting to memory');
        }

        final decryptedData = RustCrypto.decryptFileToMemory(
          filePath,
          Uint8List.fromList(passwordBytes),
          isMobile: _isMobilePlatform,
        );

        if (kDebugMode) {
          final duration = DateTime.now().difference(startTime);
          debugPrint(
            '[DECRYPT] Decryption to memory completed in ${duration.inMilliseconds}ms, size: ${decryptedData.length}',
          );
        }

        return DecryptResult.inMemory(decryptedData);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DECRYPT] Decryption failed: $e');
      }
      rethrow;
    }
  }

  static String _getOriginalExtension(String encryptedPath) {
    final name = path.basenameWithoutExtension(encryptedPath);
    final lastDot = name.lastIndexOf('.');
    if (lastDot != -1) {
      return name.substring(lastDot);
    }
    return '';
  }

  static Future<void> decryptFileToPath(
    String inputPath,
    String outputPath,
    String password,
  ) async {
    final startTime = DateTime.now();
    final inputFile = File(inputPath);

    if (!await inputFile.exists()) {
      throw Exception('Input file does not exist');
    }

    final fileSize = await inputFile.length();
    if (kDebugMode) {
      debugPrint(
        '[DECRYPT_TO_PATH] Starting decryption: fileSize=$fileSize',
      );
    }

    final passwordBytes = utf8.encode(password);

    try {
      RustCrypto.decryptFile(
        inputPath,
        outputPath,
        Uint8List.fromList(passwordBytes),
        isMobile: _isMobilePlatform,
      );

      if (kDebugMode) {
        final duration = DateTime.now().difference(startTime);
        final outputSize = await File(outputPath).length();
        debugPrint(
          '[DECRYPT_TO_PATH] Decryption completed in ${duration.inMilliseconds}ms, output size: $outputSize',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DECRYPT_TO_PATH] Decryption failed: $e');
      }
      rethrow;
    }
  }

  static String addEncryptedExtension(String filename) {
    return '$filename.$encryptedExtension';
  }

  static String removeEncryptedExtension(String filename) {
    if (filename.endsWith('.$encryptedExtension')) {
      return filename.substring(0, filename.length - encryptedExtension.length - 1);
    }
    return filename;
  }
}