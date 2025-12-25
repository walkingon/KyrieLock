import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

class RustCrypto {
  static ffi.DynamicLibrary? _lib;
  
  static void _loadLibrary() {
    if (_lib != null) return;
    
    if (Platform.isWindows) {
      final exePath = Platform.resolvedExecutable;
      final exeDir = path.dirname(exePath);
      final dllPath = path.join(exeDir, 'rust_crypto.dll');
      _lib = ffi.DynamicLibrary.open(dllPath);
    } else if (Platform.isLinux) {
      _lib = ffi.DynamicLibrary.open('rust_crypto/target/release/librust_crypto.so');
    } else if (Platform.isMacOS) {
      _lib = ffi.DynamicLibrary.open('rust_crypto/target/release/librust_crypto.dylib');
    } else if (Platform.isAndroid) {
      _lib = ffi.DynamicLibrary.open('librust_crypto.so');
    } else if (Platform.isIOS) {
      _lib = ffi.DynamicLibrary.process();
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  static Uint8List encryptData(Uint8List data, Uint8List password, Uint8List iv) {
    _loadLibrary();
    
    final encryptFunc = _lib!.lookupFunction<
      ffi.Int32 Function(
        ffi.Pointer<ffi.Uint8> dataPtr,
        ffi.Size dataLen,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        ffi.Size passwordLen,
        ffi.Pointer<ffi.Uint8> ivPtr,
        ffi.Pointer<ffi.Uint8> outputPtr,
        ffi.Pointer<ffi.Size> outputLen,
      ),
      int Function(
        ffi.Pointer<ffi.Uint8> dataPtr,
        int dataLen,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        int passwordLen,
        ffi.Pointer<ffi.Uint8> ivPtr,
        ffi.Pointer<ffi.Uint8> outputPtr,
        ffi.Pointer<ffi.Size> outputLen,
      )
    >('encrypt_data');

    final dataPtr = _allocateUint8List(data);
    final passwordPtr = _allocateUint8List(password);
    final ivPtr = _allocateUint8List(iv);
    final outputLenPtr = calloc<ffi.Size>();

    try {
      var result = encryptFunc(
        dataPtr,
        data.length,
        passwordPtr,
        password.length,
        ivPtr,
        ffi.nullptr,
        outputLenPtr,
      );

      if (result != 0) {
        throw Exception('Encryption failed with code: $result');
      }

      final outputLen = outputLenPtr.value;
      final outputPtr = calloc<ffi.Uint8>(outputLen);

      try {
        result = encryptFunc(
          dataPtr,
          data.length,
          passwordPtr,
          password.length,
          ivPtr,
          outputPtr,
          outputLenPtr,
        );

        if (result != 0) {
          throw Exception('Encryption failed with code: $result');
        }

        return Uint8List.fromList(
          outputPtr.asTypedList(outputLen),
        );
      } finally {
        calloc.free(outputPtr);
      }
    } finally {
      calloc.free(dataPtr);
      calloc.free(passwordPtr);
      calloc.free(ivPtr);
      calloc.free(outputLenPtr);
    }
  }

  static Uint8List decryptData(
    Uint8List encrypted,
    Uint8List password,
    Uint8List iv,
  ) {
    _loadLibrary();
    
    final decryptFunc = _lib!.lookupFunction<
      ffi.Int32 Function(
        ffi.Pointer<ffi.Uint8> encryptedPtr,
        ffi.Size encryptedLen,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        ffi.Size passwordLen,
        ffi.Pointer<ffi.Uint8> ivPtr,
        ffi.Pointer<ffi.Uint8> outputPtr,
        ffi.Pointer<ffi.Size> outputLen,
      ),
      int Function(
        ffi.Pointer<ffi.Uint8> encryptedPtr,
        int encryptedLen,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        int passwordLen,
        ffi.Pointer<ffi.Uint8> ivPtr,
        ffi.Pointer<ffi.Uint8> outputPtr,
        ffi.Pointer<ffi.Size> outputLen,
      )
    >('decrypt_data');

    final encryptedPtr = _allocateUint8List(encrypted);
    final passwordPtr = _allocateUint8List(password);
    final ivPtr = _allocateUint8List(iv);
    final outputLenPtr = calloc<ffi.Size>();

    try {
      var result = decryptFunc(
        encryptedPtr,
        encrypted.length,
        passwordPtr,
        password.length,
        ivPtr,
        ffi.nullptr,
        outputLenPtr,
      );

      if (result != 0) {
        throw Exception('Decryption failed with code: $result');
      }

      final outputLen = outputLenPtr.value;
      final outputPtr = calloc<ffi.Uint8>(outputLen);

      try {
        result = decryptFunc(
          encryptedPtr,
          encrypted.length,
          passwordPtr,
          password.length,
          ivPtr,
          outputPtr,
          outputLenPtr,
        );

        if (result != 0) {
          throw Exception('Decryption failed with code: $result');
        }

        return Uint8List.fromList(
          outputPtr.asTypedList(outputLen),
        );
      } finally {
        calloc.free(outputPtr);
      }
    } finally {
      calloc.free(encryptedPtr);
      calloc.free(passwordPtr);
      calloc.free(ivPtr);
      calloc.free(outputLenPtr);
    }
  }

  static Uint8List deriveKey(Uint8List password) {
    _loadLibrary();
    
    final deriveKeyFunc = _lib!.lookupFunction<
      ffi.Int32 Function(
        ffi.Pointer<ffi.Uint8> passwordPtr,
        ffi.Size passwordLen,
        ffi.Pointer<ffi.Uint8> outputPtr,
      ),
      int Function(
        ffi.Pointer<ffi.Uint8> passwordPtr,
        int passwordLen,
        ffi.Pointer<ffi.Uint8> outputPtr,
      )
    >('derive_key_ffi');

    final passwordPtr = _allocateUint8List(password);
    final outputPtr = calloc<ffi.Uint8>(32);

    try {
      final result = deriveKeyFunc(passwordPtr, password.length, outputPtr);

      if (result != 0) {
        throw Exception('Key derivation failed with code: $result');
      }

      return Uint8List.fromList(outputPtr.asTypedList(32));
    } finally {
      calloc.free(passwordPtr);
      calloc.free(outputPtr);
    }
  }

  static ffi.Pointer<ffi.Uint8> _allocateUint8List(Uint8List list) {
    final ptr = calloc<ffi.Uint8>(list.length);
    for (var i = 0; i < list.length; i++) {
      ptr[i] = list[i];
    }
    return ptr;
  }
}