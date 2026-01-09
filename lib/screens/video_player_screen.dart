import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_win/video_player_win.dart';
import 'package:chewie/chewie.dart';
import 'package:path_provider/path_provider.dart';
import '../services/encryption_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoPath;
  final String? password;
  final bool isEncrypted;

  const VideoPlayerScreen({
    super.key,
    required this.videoPath,
    this.password,
    required this.isEncrypted,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _errorMessage;
  File? _tempVideoFile;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      String videoPath;

      if (widget.isEncrypted && widget.password != null) {
        final decryptResult = await EncryptionService.decryptFile(
          widget.videoPath,
          widget.password!,
        );

        if (decryptResult.isLargeFile && decryptResult.tempFilePath != null) {
          videoPath = decryptResult.tempFilePath!;
          _tempVideoFile = File(videoPath);
        } else {
          final tempDir = await getTemporaryDirectory();
          _tempVideoFile = File(
            '${tempDir.path}/temp_video_${DateTime.now().millisecondsSinceEpoch}.mp4',
          );
          await _tempVideoFile!.writeAsBytes(decryptResult.data!);
          videoPath = _tempVideoFile!.path;
        }
      } else {
        videoPath = widget.videoPath;
      }

      if (!kIsWeb && Platform.isWindows) {
        WindowsVideoPlayer.registerWith();
      }

      _videoPlayerController = VideoPlayerController.file(File(videoPath));
      await _videoPlayerController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio,
      );

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    _cleanupTempFile();
    super.dispose();
  }

  Future<void> _cleanupTempFile() async {
    if (_tempVideoFile != null && _tempVideoFile!.existsSync()) {
      try {
        await _tempVideoFile!.delete();
      } catch (e) {
        debugPrint('Failed to delete temp video file: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Player'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : _errorMessage != null
            ? Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error: $_errorMessage',
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              )
            : _chewieController != null
            ? Chewie(controller: _chewieController!)
            : const Text('No video loaded'),
      ),
      backgroundColor: Colors.black,
    );
  }
}