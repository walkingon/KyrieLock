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
            
            Uint8List encryptedChunk;
            if (useRustCrypto) {
              final passwordBytes = utf8.encode(password);
              encryptedChunk = RustCrypto.encryptData(chunkData, passwordBytes, iv.bytes);
            } else {
              final key = encrypt.Key(_deriveKey(password));
              final encrypter = encrypt.Encrypter(encrypt.AES(key));
              final encrypted = encrypter.encryptBytes(chunkData, iv: iv);
              encryptedChunk = encrypted.bytes;
            }
            
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
          Uint8List encryptedChunk;
          if (useRustCrypto) {
            final passwordBytes = utf8.encode(password);
            encryptedChunk = RustCrypto.encryptData(lastChunk, passwordBytes, iv.bytes);
          } else {
            final key = encrypt.Key(_deriveKey(password));
            final encrypter = encrypt.Encrypter(encrypt.AES(key));
            final encrypted = encrypter.encryptBytes(lastChunk, iv: iv);
            encryptedChunk = encrypted.bytes;
          }
          
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

    if (encryptedDataSize <= chunkSize * 2) {
      print('[DECRYPT] Small file, decrypting as single chunk');
      final allBytes = await file.readAsBytes();
      final encryptedData = allBytes.sublist(encryptedDataStart);
      print('[DECRYPT] Encrypted data length: ${encryptedData.length}');

      try {
        if (useRustCrypto) {
          final passwordBytes = utf8.encode(password);
          final decrypted = RustCrypto.decryptData(encryptedData, passwordBytes, iv.bytes);
          print('[DECRYPT] Decrypted successfully: ${decrypted.length} bytes');
          return decrypted;
        } else {
          final key = encrypt.Key(_deriveKey(password));
          final encrypter = encrypt.Encrypter(encrypt.AES(key));
          final decrypted = encrypter.decryptBytes(
            encrypt.Encrypted(encryptedData),
            iv: iv,
          );
          print('[DECRYPT] Decrypted successfully: ${decrypted.length} bytes');
          return Uint8List.fromList(decrypted);
        }
      } catch (e) {
        print('[DECRYPT] Error during decryption: $e');
        throw Exception('Invalid password or corrupted file');
      }
    } else {
      print('[DECRYPT] Large file, decrypting in chunks');
      final inputStream = file.openRead(encryptedDataStart);
      final decryptedData = BytesBuilder();
      int chunkIndex = 0;
      var currentChunkData = <int>[];
      int? expectedChunkLength;

      try {
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
                
                Uint8List decryptedChunk;
                if (useRustCrypto) {
                  final passwordBytes = utf8.encode(password);
                  decryptedChunk = RustCrypto.decryptData(chunkData, passwordBytes, iv.bytes);
                } else {
                  final key = encrypt.Key(_deriveKey(password));
                  final encrypter = encrypt.Encrypter(encrypt.AES(key));
                  final decrypted = encrypter.decryptBytes(
                    encrypt.Encrypted(chunkData),
                    iv: iv,
                  );
                  decryptedChunk = Uint8List.fromList(decrypted);
                }
                print('[DECRYPT] Chunk $chunkIndex decrypted: ${decryptedChunk.length} bytes');
                decryptedData.add(decryptedChunk);
                chunkIndex++;
                
                currentChunkData.clear();
                expectedChunkLength = null;
              }
            }
          }
        }

        print('[DECRYPT] Total chunks decrypted: $chunkIndex');
        final result = decryptedData.toBytes();
        print('[DECRYPT] Total decrypted size: ${result.length} bytes');
        return result;
      } catch (e) {
        print('[DECRYPT] Error during chunked decryption: $e');
        throw Exception('Invalid password or corrupted file');
      }
    }
  }

  static Future<void> decryptFileToPath(
    String inputPath,
    String outputPath,
    String password,
  ) async {
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
      if (encryptedDataSize <= chunkSize * 2) {
        print('[DECRYPT] Small file, decrypting as single chunk');
        final allBytes = await file.readAsBytes();
        final encryptedData = allBytes.sublist(encryptedDataStart);
        print('[DECRYPT] Encrypted data length: ${encryptedData.length}');

        if (useRustCrypto) {
          final passwordBytes = utf8.encode(password);
          final decrypted = RustCrypto.decryptData(encryptedData, passwordBytes, iv.bytes);
          print('[DECRYPT] Decrypted successfully: ${decrypted.length} bytes');
          outputSink.add(decrypted);
        } else {
          final key = encrypt.Key(_deriveKey(password));
          final encrypter = encrypt.Encrypter(encrypt.AES(key));
          final decrypted = encrypter.decryptBytes(
            encrypt.Encrypted(encryptedData),
            iv: iv,
          );
          print('[DECRYPT] Decrypted successfully: ${decrypted.length} bytes');
          outputSink.add(decrypted);
        }
      } else {
        print('[DECRYPT] Large file, decrypting in chunks');
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
                
                Uint8List decryptedChunk;
                if (useRustCrypto) {
                  final passwordBytes = utf8.encode(password);
                  decryptedChunk = RustCrypto.decryptData(chunkData, passwordBytes, iv.bytes);
                } else {
                  final key = encrypt.Key(_deriveKey(password));
                  final encrypter = encrypt.Encrypter(encrypt.AES(key));
                  final decrypted = encrypter.decryptBytes(
                    encrypt.Encrypted(chunkData),
                    iv: iv,
                  );
                  decryptedChunk = Uint8List.fromList(decrypted);
                }
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