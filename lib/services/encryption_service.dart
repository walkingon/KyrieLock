import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'rust_crypto.dart';

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

  static Uint8List _deriveKey(String password) {
    return RustCrypto.deriveKey(utf8.encode(password));
  }

  static Future<void> encryptFile(
    String inputPath,
    String outputPath,
    String password, {
    String? hint,
  }) async {
    final startTime = DateTime.now();
    final inputFile = File(inputPath);
    final outputFile = File(outputPath);

    if (!await inputFile.exists()) {
      throw Exception('Input file does not exist');
    }

    final fileSize = await inputFile.length();
    const int chunkSize = 64 * 1024 * 1024;
    print('[ENCRYPT] Starting encryption: fileSize=$fileSize, chunkSize=$chunkSize');

    final iv = encrypt.IV.fromLength(16);

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

    final outputSink = outputFile.openWrite();
    try {
      outputSink.add(header.toBytes());
      outputSink.add([hintLength]);
      outputSink.add(hintBytes);
      outputSink.add(iv.bytes);

      if (fileSize <= chunkSize) {
        print('[ENCRYPT] Small file, encrypting as single chunk');
        final bytes = await inputFile.readAsBytes();
        final passwordBytes = utf8.encode(password);
        final encryptedBytes = RustCrypto.encryptData(bytes, passwordBytes, iv.bytes);
        print('[ENCRYPT] Encrypted size: ${encryptedBytes.length}');
        outputSink.add(encryptedBytes);
      } else {
        print('[ENCRYPT] Large file, encrypting in chunks');
        final inputStream = inputFile.openRead();
        final buffer = <int>[];
        int chunkIndex = 0;
        
        await for (var chunk in inputStream) {
          buffer.addAll(chunk);
          
          while (buffer.length >= chunkSize) {
            final chunkData = Uint8List.fromList(buffer.sublist(0, chunkSize));
            buffer.removeRange(0, chunkSize);
            
            final passwordBytes = utf8.encode(password);
            final encryptedChunk = RustCrypto.encryptData(chunkData, passwordBytes, iv.bytes);
            
            print('[ENCRYPT] Chunk $chunkIndex: original=${chunkData.length}, encrypted=${encryptedChunk.length}');
            final chunkLengthBytes = ByteData(4);
            chunkLengthBytes.setUint32(0, encryptedChunk.length, Endian.big);
            outputSink.add(chunkLengthBytes.buffer.asUint8List());
            outputSink.add(encryptedChunk);
            chunkIndex++;
          }
        }
        
        if (buffer.isNotEmpty) {
          final lastChunk = Uint8List.fromList(buffer);
          final passwordBytes = utf8.encode(password);
          final encryptedChunk = RustCrypto.encryptData(lastChunk, passwordBytes, iv.bytes);
          
          print('[ENCRYPT] Last chunk $chunkIndex: original=${lastChunk.length}, encrypted=${encryptedChunk.length}');
          final chunkLengthBytes = ByteData(4);
          chunkLengthBytes.setUint32(0, encryptedChunk.length, Endian.big);
          outputSink.add(chunkLengthBytes.buffer.asUint8List());
          outputSink.add(encryptedChunk);
        }
        print('[ENCRYPT] Total chunks encrypted: ${chunkIndex + 1}');
      }

      await outputSink.flush();
    } finally {
      await outputSink.close();
    }
    
    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    print('[ENCRYPT] Total encryption time: ${duration.inMilliseconds}ms (${duration.inSeconds}s)');
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

  static Future<DecryptResult> decryptFile(String filePath, String password) async {
    final startTime = DateTime.now();
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist');
    }

    final fileSize = await file.length();
    const int chunkSize = 64 * 1024 * 1024;
    const int memoryThreshold = 100 * 1024 * 1024;
    print('[DECRYPT] Starting decryption: fileSize=$fileSize');

    final headerBytes = await file.openRead(0, headerSize + 1).first;
    final bytes = Uint8List.fromList(headerBytes);

    final magicBytes = bytes.sublist(0, magicString.length);
    final magic = utf8.decode(magicBytes);
    if (magic != magicString) {
      print('[DECRYPT] Error: Not an encrypted file, magic=$magic');
      throw Exception('Not an encrypted file');
    }

    final versionBytes = bytes.sublist(magicString.length, headerSize);
    final fileVersion = versionBytes[0];
    if (fileVersion != version) {
      print('[DECRYPT] Error: Unsupported version=$fileVersion');
      throw Exception('Unsupported file version: $fileVersion');
    }

    final hintLengthOffset = headerSize;
    final hintLength = bytes[hintLengthOffset];
    final dataOffset = hintLengthOffset + 1 + hintLength;
    print('[DECRYPT] Header parsed: hintLength=$hintLength, dataOffset=$dataOffset');

    final ivBytes = await file.openRead(dataOffset, dataOffset + 16).first;
    final iv = encrypt.IV(Uint8List.fromList(ivBytes));

    final encryptedDataStart = dataOffset + 16;
    final encryptedDataSize = fileSize - encryptedDataStart;
    print('[DECRYPT] Encrypted data: start=$encryptedDataStart, size=$encryptedDataSize');

    bool isChunked = false;
    if (encryptedDataSize > chunkSize) {
      final firstFourBytes = await file.openRead(encryptedDataStart, encryptedDataStart + 4).first;
      final possibleChunkLength = ByteData.sublistView(Uint8List.fromList(firstFourBytes)).getUint32(0, Endian.big);
      if (possibleChunkLength > 0 && possibleChunkLength <= encryptedDataSize - 4) {
        isChunked = true;
        print('[DECRYPT] Detected chunked encryption format (first chunk length: $possibleChunkLength)');
      }
    }

    if (!isChunked && encryptedDataSize <= memoryThreshold) {
      print('[DECRYPT] Small file (single chunk), decrypting in memory');
      final allBytes = await file.readAsBytes();
      final encryptedData = allBytes.sublist(encryptedDataStart);
      print('[DECRYPT] Small file (single chunk), decrypting in memory');
      print('[DECRYPT] Encrypted data length: ${encryptedData.length}');

      try {
        final passwordBytes = utf8.encode(password);
        final decrypted = RustCrypto.decryptData(encryptedData, passwordBytes, iv.bytes);
        print('[DECRYPT] Decrypted successfully: ${decrypted.length} bytes');
        final endTime = DateTime.now();
        final duration = endTime.difference(startTime);
        print('[DECRYPT] Total decryption time: ${duration.inMilliseconds}ms (${duration.inSeconds}s)');
        return DecryptResult.inMemory(decrypted);
      } catch (e) {
        print('[DECRYPT] Error during decryption: $e');
        throw Exception('Invalid password or corrupted file');
      }
    } else {
      print('[DECRYPT] Large file or chunked format detected (${(encryptedDataSize / 1024 / 1024).toStringAsFixed(2)} MB), decrypting to temp file');
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final originalExt = _getOriginalExtension(filePath);
      final tempFile = File(
        '${tempDir.path}/temp_decrypt_${timestamp}$originalExt',
      );

      try {
        await decryptFileToPath(filePath, tempFile.path, password);
        print('[DECRYPT] Large file decrypted successfully to temp file: ${tempFile.path}');
        final endTime = DateTime.now();
        final duration = endTime.difference(startTime);
        print('[DECRYPT] Total decryption time: ${duration.inMilliseconds}ms (${duration.inSeconds}s)');
        return DecryptResult.tempFile(tempFile.path);
      } catch (e) {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        rethrow;
      }
    }
  }

  static String _getOriginalExtension(String encryptedPath) {
    final fileName = encryptedPath.split(Platform.pathSeparator).last;
    if (fileName.endsWith('.$encryptedExtension')) {
      final originalName = fileName.substring(0, fileName.length - encryptedExtension.length - 1);
      final lastDot = originalName.lastIndexOf('.');
      if (lastDot != -1) {
        return originalName.substring(lastDot);
      }
    }
    return '';
  }

  static Future<void> decryptFileToPath(
    String inputPath,
    String outputPath,
    String password,
  ) async {
    final startTime = DateTime.now();
    final file = File(inputPath);
    if (!await file.exists()) {
      throw Exception('File does not exist');
    }

    final fileSize = await file.length();
    const int chunkSize = 64 * 1024 * 1024;
    print('[DECRYPT] Starting decryption: fileSize=$fileSize');

    final headerBytes = await file.openRead(0, headerSize + 1).first;
    final bytes = Uint8List.fromList(headerBytes);

    final magicBytes = bytes.sublist(0, magicString.length);
    final magic = utf8.decode(magicBytes);
    if (magic != magicString) {
      print('[DECRYPT] Error: Not an encrypted file, magic=$magic');
      throw Exception('Not an encrypted file');
    }

    final versionBytes = bytes.sublist(magicString.length, headerSize);
    final fileVersion = versionBytes[0];
    if (fileVersion != version) {
      print('[DECRYPT] Error: Unsupported version=$fileVersion');
      throw Exception('Unsupported file version: $fileVersion');
    }

    final hintLengthOffset = headerSize;
    final hintLength = bytes[hintLengthOffset];
    final dataOffset = hintLengthOffset + 1 + hintLength;
    print('[DECRYPT] Header parsed: hintLength=$hintLength, dataOffset=$dataOffset');

    final ivBytes = await file.openRead(dataOffset, dataOffset + 16).first;
    final iv = encrypt.IV(Uint8List.fromList(ivBytes));

    final encryptedDataStart = dataOffset + 16;
    final encryptedDataSize = fileSize - encryptedDataStart;
    print('[DECRYPT] Encrypted data: start=$encryptedDataStart, size=$encryptedDataSize');

    final outputFile = File(outputPath);
    final outputSink = outputFile.openWrite();

    try {
      bool isChunked = false;
      if (encryptedDataSize > chunkSize) {
        final firstFourBytes = await file.openRead(encryptedDataStart, encryptedDataStart + 4).first;
        final possibleChunkLength = ByteData.sublistView(Uint8List.fromList(firstFourBytes)).getUint32(0, Endian.big);
        if (possibleChunkLength > 0 && possibleChunkLength <= encryptedDataSize - 4) {
          isChunked = true;
        }
      }

      if (!isChunked && encryptedDataSize <= chunkSize) {
        print('[DECRYPT] Small file (single chunk), decrypting directly');
        final allBytes = await file.readAsBytes();
        final encryptedData = allBytes.sublist(encryptedDataStart);
        print('[DECRYPT] Encrypted data length: ${encryptedData.length}');

        final passwordBytes = utf8.encode(password);
        final decrypted = RustCrypto.decryptData(encryptedData, passwordBytes, iv.bytes);
        print('[DECRYPT] Decrypted successfully: ${decrypted.length} bytes');
        outputSink.add(decrypted);
      } else {
        print('[DECRYPT] Chunked file format detected, decrypting in chunks');
        final inputStream = file.openRead(encryptedDataStart);
        int chunkIndex = 0;
        var currentChunkData = <int>[];
        int? expectedChunkLength;

        await for (var chunk in inputStream) {
          var offset = 0;
          
          while (offset < chunk.length) {
            if (expectedChunkLength == null) {
              if (currentChunkData.length < 4) {
                final needed = 4 - currentChunkData.length;
                final available = chunk.length - offset;
                final toTake = available < needed ? available : needed;
                currentChunkData.addAll(chunk.sublist(offset, offset + toTake));
                offset += toTake;
                
                if (currentChunkData.length == 4) {
                  final lengthBytes = ByteData.sublistView(Uint8List.fromList(currentChunkData));
                  expectedChunkLength = lengthBytes.getUint32(0, Endian.big);
                  print('[DECRYPT] Chunk $chunkIndex: expecting $expectedChunkLength bytes');
                  currentChunkData.clear();
                }
              }
            } else {
              final needed = expectedChunkLength - currentChunkData.length;
              final available = chunk.length - offset;
              final toTake = available < needed ? available : needed;
              currentChunkData.addAll(chunk.sublist(offset, offset + toTake));
              offset += toTake;
              
              if (currentChunkData.length == expectedChunkLength) {
                final chunkData = Uint8List.fromList(currentChunkData);
                
                final passwordBytes = utf8.encode(password);
                final decryptedChunk = RustCrypto.decryptData(chunkData, passwordBytes, iv.bytes);
                print('[DECRYPT] Chunk $chunkIndex decrypted: ${decryptedChunk.length} bytes');
                outputSink.add(decryptedChunk);
                chunkIndex++;
                
                currentChunkData.clear();
                expectedChunkLength = null;
              }
            }
          }
        }

        print('[DECRYPT] Total chunks decrypted: $chunkIndex');
      }

      await outputSink.flush();
      print('[DECRYPT] Decryption completed successfully');
    } catch (e) {
      print('[DECRYPT] Error during decryption: $e');
      throw Exception('Invalid password or corrupted file');
    } finally {
      await outputSink.close();
    }
    
    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    print('[DECRYPT] Total decryption time: ${duration.inMilliseconds}ms (${duration.inSeconds}s)');
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