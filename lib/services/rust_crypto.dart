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

  static Uint8List encryptData(Uint8List data, Uint8List password, Uint8List nonce) {
    _loadLibrary();
    
    final encryptFunc = _lib!.lookupFunction<
      ffi.Int32 Function(
        ffi.Pointer<ffi.Uint8> dataPtr,
        ffi.Size dataLen,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        ffi.Size passwordLen,
        ffi.Pointer<ffi.Uint8> noncePtr,
        ffi.Pointer<ffi.Uint8> outputPtr,
        ffi.Pointer<ffi.Size> outputLen,
      ),
      int Function(
        ffi.Pointer<ffi.Uint8> dataPtr,
        int dataLen,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        int passwordLen,
        ffi.Pointer<ffi.Uint8> noncePtr,
        ffi.Pointer<ffi.Uint8> outputPtr,
        ffi.Pointer<ffi.Size> outputLen,
      )
    >('encrypt_data');

    final dataPtr = _allocateUint8List(data);
    final passwordPtr = _allocateUint8List(password);
    final noncePtr = _allocateUint8List(nonce);
    final outputLenPtr = calloc<ffi.Size>();

    try {
      var result = encryptFunc(
        dataPtr,
        data.length,
        passwordPtr,
        password.length,
        noncePtr,
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
          noncePtr,
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
      calloc.free(noncePtr);
      calloc.free(outputLenPtr);
    }
  }

  static Uint8List decryptData(
    Uint8List encrypted,
    Uint8List password,
    Uint8List nonce,
  ) {
    _loadLibrary();
    
    final decryptFunc = _lib!.lookupFunction<
      ffi.Int32 Function(
        ffi.Pointer<ffi.Uint8> encryptedPtr,
        ffi.Size encryptedLen,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        ffi.Size passwordLen,
        ffi.Pointer<ffi.Uint8> noncePtr,
        ffi.Pointer<ffi.Uint8> outputPtr,
        ffi.Pointer<ffi.Size> outputLen,
      ),
      int Function(
        ffi.Pointer<ffi.Uint8> encryptedPtr,
        int encryptedLen,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        int passwordLen,
        ffi.Pointer<ffi.Uint8> noncePtr,
        ffi.Pointer<ffi.Uint8> outputPtr,
        ffi.Pointer<ffi.Size> outputLen,
      )
    >('decrypt_data');

    final encryptedPtr = _allocateUint8List(encrypted);
    final passwordPtr = _allocateUint8List(password);
    final noncePtr = _allocateUint8List(nonce);
    final outputLenPtr = calloc<ffi.Size>();

    try {
      var result = decryptFunc(
        encryptedPtr,
        encrypted.length,
        passwordPtr,
        password.length,
        noncePtr,
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
          noncePtr,
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
      calloc.free(noncePtr);
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

  static List<Uint8List> encryptDataParallel(
    List<Uint8List> chunks,
    Uint8List password,
    List<Uint8List> nonces,
  ) {
    _loadLibrary();

    if (chunks.isEmpty || chunks.length != nonces.length) {
      throw ArgumentError('Chunks and nonces must have the same length');
    }

    final encryptFunc = _lib!.lookupFunction<
      ffi.Int32 Function(
        ffi.Pointer<ffi.Pointer<ffi.Uint8>> chunksPtr,
        ffi.Pointer<ffi.Size> chunkLens,
        ffi.Size numChunks,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        ffi.Size passwordLen,
        ffi.Pointer<ffi.Uint8> noncesPtr,
        ffi.Pointer<ffi.Pointer<ffi.Uint8>> outputsPtr,
        ffi.Pointer<ffi.Size> outputLens,
      ),
      int Function(
        ffi.Pointer<ffi.Pointer<ffi.Uint8>> chunksPtr,
        ffi.Pointer<ffi.Size> chunkLens,
        int numChunks,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        int passwordLen,
        ffi.Pointer<ffi.Uint8> noncesPtr,
        ffi.Pointer<ffi.Pointer<ffi.Uint8>> outputsPtr,
        ffi.Pointer<ffi.Size> outputLens,
      )
    >('encrypt_data_parallel');

    final numChunks = chunks.length;
    final chunkPtrs = calloc<ffi.Pointer<ffi.Uint8>>(numChunks);
    final chunkLens = calloc<ffi.Size>(numChunks);
    final passwordPtr = _allocateUint8List(password);
    
    final totalNonceSize = nonces.length * 12;
    final noncesPtr = calloc<ffi.Uint8>(totalNonceSize);
    for (var i = 0; i < nonces.length; i++) {
      for (var j = 0; j < 12; j++) {
        noncesPtr[i * 12 + j] = nonces[i][j];
      }
    }

    for (var i = 0; i < numChunks; i++) {
      chunkPtrs[i] = _allocateUint8List(chunks[i]);
      chunkLens[i] = chunks[i].length;
    }

    final outputPtrs = calloc<ffi.Pointer<ffi.Uint8>>(numChunks);
    final outputLens = calloc<ffi.Size>(numChunks);

    for (var i = 0; i < numChunks; i++) {
      outputPtrs[i] = ffi.nullptr;
    }

    try {
      var result = encryptFunc(
        chunkPtrs,
        chunkLens,
        numChunks,
        passwordPtr,
        password.length,
        noncesPtr,
        outputPtrs,
        outputLens,
      );

      if (result != 0) {
        throw Exception('Parallel encryption failed with code: $result');
      }

      for (var i = 0; i < numChunks; i++) {
        final len = outputLens[i];
        outputPtrs[i] = calloc<ffi.Uint8>(len);
      }

      result = encryptFunc(
        chunkPtrs,
        chunkLens,
        numChunks,
        passwordPtr,
        password.length,
        noncesPtr,
        outputPtrs,
        outputLens,
      );

      if (result != 0) {
        throw Exception('Parallel encryption failed with code: $result');
      }

      final results = <Uint8List>[];
      for (var i = 0; i < numChunks; i++) {
        final len = outputLens[i];
        results.add(Uint8List.fromList(outputPtrs[i].asTypedList(len)));
      }

      return results;
    } finally {
      for (var i = 0; i < numChunks; i++) {
        calloc.free(chunkPtrs[i]);
        if (outputPtrs[i] != ffi.nullptr) {
          calloc.free(outputPtrs[i]);
        }
      }
      calloc.free(chunkPtrs);
      calloc.free(chunkLens);
      calloc.free(passwordPtr);
      calloc.free(noncesPtr);
      calloc.free(outputPtrs);
      calloc.free(outputLens);
    }
  }

  static List<Uint8List> decryptDataParallel(
    List<Uint8List> chunks,
    Uint8List password,
    List<Uint8List> nonces,
  ) {
    _loadLibrary();

    if (chunks.isEmpty || chunks.length != nonces.length) {
      throw ArgumentError('Chunks and nonces must have the same length');
    }

    final decryptFunc = _lib!.lookupFunction<
      ffi.Int32 Function(
        ffi.Pointer<ffi.Pointer<ffi.Uint8>> chunksPtr,
        ffi.Pointer<ffi.Size> chunkLens,
        ffi.Size numChunks,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        ffi.Size passwordLen,
        ffi.Pointer<ffi.Uint8> noncesPtr,
        ffi.Pointer<ffi.Pointer<ffi.Uint8>> outputsPtr,
        ffi.Pointer<ffi.Size> outputLens,
      ),
      int Function(
        ffi.Pointer<ffi.Pointer<ffi.Uint8>> chunksPtr,
        ffi.Pointer<ffi.Size> chunkLens,
        int numChunks,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        int passwordLen,
        ffi.Pointer<ffi.Uint8> noncesPtr,
        ffi.Pointer<ffi.Pointer<ffi.Uint8>> outputsPtr,
        ffi.Pointer<ffi.Size> outputLens,
      )
    >('decrypt_data_parallel');

    final numChunks = chunks.length;
    final chunkPtrs = calloc<ffi.Pointer<ffi.Uint8>>(numChunks);
    final chunkLens = calloc<ffi.Size>(numChunks);
    final passwordPtr = _allocateUint8List(password);
    
    final totalNonceSize = nonces.length * 12;
    final noncesPtr = calloc<ffi.Uint8>(totalNonceSize);
    for (var i = 0; i < nonces.length; i++) {
      for (var j = 0; j < 12; j++) {
        noncesPtr[i * 12 + j] = nonces[i][j];
      }
    }

    for (var i = 0; i < numChunks; i++) {
      chunkPtrs[i] = _allocateUint8List(chunks[i]);
      chunkLens[i] = chunks[i].length;
    }

    final outputPtrs = calloc<ffi.Pointer<ffi.Uint8>>(numChunks);
    final outputLens = calloc<ffi.Size>(numChunks);

    for (var i = 0; i < numChunks; i++) {
      outputPtrs[i] = ffi.nullptr;
    }

    try {
      var result = decryptFunc(
        chunkPtrs,
        chunkLens,
        numChunks,
        passwordPtr,
        password.length,
        noncesPtr,
        outputPtrs,
        outputLens,
      );

      if (result != 0) {
        throw Exception('Parallel decryption failed with code: $result');
      }

      for (var i = 0; i < numChunks; i++) {
        final len = outputLens[i];
        outputPtrs[i] = calloc<ffi.Uint8>(len);
      }

      result = decryptFunc(
        chunkPtrs,
        chunkLens,
        numChunks,
        passwordPtr,
        password.length,
        noncesPtr,
        outputPtrs,
        outputLens,
      );

      if (result != 0) {
        throw Exception('Parallel decryption failed with code: $result');
      }

      final results = <Uint8List>[];
      for (var i = 0; i < numChunks; i++) {
        final len = outputLens[i];
        results.add(Uint8List.fromList(outputPtrs[i].asTypedList(len)));
      }

      return results;
    } finally {
      for (var i = 0; i < numChunks; i++) {
        calloc.free(chunkPtrs[i]);
        if (outputPtrs[i] != ffi.nullptr) {
          calloc.free(outputPtrs[i]);
        }
      }
      calloc.free(chunkPtrs);
      calloc.free(chunkLens);
      calloc.free(passwordPtr);
      calloc.free(noncesPtr);
      calloc.free(outputPtrs);
      calloc.free(outputLens);
    }
  }

  static void encryptFile(
    String inputPath,
    String outputPath,
    Uint8List password, {
    String? hint,
    bool isMobile = false,
  }) {
    _loadLibrary();

    final encryptFileFunc = _lib!.lookupFunction<
      ffi.Int32 Function(
        ffi.Pointer<ffi.Char> inputPathPtr,
        ffi.Pointer<ffi.Char> outputPathPtr,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        ffi.Size passwordLen,
        ffi.Pointer<ffi.Char> hintPtr,
        ffi.Bool isMobile,
        ffi.Size cpuCores,
      ),
      int Function(
        ffi.Pointer<ffi.Char> inputPathPtr,
        ffi.Pointer<ffi.Char> outputPathPtr,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        int passwordLen,
        ffi.Pointer<ffi.Char> hintPtr,
        bool isMobile,
        int cpuCores,
      )
    >('encrypt_file');

    final inputPathPtr = inputPath.toNativeUtf8().cast<ffi.Char>();
    final outputPathPtr = outputPath.toNativeUtf8().cast<ffi.Char>();
    final passwordPtr = _allocateUint8List(password);
    final hintPtr = hint != null 
        ? hint.toNativeUtf8().cast<ffi.Char>() 
        : ffi.nullptr;
    final cpuCores = Platform.numberOfProcessors;

    try {
      final result = encryptFileFunc(
        inputPathPtr,
        outputPathPtr,
        passwordPtr,
        password.length,
        hintPtr,
        isMobile,
        cpuCores,
      );

      if (result != 0) {
        throw Exception('File encryption failed with code: $result');
      }
    } finally {
      calloc.free(inputPathPtr);
      calloc.free(outputPathPtr);
      calloc.free(passwordPtr);
      if (hintPtr != ffi.nullptr) {
        calloc.free(hintPtr);
      }
    }
  }

  static void decryptFile(
    String inputPath,
    String outputPath,
    Uint8List password, {
    bool isMobile = false,
  }) {
    _loadLibrary();

    final decryptFileFunc = _lib!.lookupFunction<
      ffi.Int32 Function(
        ffi.Pointer<ffi.Char> inputPathPtr,
        ffi.Pointer<ffi.Char> outputPathPtr,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        ffi.Size passwordLen,
        ffi.Bool isMobile,
        ffi.Size cpuCores,
      ),
      int Function(
        ffi.Pointer<ffi.Char> inputPathPtr,
        ffi.Pointer<ffi.Char> outputPathPtr,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        int passwordLen,
        bool isMobile,
        int cpuCores,
      )
    >('decrypt_file');

    final inputPathPtr = inputPath.toNativeUtf8().cast<ffi.Char>();
    final outputPathPtr = outputPath.toNativeUtf8().cast<ffi.Char>();
    final passwordPtr = _allocateUint8List(password);
    final cpuCores = Platform.numberOfProcessors;

    try {
      final result = decryptFileFunc(
        inputPathPtr,
        outputPathPtr,
        passwordPtr,
        password.length,
        isMobile,
        cpuCores,
      );

      if (result != 0) {
        throw Exception('File decryption failed with code: $result');
      }
    } finally {
      calloc.free(inputPathPtr);
      calloc.free(outputPathPtr);
      calloc.free(passwordPtr);
    }
  }

  static Uint8List decryptFileToMemory(
    String inputPath,
    Uint8List password, {
    bool isMobile = false,
  }) {
    _loadLibrary();

    final decryptFileToMemoryFunc = _lib!.lookupFunction<
      ffi.Int32 Function(
        ffi.Pointer<ffi.Char> inputPathPtr,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        ffi.Size passwordLen,
        ffi.Pointer<ffi.Uint8> outputPtr,
        ffi.Pointer<ffi.Size> outputLen,
        ffi.Bool isMobile,
        ffi.Size cpuCores,
      ),
      int Function(
        ffi.Pointer<ffi.Char> inputPathPtr,
        ffi.Pointer<ffi.Uint8> passwordPtr,
        int passwordLen,
        ffi.Pointer<ffi.Uint8> outputPtr,
        ffi.Pointer<ffi.Size> outputLen,
        bool isMobile,
        int cpuCores,
      )
    >('decrypt_file_to_memory');

    final inputPathPtr = inputPath.toNativeUtf8().cast<ffi.Char>();
    final passwordPtr = _allocateUint8List(password);
    final outputLenPtr = calloc<ffi.Size>();
    final cpuCores = Platform.numberOfProcessors;

    try {
      var result = decryptFileToMemoryFunc(
        inputPathPtr,
        passwordPtr,
        password.length,
        ffi.nullptr,
        outputLenPtr,
        isMobile,
        cpuCores,
      );

      if (result != 0) {
        throw Exception('File decryption to memory failed with code: $result');
      }

      final outputLen = outputLenPtr.value;
      final outputPtr = calloc<ffi.Uint8>(outputLen);

      try {
        result = decryptFileToMemoryFunc(
          inputPathPtr,
          passwordPtr,
          password.length,
          outputPtr,
          outputLenPtr,
          isMobile,
          cpuCores,
        );

        if (result != 0) {
          throw Exception('File decryption to memory failed with code: $result');
        }

        return Uint8List.fromList(outputPtr.asTypedList(outputLen));
      } finally {
        calloc.free(outputPtr);
      }
    } finally {
      calloc.free(inputPathPtr);
      calloc.free(passwordPtr);
      calloc.free(outputLenPtr);
    }
  }

  static String getHintFromFile(String inputPath) {
    _loadLibrary();

    final getHintFunc = _lib!.lookupFunction<
      ffi.Int32 Function(
        ffi.Pointer<ffi.Char> inputPathPtr,
        ffi.Pointer<ffi.Uint8> hintPtr,
        ffi.Pointer<ffi.Size> hintLen,
      ),
      int Function(
        ffi.Pointer<ffi.Char> inputPathPtr,
        ffi.Pointer<ffi.Uint8> hintPtr,
        ffi.Pointer<ffi.Size> hintLen,
      )
    >('get_hint_from_file');

    final inputPathPtr = inputPath.toNativeUtf8().cast<ffi.Char>();
    final hintLenPtr = calloc<ffi.Size>();

    try {
      var result = getHintFunc(
        inputPathPtr,
        ffi.nullptr,
        hintLenPtr,
      );

      if (result != 0) {
        throw Exception('Get hint failed with code: $result');
      }

      final hintLen = hintLenPtr.value;
      if (hintLen == 0) {
        return '';
      }

      final hintPtr = calloc<ffi.Uint8>(hintLen);

      try {
        result = getHintFunc(
          inputPathPtr,
          hintPtr,
          hintLenPtr,
        );

        if (result != 0) {
          throw Exception('Get hint failed with code: $result');
        }

        final hintBytes = Uint8List.fromList(hintPtr.asTypedList(hintLen));
        return String.fromCharCodes(hintBytes);
      } finally {
        calloc.free(hintPtr);
      }
    } finally {
      calloc.free(inputPathPtr);
      calloc.free(hintLenPtr);
    }
  }
}