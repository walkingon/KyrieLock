import 'package:flutter/material.dart';

class ProgressDialog extends StatelessWidget {
  final String title;
  final int currentProgress;
  final int totalProgress;
  final String? currentFileName;

  const ProgressDialog({
    super.key,
    required this.title,
    required this.currentProgress,
    required this.totalProgress,
    this.currentFileName,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalProgress > 0 ? currentProgress / totalProgress : 0.0;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 16),
            Text(
              '进度: $currentProgress / $totalProgress',
              style: const TextStyle(fontSize: 14),
            ),
            if (currentFileName != null) ...[
              const SizedBox(height: 8),
              Text(
                '当前文件: $currentFileName',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static void show(
    BuildContext context, {
    required String title,
    required int currentProgress,
    required int totalProgress,
    String? currentFileName,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProgressDialog(
        title: title,
        currentProgress: currentProgress,
        totalProgress: totalProgress,
        currentFileName: currentFileName,
      ),
    );
  }

  static void update(
    BuildContext context, {
    required String title,
    required int currentProgress,
    required int totalProgress,
    String? currentFileName,
  }) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    show(
      context,
      title: title,
      currentProgress: currentProgress,
      totalProgress: totalProgress,
      currentFileName: currentFileName,
    );
  }

  static void hide(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }
}