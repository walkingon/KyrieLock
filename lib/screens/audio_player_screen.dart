import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/encryption_service.dart';

class AudioPlayerScreen extends StatefulWidget {
  final String audioPath;
  final String? password;
  final bool isEncrypted;

  const AudioPlayerScreen({
    super.key,
    required this.audioPath,
    this.password,
    required this.isEncrypted,
  });

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isLoading = true;
  String? _errorMessage;
  File? _tempAudioFile;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      String audioPath;

      if (widget.isEncrypted && widget.password != null) {
        final decryptResult = await EncryptionService.decryptFile(
          widget.audioPath,
          widget.password!,
        );

        if (decryptResult.isLargeFile && decryptResult.tempFilePath != null) {
          audioPath = decryptResult.tempFilePath!;
          _tempAudioFile = File(audioPath);
        } else if (decryptResult.data != null) {
          final tempDir = Directory.systemTemp;
          final originalName = EncryptionService.removeEncryptedExtension(
            widget.audioPath.split(Platform.pathSeparator).last,
          );
          final ext = originalName.split('.').last;
          _tempAudioFile = File(
            '${tempDir.path}/temp_audio_${DateTime.now().millisecondsSinceEpoch}.$ext',
          );
          await _tempAudioFile!.writeAsBytes(decryptResult.data!);
          audioPath = _tempAudioFile!.path;
        } else {
          throw Exception('Invalid decrypt result');
        }
      } else {
        audioPath = widget.audioPath;
      }

      setState(() {
        _isLoading = false;
      });

      await _audioPlayer.setFilePath(audioPath);
      await _audioPlayer.play();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _cleanupTempFile();
    super.dispose();
  }

  void _cleanupTempFile() {
    if (_tempAudioFile != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        try {
          if (_tempAudioFile!.existsSync()) {
            _tempAudioFile!.deleteSync();
          }
        } catch (_) {
        }
      });
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return hours != '00' ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Player'),
        backgroundColor: Colors.deepPurple,
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
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.music_note,
                    size: 120,
                    color: Colors.deepPurple,
                  ),
                  const SizedBox(height: 40),
                  StreamBuilder<Duration>(
                    stream: _audioPlayer.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final duration = _audioPlayer.duration ?? Duration.zero;
                      
                      return Column(
                        children: [
                          Text(
                            '${_formatDuration(position)} / ${_formatDuration(duration)}',
                            style: const TextStyle(fontSize: 24),
                          ),
                          const SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Slider(
                              value: duration.inMilliseconds > 0 
                                  ? position.inMilliseconds.toDouble().clamp(0.0, duration.inMilliseconds.toDouble())
                                  : 0.0,
                              max: duration.inMilliseconds > 0 
                                  ? duration.inMilliseconds.toDouble() 
                                  : 1.0,
                              onChanged: duration.inMilliseconds > 0 
                                  ? (value) {
                                      _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                                    }
                                  : null,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_10),
                        iconSize: 40,
                        onPressed: () {
                          final position = _audioPlayer.position;
                          _audioPlayer.seek(position - const Duration(seconds: 10));
                        },
                      ),
                      const SizedBox(width: 20),
                      StreamBuilder<PlayerState>(
                        stream: _audioPlayer.playerStateStream,
                        builder: (context, snapshot) {
                          final playerState = snapshot.data;
                          final isPlaying = playerState?.playing ?? false;
                          
                          return IconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause_circle : Icons.play_circle,
                            ),
                            iconSize: 64,
                            onPressed: () {
                              if (isPlaying) {
                                _audioPlayer.pause();
                              } else {
                                _audioPlayer.play();
                              }
                            },
                          );
                        },
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        icon: const Icon(Icons.forward_10),
                        iconSize: 40,
                        onPressed: () {
                          final position = _audioPlayer.position;
                          _audioPlayer.seek(position + const Duration(seconds: 10));
                        },
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}