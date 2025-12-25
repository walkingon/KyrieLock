import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'rust_crypto.dart';

class EncryptionService {
  static const String magicString = 'KYRIE_LOCK';
  static const String encryptedExtension = 'kyl';
  static const int version = 1;
  static const int headerSize = 14;
  static const int maxHintLength = 32;
  static const bool useRustCrypto = true;

  static Uint8List _deriveKey(String password) {
    if (useRustCrypto) {
      return RustCrypto.deriveKey(utf8.encode(password));
    } else {
      final bytes = utf8.encode(password);
      final hash = sha256.convert(bytes);
      return Uint8List.fromList(hash.bytes);
    }
  }

  static Future<void> encryptFile(
    String inputPath,
    String outputPath,
    String password, {
    String? hint,
  }) async {
    final inputFile = File(inputPath);
    final outputFile = File(outputPath);

    if (!await inputFile.exists()) {
      throw Exception('Input file does not exist');
    }

    final iv = encrypt.IV.fromLength(16);
    final bytes = await inputFile.readAsBytes();

    Uint8List encryptedBytes;
    if (useRustCrypto) {
      final passwordBytes = utf8.encode(password);
      encryptedBytes = RustCrypto.encryptData(bytes, passwordBytes, iv.bytes);
    } else {
      final key = encrypt.Key(_deriveKey(password));
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final encrypted = encrypter.encryptBytes(bytes, iv: iv);
      encryptedBytes = encrypted.bytes;
    }

    final hintBytes = hint != null && hint.isNotEmpty
        ? utf8.encode(
            hint.substring(
              0,
              hint.length > maxHintLength ? maxHintLength : hint.length,
            ),
          )
        : <int>[];
    final hintLength = hintBytes.length;

    final header = BytesBuilder();
    header.add(utf8.encode(magicString));
    header.add([version, 0, 0, 0]);

    final outputData = BytesBuilder();
    outputData.add(header.toBytes());
    outputData.add([hintLength]);
    outputData.add(hintBytes);
    outputData.add(iv.bytes);
    outputData.add(encryptedBytes);

    await outputFile.writeAsBytes(outputData.toBytes());
  }

  static Future<bool> isEncryptedFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return false;
    }

    try {
      final bytes = await file.openRead(0, magicString.length).first;
      final header = utf8.decode(bytes, allowMalformed: false);
      return header == magicString;
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
      final bytes = await file.readAsBytes();

      final magicBytes = bytes.sublist(0, magicString.length);
      final magic = utf8.decode(magicBytes);
      if (magic != magicString) {
        return null;
      }

      final versionBytes = bytes.sublist(magicString.length, headerSize);
      final fileVersion = versionBytes[0];
      if (fileVersion != version) {
        return null;
      }

      final hintLengthOffset = headerSize;
      if (bytes.length <= hintLengthOffset) {
        return null;
      }

      final hintLength = bytes[hintLengthOffset];
      if (hintLength == 0) {
        return null;
      }

      final hintOffset = hintLengthOffset + 1;
      if (bytes.length < hintOffset + hintLength) {
        return null;
      }

      final hintBytes = bytes.sublist(hintOffset, hintOffset + hintLength);
      return utf8.decode(hintBytes);
    } catch (e) {
      return null;
    }
  }

  static Future<Uint8List> decryptFile(String filePath, String password) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist');
    }

    final bytes = await file.readAsBytes();

    final magicBytes = bytes.sublist(0, magicString.length);
    final magic = utf8.decode(magicBytes);
    if (magic != magicString) {
      throw Exception('Not an encrypted file');
    }

    final versionBytes = bytes.sublist(magicString.length, headerSize);
    final fileVersion = versionBytes[0];
    if (fileVersion != version) {
      throw Exception('Unsupported file version: $fileVersion');
    }

    final hintLengthOffset = headerSize;
    final hintLength = bytes[hintLengthOffset];
    final dataOffset = hintLengthOffset + 1 + hintLength;

    final iv = encrypt.IV(bytes.sublist(dataOffset, dataOffset + 16));
    final encryptedData = bytes.sublist(dataOffset + 16);

    try {
      if (useRustCrypto) {
        final passwordBytes = utf8.encode(password);
        return RustCrypto.decryptData(encryptedData, passwordBytes, iv.bytes);
      } else {
        final key = encrypt.Key(_deriveKey(password));
        final encrypter = encrypt.Encrypter(encrypt.AES(key));
        final decrypted = encrypter.decryptBytes(
          encrypt.Encrypted(encryptedData),
          iv: iv,
        );
        return Uint8List.fromList(decrypted);
      }
    } catch (e) {
      throw Exception('Invalid password or corrupted file');
    }
  }

  static Future<void> decryptFileToPath(
    String inputPath,
    String outputPath,
    String password,
  ) async {
    final decryptedData = await decryptFile(inputPath, password);
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(decryptedData);
  }

  static String addEncryptedExtension(String filename) {
    return '$filename.$encryptedExtension';
  }

  static String removeEncryptedExtension(String filename) {
    if (filename.endsWith('.$encryptedExtension')) {
      return filename.substring(
        0,
        filename.length - encryptedExtension.length - 1,
      );
    }
    return filename;
  }
}