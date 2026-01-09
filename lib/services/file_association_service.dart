import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class FileAssociationService {
  static const MethodChannel _channel =
      MethodChannel('com.walkingon.kyrielock/file_association');

  static Future<void> registerFileAssociation() async {
    if (Platform.isWindows) {
      await _registerWindowsFileAssociation();
    }
  }

  static Future<void> _registerWindowsFileAssociation() async {
    try {
      await _channel.invokeMethod('registerFileAssociation');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to register file association: $e');
      }
    }
  }

  static Future<String?> getInitialFile() async {
    try {
      return await _channel.invokeMethod('getInitialFile');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to get initial file: $e');
      }
    }
    return null;
  }
}