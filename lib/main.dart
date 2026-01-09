import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'services/file_operations_service.dart';
import 'services/encryption_service.dart';
import 'services/file_viewer_service.dart';
import 'services/file_association_service.dart';
import 'services/localization_service.dart';
import 'widgets/progress_dialog.dart';
import 'screens/about_screen.dart';
import 'screens/language_screen.dart';

// 密码长度限制常量
const int kPasswordMinLength = 4;
const int kPasswordMaxLength = 32;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize localization service before running the app
  await LocalizationService.getInstance();

  if (Platform.isWindows) {
    await FileAssociationService.registerFileAssociation();
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<LocalizationService> _localizationService;

  @override
  void initState() {
    super.initState();
    _localizationService = LocalizationService.getInstance();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LocalizationService>(
      future: _localizationService,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return MaterialApp(
            title: 'KyrieLock',
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final localizationService = snapshot.data!;

        return MaterialApp(
          title: localizationService.translate('appTitle'),
          locale: localizationService.currentLocale,
          localizationsDelegates: const [
            // Add delegates if needed for specific widgets
          ],
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
          ),
          home: HomePage(
            localizationService: localizationService,
            onLanguageChanged: _onLanguageChanged,
          ),
        );
      },
    );
  }

  void _onLanguageChanged() {
    setState(() {
      _localizationService = LocalizationService.getInstance();
    });
  }
}

class HomePage extends StatefulWidget {
  final LocalizationService localizationService;
  final VoidCallback onLanguageChanged;

  const HomePage({
    super.key,
    required this.localizationService,
    required this.onLanguageChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _isProcessing = false;

  // Helper to get translations
  String t(String key) => widget.localizationService.translate(key);

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
        _showMessage('${t('fileNotFound')}$filePath', isError: true);
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
      _showMessage('${t('openFileFailed')}$e', isError: true);
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
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final hintController = TextEditingController();

    return showDialog<Map<String, String?>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t('setPassword')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passwordController,
                obscureText: true,
                maxLength: kPasswordMaxLength,
                decoration: InputDecoration(
                  labelText: t('password'),
                  hintText: t('passwordPlaceholder'),
                  counterText: t('passwordLengthHint'),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                obscureText: true,
                maxLength: kPasswordMaxLength,
                decoration: InputDecoration(
                  labelText: t('confirmPassword'),
                  hintText: t('confirmPasswordPlaceholder'),
                  counterText: t('passwordLengthHint'),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: hintController,
                decoration: InputDecoration(
                  labelText: t('passwordHint'),
                  hintText: t('passwordHintPlaceholder'),
                ),
                maxLength: 32,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('cancel')),
            ),
            TextButton(
              onPressed: () {
                if (passwordController.text.isEmpty) {
                  _showMessage(t('passwordEmpty'), isError: true);
                  return;
                }
                final passwordLength = passwordController.text.length;
                if (passwordLength < kPasswordMinLength ||
                    passwordLength > kPasswordMaxLength) {
                  _showMessage(t('passwordLengthInvalid'), isError: true);
                  return;
                }
                if (passwordController.text != confirmController.text) {
                  _showMessage(t('passwordMismatch'), isError: true);
                  return;
                }
                Navigator.pop(context, {
                  'password': passwordController.text,
                  'hint': hintController.text.isNotEmpty
                      ? hintController.text
                      : null,
                });
              },
              child: Text(t('confirm')),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _showPasswordDialog({String? hint}) async {
    final passwordController = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t('enterPassword')),
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
                          '${t('hint')}$hint',
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
                maxLength: kPasswordMaxLength,
                decoration: InputDecoration(
                  labelText: t('password'),
                  hintText: t('passwordPlaceholder'),
                  counterText: t('passwordLengthHint'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('cancel')),
            ),
            TextButton(
              onPressed: () {
                if (passwordController.text.isEmpty) {
                  _showMessage(t('passwordEmpty'), isError: true);
                  return;
                }
                final passwordLength = passwordController.text.length;
                if (passwordLength < kPasswordMinLength ||
                    passwordLength > kPasswordMaxLength) {
                  _showMessage(t('passwordLengthInvalid'), isError: true);
                  return;
                }
                Navigator.pop(context, passwordController.text);
              },
              child: Text(t('confirm')),
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
      _showMessage('${t('openFileFailed')}$e', isError: true);
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
              title: Text(t('selectOutputDirectory')),
              content: Text(
                  '${t('aboutToEncrypt')}${filePaths.length}${t('filesSelectOutputDir')}'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(t('cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(t('confirm')),
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
              title: t('batchEncrypt'),
              currentProgress: i,
              totalProgress: totalFiles,
              currentFileName: fileName,
            );
          }
        } else {
          if (mounted) {
            ProgressDialog.update(
              context,
              title: t('batchEncrypt'),
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
        _showMessage(
            '${t('encryptCompleted')}$successFiles${t('skipped')}$skippedFiles 个');
      }
    } catch (e) {
      if (mounted) {
        ProgressDialog.hide(context);
        _showMessage('${t('encryptFailed')}$e', isError: true);
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

      final encryptedFiles = <String>[];
      for (final filePath in filePaths) {
        final isEncrypted = await EncryptionService.isEncryptedFile(filePath);
        if (isEncrypted) {
          encryptedFiles.add(filePath);
        } else {
          _showMessage(
            '${filePath.split(Platform.pathSeparator).last} ${t('notEncryptedFile')}',
            isError: true,
          );
        }
      }

      if (encryptedFiles.isEmpty) {
        _showMessage(t('noDecryptableFiles'), isError: true);
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
        _showMessage(t('noOutputDirectory'), isError: true);
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
              title: t('batchDecrypt'),
              currentProgress: i,
              totalProgress: totalFiles,
              currentFileName: fileName,
            );
          }
        } else {
          if (mounted) {
            ProgressDialog.update(
              context,
              title: t('batchDecrypt'),
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
            } catch (deleteError) {
              // Ignore deletion errors - file may have been already deleted
            }
          }
          continue;
        }
      }

      if (mounted) {
        ProgressDialog.hide(context);
        _showMessage(
            '${t('decryptCompleted')}$successFiles${t('failed')}$failedFiles 个');
      }
    } catch (e) {
      if (mounted) {
        ProgressDialog.hide(context);
        _showMessage('${t('decryptFailed')}$e', isError: true);
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('appTitle')),
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_special,
                    size: 60,
                    color: Colors.blueAccent,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t('appTitle'),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(t('language')),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => LanguageScreen(
                            onLanguageChanged: widget.onLanguageChanged,
                          )),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(t('about')),
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
                    color: Colors.blueAccent,
                  ),
                  const SizedBox(height: 48),
                  _buildMenuButton(
                    icon: Icons.folder_open,
                    label: t('openFile'),
                    onPressed: _handleOpenFile,
                  ),
                  const SizedBox(height: 16),
                  _buildMenuButton(
                    icon: Icons.lock,
                    label: t('encryptFile'),
                    onPressed: _handleEncryptFile,
                  ),
                  const SizedBox(height: 16),
                  _buildMenuButton(
                    icon: Icons.lock_open,
                    label: t('decryptFile'),
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
