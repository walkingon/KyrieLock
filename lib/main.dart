import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'services/file_operations_service.dart';
import 'services/encryption_service.dart';
import 'services/file_viewer_service.dart';
import 'services/file_association_service.dart';
import 'widgets/progress_dialog.dart';
import 'screens/about_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await FileAssociationService.registerFileAssociation();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KyrieLock',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialFile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isAndroid) {
      _cleanupFilePickerCache();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  Future<void> _cleanupFilePickerCache() async {
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } catch (e) {
      debugPrint('Failed to clear file_picker cache: $e');
    }
  }

  Future<void> _checkInitialFile() async {
    final filePath = await FileAssociationService.getInitialFile();
    if (filePath != null && filePath.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _openFile(filePath);
      }
    }
  }

  Future<void> _openFile(String filePath) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final fileExists = await File(filePath).exists();
      if (!fileExists) {
        _showMessage('文件不存在: $filePath', isError: true);
        setState(() => _isProcessing = false);
        return;
      }

      final isEncrypted = await EncryptionService.isEncryptedFile(filePath);
      String? password;

      if (isEncrypted) {
        final hint = await EncryptionService.getPasswordHint(filePath);
        password = await _showPasswordDialog(hint: hint);
        if (password == null) {
          setState(() => _isProcessing = false);
          return;
        }
      }

      if (mounted) {
        await FileViewerService.openFile(
          context,
          filePath,
          password: password,
          isEncrypted: isEncrypted,
        );
      }
    } catch (e) {
      _showMessage('打开文件失败: $e', isError: true);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<Map<String, String?>?> _showEncryptPasswordDialog() async {
    final TextEditingController passwordController = TextEditingController();
    final TextEditingController confirmController = TextEditingController();
    final TextEditingController hintController = TextEditingController();

    return showDialog<Map<String, String?>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('设置加密密码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码',
                  hintText: '请输入密码',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '确认密码',
                  hintText: '请再次输入密码',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: hintController,
                decoration: const InputDecoration(
                  labelText: '密码提示(可选)',
                  hintText: '输入密码提示词,帮助回忆',
                ),
                maxLength: 32,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                if (passwordController.text.isEmpty) {
                  _showMessage('密码不能为空', isError: true);
                  return;
                }
                if (passwordController.text != confirmController.text) {
                  _showMessage('两次输入的密码不一致', isError: true);
                  return;
                }
                Navigator.pop(context, {
                  'password': passwordController.text,
                  'hint': hintController.text.isNotEmpty
                      ? hintController.text
                      : null,
                });
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _showPasswordDialog({
    bool isConfirm = false,
    String? hint,
  }) async {
    final TextEditingController passwordController = TextEditingController();
    final TextEditingController confirmController = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('输入密码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hint != null && hint.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: Colors.blue.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '提示: $hint',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码',
                  hintText: '请输入密码',
                ),
              ),
              if (isConfirm) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '确认密码',
                    hintText: '请再次输入密码',
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                if (passwordController.text.isEmpty) {
                  _showMessage('密码不能为空', isError: true);
                  return;
                }
                if (isConfirm &&
                    passwordController.text != confirmController.text) {
                  _showMessage('两次输入的密码不一致', isError: true);
                  return;
                }
                Navigator.pop(context, passwordController.text);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleOpenFile() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final filePath = await FileOperationsService.pickFile();
      if (filePath == null) {
        setState(() => _isProcessing = false);
        return;
      }

      final isEncrypted = await EncryptionService.isEncryptedFile(filePath);
      String? password;

      if (isEncrypted) {
        final hint = await EncryptionService.getPasswordHint(filePath);
        password = await _showPasswordDialog(hint: hint);
        if (password == null) {
          setState(() => _isProcessing = false);
          return;
        }
      }

      if (mounted) {
        await FileViewerService.openFile(
          context,
          filePath,
          password: password,
          isEncrypted: isEncrypted,
        );
      }
    } catch (e) {
      _showMessage('打开文件失败: $e', isError: true);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleEncryptFile() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final filePaths = await FileOperationsService.pickMultipleFiles();
      if (filePaths.isEmpty) {
        setState(() => _isProcessing = false);
        return;
      }

      final result = await _showEncryptPasswordDialog();
      if (result == null) {
        setState(() => _isProcessing = false);
        return;
      }

      if (mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('选择输出目录'),
              content: Text('即将加密 ${filePaths.length} 个文件\n请选择加密后文件的保存目录'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );

        if (confirmed != true) {
          setState(() => _isProcessing = false);
          return;
        }
      }

      final outputDirectory = await FileOperationsService.pickOutputDirectory();
      if (outputDirectory == null) {
        setState(() => _isProcessing = false);
        return;
      }

      int totalFiles = filePaths.length;
      int skippedFiles = 0;
      int successFiles = 0;

      for (int i = 0; i < filePaths.length; i++) {
        final filePath = filePaths[i];
        final fileName = filePath.split(Platform.pathSeparator).last;

        if (i == 0) {
          if (mounted) {
            ProgressDialog.show(
              context,
              title: '批量加密文件',
              currentProgress: i,
              totalProgress: totalFiles,
              currentFileName: fileName,
            );
          }
        } else {
          if (mounted) {
            ProgressDialog.update(
              context,
              title: '批量加密文件',
              currentProgress: i,
              totalProgress: totalFiles,
              currentFileName: fileName,
            );
          }
        }

        try {
          final isEncrypted = await EncryptionService.isEncryptedFile(filePath);
          if (isEncrypted) {
            skippedFiles++;
            continue;
          }

          await FileOperationsService.encryptFile(
            filePath,
            outputDirectory,
            result['password']!,
            hint: result['hint'],
          );
          successFiles++;
        } catch (e) {
          continue;
        }
      }

      if (mounted) {
        ProgressDialog.hide(context);
        _showMessage('加密完成: 成功 $successFiles 个, 跳过 $skippedFiles 个');
      }
    } catch (e) {
      if (mounted) {
        ProgressDialog.hide(context);
        _showMessage('加密失败: $e', isError: true);
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleDecryptFile() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final filePaths = await FileOperationsService.pickFilesForDecryption();
      if (filePaths.isEmpty) {
        setState(() => _isProcessing = false);
        return;
      }

      for (final filePath in filePaths) {
        final isEncrypted = await EncryptionService.isEncryptedFile(filePath);
        if (!isEncrypted) {
          _showMessage(
            '文件 ${filePath.split(Platform.pathSeparator).last} 不是加密文件，已跳过',
            isError: true,
          );
          continue;
        }
      }

      final encryptedFiles = [];
      for (final filePath in filePaths) {
        final isEncrypted = await EncryptionService.isEncryptedFile(filePath);
        if (isEncrypted) {
          encryptedFiles.add(filePath);
        }
      }

      if (encryptedFiles.isEmpty) {
        _showMessage('没有可解密的文件', isError: true);
        setState(() => _isProcessing = false);
        return;
      }

      final firstFilePath = encryptedFiles[0];
      final hint = await EncryptionService.getPasswordHint(firstFilePath);
      final password = await _showPasswordDialog(hint: hint);
      if (password == null) {
        setState(() => _isProcessing = false);
        return;
      }

      final outputDirectory = await FileOperationsService.pickOutputDirectory();
      if (outputDirectory == null) {
        _showMessage('未选择保存目录', isError: true);
        setState(() => _isProcessing = false);
        return;
      }

      int totalFiles = encryptedFiles.length;
      int successFiles = 0;
      int failedFiles = 0;

      for (int i = 0; i < encryptedFiles.length; i++) {
        final filePath = encryptedFiles[i];
        final fileName = filePath.split(Platform.pathSeparator).last;

        if (i == 0) {
          if (mounted) {
            ProgressDialog.show(
              context,
              title: '批量解密文件',
              currentProgress: i,
              totalProgress: totalFiles,
              currentFileName: fileName,
            );
          }
        } else {
          if (mounted) {
            ProgressDialog.update(
              context,
              title: '批量解密文件',
              currentProgress: i,
              totalProgress: totalFiles,
              currentFileName: fileName,
            );
          }
        }

        try {
          await FileOperationsService.decryptFile(
            filePath,
            outputDirectory,
            password,
          );
          successFiles++;
        } catch (e) {
          failedFiles++;

          final fileName = filePath.split(Platform.pathSeparator).last;
          final outputName = EncryptionService.removeEncryptedExtension(
            fileName,
          );
          final outputPath =
              '$outputDirectory${Platform.pathSeparator}$outputName';
          final failedFile = File(outputPath);
          if (await failedFile.exists()) {
            try {
              await failedFile.delete();
            } catch (deleteError) {}
          }
          continue;
        }
      }

      if (mounted) {
        ProgressDialog.hide(context);
        _showMessage('解密完成: 成功 $successFiles 个, 失败 $failedFiles 个');
      }
    } catch (e) {
      if (mounted) {
        ProgressDialog.hide(context);
        _showMessage('解密失败: $e', isError: true);
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KyrieLock'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.inversePrimary,
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_special,
                    size: 60,
                    color: Colors.deepPurple,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'KyrieLock',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('关于'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AboutScreen()),
                );
              },
            ),
          ],
        ),
      ),
      body: Center(
        child: _isProcessing
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.folder_special,
                    size: 100,
                    color: Colors.deepPurple,
                  ),
                  const SizedBox(height: 48),
                  _buildMenuButton(
                    icon: Icons.folder_open,
                    label: '打开文件',
                    onPressed: _handleOpenFile,
                  ),
                  const SizedBox(height: 16),
                  _buildMenuButton(
                    icon: Icons.lock,
                    label: '加密文件',
                    onPressed: _handleEncryptFile,
                  ),
                  const SizedBox(height: 16),
                  _buildMenuButton(
                    icon: Icons.lock_open,
                    label: '解密文件',
                    onPressed: _handleDecryptFile,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 200,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
