import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
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
        ? 128 *
              1048576 // 128MB for mobile
        : 256 * 1048576; // 256MB for desktop (避免过高参数导致UI阻塞)
  }

  static int get parallelBatchThreshold {
    return _isMobilePlatform
        ? 512 * 1048576  // 512MB for mobile (avoid OOM)
        : 1024 * 1048576; // 1GB for desktop
  }

  static int get parallelBatchSize {
    return _isMobilePlatform
        ? 4  // Process 4 chunks at a time (4×128MB=512MB)
        : 8; // Process 8 chunks at a time (8×256MB=2GB)
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
    if (kDebugMode) {
      debugPrint(
        '[ENCRYPT] Starting encryption: fileSize=$fileSize, chunkSize=$chunkSize',
      );
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

    final outputSink = outputFile.openWrite();
    try {
      outputSink.add(header.toBytes());
      outputSink.add([hintLength]);
      outputSink.add(hintBytes);

      if (fileSize <= chunkSize) {
        if (kDebugMode) {
          debugPrint('[ENCRYPT] Small file, encrypting as single chunk');
        }
        final nonce = encrypt.IV.fromLength(12);
        outputSink.add(nonce.bytes);
        
        final bytes = await inputFile.readAsBytes();
        final passwordBytes = utf8.encode(password);
        final encryptedBytes = RustCrypto.encryptData(
          bytes,
          passwordBytes,
          nonce.bytes,
        );
        if (kDebugMode) {
          debugPrint('[ENCRYPT] Encrypted size: ${encryptedBytes.length}');
        }
        outputSink.add(encryptedBytes);
      } else if (fileSize <= parallelBatchThreshold) {
        if (kDebugMode) {
          debugPrint('[ENCRYPT] Medium file, encrypting with full parallel processing');
        }
        
        final allBytes = await inputFile.readAsBytes();
        final chunks = <Uint8List>[];
        final nonces = <Uint8List>[];
        
        for (var offset = 0; offset < allBytes.length; offset += chunkSize) {
          final end = (offset + chunkSize < allBytes.length) 
              ? offset + chunkSize 
              : allBytes.length;
          chunks.add(Uint8List.sublistView(allBytes, offset, end));
          final chunkNonce = encrypt.IV.fromLength(12);
          nonces.add(chunkNonce.bytes);
        }
        
        if (kDebugMode) {
          debugPrint('[ENCRYPT] Total chunks to encrypt in parallel: ${chunks.length}');
        }
        
        final passwordBytes = utf8.encode(password);
        final encryptedChunks = RustCrypto.encryptDataParallel(
          chunks,
          passwordBytes,
          nonces,
        );
        
        if (kDebugMode) {
          debugPrint('[ENCRYPT] Parallel encryption completed, writing to file');
        }
        
        for (var i = 0; i < encryptedChunks.length; i++) {
          final encryptedChunk = encryptedChunks[i];
          if (kDebugMode) {
            debugPrint(
              '[ENCRYPT] Chunk $i: original=${chunks[i].length}, encrypted=${encryptedChunk.length}',
            );
          }
          outputSink.add(nonces[i]);
          final chunkLengthBytes = ByteData(4);
          chunkLengthBytes.setUint32(0, encryptedChunk.length, Endian.big);
          outputSink.add(chunkLengthBytes.buffer.asUint8List());
          outputSink.add(encryptedChunk);
        }
        
        if (kDebugMode) {
          debugPrint('[ENCRYPT] Total chunks encrypted: ${encryptedChunks.length}');
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            '[ENCRYPT] Large file (${(fileSize / 1048576).toStringAsFixed(2)} MB), using batched parallel encryption',
          );
        }
        
        final inputStream = inputFile.openRead();
        final buffer = <int>[];
        final passwordBytes = utf8.encode(password);
        var totalChunksProcessed = 0;
        
        final batchChunks = <Uint8List>[];
        final batchNonces = <Uint8List>[];
        
        await for (var chunk in inputStream) {
          buffer.addAll(chunk);
          
          while (buffer.length >= chunkSize) {
            final chunkData = Uint8List.fromList(buffer.sublist(0, chunkSize));
            buffer.removeRange(0, chunkSize);
            
            batchChunks.add(chunkData);
            final chunkNonce = encrypt.IV.fromLength(12);
            batchNonces.add(chunkNonce.bytes);
            
            if (batchChunks.length >= parallelBatchSize) {
              if (kDebugMode) {
                debugPrint(
                  '[ENCRYPT] Processing batch of ${batchChunks.length} chunks in parallel (chunks $totalChunksProcessed-${totalChunksProcessed + batchChunks.length - 1})',
                );
              }
              
              final encryptedBatch = RustCrypto.encryptDataParallel(
                batchChunks,
                passwordBytes,
                batchNonces,
              );
              
              for (var i = 0; i < encryptedBatch.length; i++) {
                outputSink.add(batchNonces[i]);
                final chunkLengthBytes = ByteData(4);
                chunkLengthBytes.setUint32(0, encryptedBatch[i].length, Endian.big);
                outputSink.add(chunkLengthBytes.buffer.asUint8List());
                outputSink.add(encryptedBatch[i]);
              }
              
              totalChunksProcessed += batchChunks.length;
              batchChunks.clear();
              batchNonces.clear();
            }
          }
        }
        
        if (buffer.isNotEmpty) {
          batchChunks.add(Uint8List.fromList(buffer));
          final chunkNonce = encrypt.IV.fromLength(12);
          batchNonces.add(chunkNonce.bytes);
        }
        
        if (batchChunks.isNotEmpty) {
          if (kDebugMode) {
            debugPrint(
              '[ENCRYPT] Processing final batch of ${batchChunks.length} chunks in parallel',
            );
          }
          
          final encryptedBatch = RustCrypto.encryptDataParallel(
            batchChunks,
            passwordBytes,
            batchNonces,
          );
          
          for (var i = 0; i < encryptedBatch.length; i++) {
            outputSink.add(batchNonces[i]);
            final chunkLengthBytes = ByteData(4);
            chunkLengthBytes.setUint32(0, encryptedBatch[i].length, Endian.big);
            outputSink.add(chunkLengthBytes.buffer.asUint8List());
            outputSink.add(encryptedBatch[i]);
          }
          
          totalChunksProcessed += batchChunks.length;
        }
        
        if (kDebugMode) {
          debugPrint('[ENCRYPT] Total chunks encrypted: $totalChunksProcessed');
        }
      }

      await outputSink.flush();
    } finally {
      await outputSink.close();
    }

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    if (kDebugMode) {
      debugPrint(
        '[ENCRYPT] Total encryption time: ${duration.inMilliseconds}ms (${duration.inSeconds}s)',
      );
    }
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
      final maxReadSize = headerSize + 1 + maxHintLength;
      final bytesStream = await file.openRead(0, maxReadSize).first;
      final bytes = Uint8List.fromList(bytesStream);

      if (bytes.length < headerSize + 1) {
        return null;
      }

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
    if (kDebugMode) {
      debugPrint('[DECRYPT] Starting decryption: fileSize=$fileSize');
    }

    final headerBytes = await file.openRead(0, headerSize + 1).first;
    final bytes = Uint8List.fromList(headerBytes);

    final magicBytes = bytes.sublist(0, magicString.length);
    final magic = utf8.decode(magicBytes);
    if (magic != magicString) {
      debugPrint('[DECRYPT] Error: Not an encrypted file, magic=$magic');
      throw Exception('Not an encrypted file');
    }

    final versionBytes = bytes.sublist(magicString.length, headerSize);
    final fileVersion = versionBytes[0];
    if (fileVersion != version) {
      debugPrint('[DECRYPT] Error: Unsupported version=$fileVersion');
      throw Exception('Unsupported file version: $fileVersion');
    }

    final hintLengthOffset = headerSize;
    final hintLength = bytes[hintLengthOffset];
    final dataOffset = hintLengthOffset + 1 + hintLength;
    debugPrint(
      '[DECRYPT] Header parsed: hintLength=$hintLength, dataOffset=$dataOffset',
    );

    final encryptedDataStart = dataOffset;
    final encryptedDataSize = fileSize - encryptedDataStart;
    if (kDebugMode) {
      debugPrint(
        '[DECRYPT] Encrypted data: start=$encryptedDataStart, size=$encryptedDataSize',
      );
    }

    bool isChunked = false;
    if (encryptedDataSize > chunkSize + 16) {
      final firstBytes = await file
          .openRead(encryptedDataStart, encryptedDataStart + 16)
          .first;
      if (firstBytes.length >= 16) {
        final possibleChunkLength = ByteData.sublistView(
          Uint8List.fromList(firstBytes),
          12,
          16,
        ).getUint32(0, Endian.big);
        if (possibleChunkLength > 0 &&
            possibleChunkLength <= encryptedDataSize - 16) {
          isChunked = true;
          if (kDebugMode) {
            debugPrint(
              '[DECRYPT] Detected chunked encryption format (first chunk length: $possibleChunkLength)',
            );
          }
        }
      }
    }

    if (!isChunked && encryptedDataSize <= chunkSize + 16) {
      if (kDebugMode) {
        debugPrint('[DECRYPT] Small file (single chunk), decrypting in memory');
      }
      final allBytes = await file.readAsBytes();
      final nonceBytes = allBytes.sublist(encryptedDataStart, encryptedDataStart + 12);
      final nonce = encrypt.IV(Uint8List.fromList(nonceBytes));
      final encryptedData = allBytes.sublist(encryptedDataStart + 12);
      if (kDebugMode) {
        debugPrint('[DECRYPT] Encrypted data length: ${encryptedData.length}');
      }

      try {
        final passwordBytes = utf8.encode(password);
        final decrypted = RustCrypto.decryptData(
          encryptedData,
          passwordBytes,
          nonce.bytes,
        );
        if (kDebugMode) {
          debugPrint(
            '[DECRYPT] Decrypted successfully: ${decrypted.length} bytes',
          );
        }
        final endTime = DateTime.now();
        final duration = endTime.difference(startTime);
        if (kDebugMode) {
          debugPrint(
            '[DECRYPT] Total decryption time: ${duration.inMilliseconds}ms (${duration.inSeconds}s)',
          );
        }
        return DecryptResult.inMemory(decrypted);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[DECRYPT] Error during decryption: $e');
        }
        throw Exception('Invalid password or corrupted file');
      }
    } else {
      if (kDebugMode) {
        debugPrint(
          '[DECRYPT] Large file or chunked format detected (${(encryptedDataSize / 1024 / 1024).toStringAsFixed(2)} MB), decrypting to temp file',
        );
      }
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final originalExt = _getOriginalExtension(filePath);
      final tempFile = File(
        '${tempDir.path}/temp_decrypt_$timestamp$originalExt',
      );

      try {
        await decryptFileToPath(filePath, tempFile.path, password);
        if (kDebugMode) {
          debugPrint(
            '[DECRYPT] Large file decrypted successfully to temp file: ${tempFile.path}',
          );
        }
        final endTime = DateTime.now();
        final duration = endTime.difference(startTime);
        if (kDebugMode) {
          debugPrint(
            '[DECRYPT] Total decryption time: ${duration.inMilliseconds}ms (${duration.inSeconds}s)',
          );
        }
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
      final originalName = fileName.substring(
        0,
        fileName.length - encryptedExtension.length - 1,
      );
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
    if (kDebugMode) {
      debugPrint('[DECRYPT] Starting decryption: fileSize=$fileSize');
    }

    final headerBytes = await file.openRead(0, headerSize + 1).first;
    final bytes = Uint8List.fromList(headerBytes);

    final magicBytes = bytes.sublist(0, magicString.length);
    final magic = utf8.decode(magicBytes);
    if (magic != magicString) {
      if (kDebugMode) {
        debugPrint('[DECRYPT] Error: Not an encrypted file, magic=$magic');
      }
      throw Exception('Not an encrypted file');
    }

    final versionBytes = bytes.sublist(magicString.length, headerSize);
    final fileVersion = versionBytes[0];
    if (fileVersion != version) {
      if (kDebugMode) {
        debugPrint('[DECRYPT] Error: Unsupported version=$fileVersion');
      }
      throw Exception('Unsupported file version: $fileVersion');
    }

    final hintLengthOffset = headerSize;
    final hintLength = bytes[hintLengthOffset];
    final dataOffset = hintLengthOffset + 1 + hintLength;
    if (kDebugMode) {
      debugPrint(
        '[DECRYPT] Header parsed: hintLength=$hintLength, dataOffset=$dataOffset',
      );
    }

    final encryptedDataStart = dataOffset;
    final encryptedDataSize = fileSize - encryptedDataStart;
    if (kDebugMode) {
      debugPrint(
        '[DECRYPT] Encrypted data: start=$encryptedDataStart, size=$encryptedDataSize',
      );
    }

    final outputFile = File(outputPath);
    final outputSink = outputFile.openWrite();

    try {
      bool isChunked = false;
      if (encryptedDataSize > chunkSize + 16) {
        final firstBytes = await file
            .openRead(encryptedDataStart, encryptedDataStart + 16)
            .first;
        if (firstBytes.length >= 16) {
          final possibleChunkLength = ByteData.sublistView(
            Uint8List.fromList(firstBytes),
            12,
            16,
          ).getUint32(0, Endian.big);
          if (possibleChunkLength > 0 &&
              possibleChunkLength <= encryptedDataSize - 16) {
            isChunked = true;
          }
        }
      }

      if (!isChunked && encryptedDataSize <= chunkSize + 16) {
        if (kDebugMode) {
          debugPrint(
            '[DECRYPT] Small file (single chunk), decrypting directly',
          );
        }
        final allBytes = await file.readAsBytes();
        final nonceBytes = allBytes.sublist(encryptedDataStart, encryptedDataStart + 12);
        final nonce = encrypt.IV(Uint8List.fromList(nonceBytes));
        final encryptedData = allBytes.sublist(encryptedDataStart + 12);
        if (kDebugMode) {
          debugPrint(
            '[DECRYPT] Encrypted data length: ${encryptedData.length}',
          );
        }

        final passwordBytes = utf8.encode(password);
        final decrypted = RustCrypto.decryptData(
          encryptedData,
          passwordBytes,
          nonce.bytes,
        );
        if (kDebugMode) {
          debugPrint(
            '[DECRYPT] Decrypted successfully: ${decrypted.length} bytes',
          );
        }
        outputSink.add(decrypted);
      } else if (encryptedDataSize <= parallelBatchThreshold) {
        if (kDebugMode) {
          debugPrint(
            '[DECRYPT] Medium file, decrypting with full parallel processing',
          );
        }
        
        final allData = await file.openRead(encryptedDataStart).toList();
        final allBytes = Uint8List.fromList(allData.expand((x) => x).toList());
        
        final encryptedChunks = <Uint8List>[];
        final nonces = <Uint8List>[];
        var offset = 0;
        
        while (offset < allBytes.length) {
          if (offset + 12 > allBytes.length) break;
          
          final nonceBytes = Uint8List.sublistView(allBytes, offset, offset + 12);
          nonces.add(nonceBytes);
          offset += 12;
          
          if (offset + 4 > allBytes.length) break;
          
          final lengthBytes = ByteData.sublistView(
            allBytes,
            offset,
            offset + 4,
          );
          final chunkLength = lengthBytes.getUint32(0, Endian.big);
          offset += 4;
          
          if (offset + chunkLength > allBytes.length) break;
          
          encryptedChunks.add(
            Uint8List.sublistView(allBytes, offset, offset + chunkLength),
          );
          offset += chunkLength;
        }
        
        if (kDebugMode) {
          debugPrint('[DECRYPT] Total chunks to decrypt in parallel: ${encryptedChunks.length}');
        }
        
        final passwordBytes = utf8.encode(password);
        final decryptedChunks = RustCrypto.decryptDataParallel(
          encryptedChunks,
          passwordBytes,
          nonces,
        );
        
        if (kDebugMode) {
          debugPrint('[DECRYPT] Parallel decryption completed, writing to file');
        }
        
        for (var i = 0; i < decryptedChunks.length; i++) {
          if (kDebugMode) {
            debugPrint(
              '[DECRYPT] Chunk $i decrypted: ${decryptedChunks[i].length} bytes',
            );
          }
          outputSink.add(decryptedChunks[i]);
        }
        
        if (kDebugMode) {
          debugPrint('[DECRYPT] Total chunks decrypted: ${decryptedChunks.length}');
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            '[DECRYPT] Large file (${(encryptedDataSize / 1048576).toStringAsFixed(2)} MB), using batched parallel decryption',
          );
        }
        
        final inputStream = file.openRead(encryptedDataStart);
        final passwordBytes = utf8.encode(password);
        var totalChunksProcessed = 0;
        
        final batchChunks = <Uint8List>[];
        final batchNonces = <Uint8List>[];
        var currentChunkData = <int>[];
        var currentNonce = <int>[];
        int? expectedChunkLength;
        var readingNonce = true;
        
        await for (var chunk in inputStream) {
          var offset = 0;
          
          while (offset < chunk.length) {
            if (readingNonce) {
              if (currentNonce.length < 12) {
                final needed = 12 - currentNonce.length;
                final available = chunk.length - offset;
                final toTake = available < needed ? available : needed;
                currentNonce.addAll(chunk.sublist(offset, offset + toTake));
                offset += toTake;
                
                if (currentNonce.length == 12) {
                  readingNonce = false;
                }
              }
            } else if (expectedChunkLength == null) {
              if (currentChunkData.length < 4) {
                final needed = 4 - currentChunkData.length;
                final available = chunk.length - offset;
                final toTake = available < needed ? available : needed;
                currentChunkData.addAll(chunk.sublist(offset, offset + toTake));
                offset += toTake;
                
                if (currentChunkData.length == 4) {
                  final lengthBytes = ByteData.sublistView(
                    Uint8List.fromList(currentChunkData),
                  );
                  expectedChunkLength = lengthBytes.getUint32(0, Endian.big);
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
                batchChunks.add(Uint8List.fromList(currentChunkData));
                batchNonces.add(Uint8List.fromList(currentNonce));
                
                currentChunkData.clear();
                currentNonce.clear();
                expectedChunkLength = null;
                readingNonce = true;
                
                if (batchChunks.length >= parallelBatchSize) {
                  if (kDebugMode) {
                    debugPrint(
                      '[DECRYPT] Processing batch of ${batchChunks.length} chunks in parallel (chunks $totalChunksProcessed-${totalChunksProcessed + batchChunks.length - 1})',
                    );
                  }
                  
                  final decryptedBatch = RustCrypto.decryptDataParallel(
                    batchChunks,
                    passwordBytes,
                    batchNonces,
                  );
                  
                  for (var decrypted in decryptedBatch) {
                    outputSink.add(decrypted);
                  }
                  
                  totalChunksProcessed += batchChunks.length;
                  batchChunks.clear();
                  batchNonces.clear();
                }
              }
            }
          }
        }
        
        if (batchChunks.isNotEmpty) {
          if (kDebugMode) {
            debugPrint(
              '[DECRYPT] Processing final batch of ${batchChunks.length} chunks in parallel',
            );
          }
          
          final decryptedBatch = RustCrypto.decryptDataParallel(
            batchChunks,
            passwordBytes,
            batchNonces,
          );
          
          for (var decrypted in decryptedBatch) {
            outputSink.add(decrypted);
          }
          
          totalChunksProcessed += batchChunks.length;
        }
        
        if (kDebugMode) {
          debugPrint('[DECRYPT] Total chunks decrypted: $totalChunksProcessed');
        }
      }

      await outputSink.flush();
      if (kDebugMode) {
        debugPrint('[DECRYPT] Decryption completed successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DECRYPT] Error during decryption: $e');
      }
      throw Exception('Invalid password or corrupted file');
    } finally {
      await outputSink.close();
    }

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    if (kDebugMode) {
      debugPrint(
        '[DECRYPT] Total decryption time: ${duration.inMilliseconds}ms (${duration.inSeconds}s)',
      );
    }
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