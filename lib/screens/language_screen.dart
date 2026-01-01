import 'package:flutter/material.dart';
import 'package:kyrie_lock/services/localization_service.dart';

class LanguageScreen extends StatefulWidget {
  final VoidCallback? onLanguageChanged;

  const LanguageScreen({super.key, this.onLanguageChanged});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  late Future<LocalizationService> _localizationService;

  @override
  void initState() {
    super.initState();
    _localizationService = LocalizationService.getInstance();
  }

  Future<String> _getTranslation(String key) async {
    final service = await LocalizationService.getInstance();
    return service.translate(key);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<String>(
          future: _getTranslation('languageSettings'),
          builder: (context, snapshot) {
            return Text(snapshot.data ?? '语言设置');
          },
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: FutureBuilder<LocalizationService>(
        future: _localizationService,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final localizationService = snapshot.data!;
          final currentLanguage = localizationService.currentLanguage;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FutureBuilder<String>(
                future: _getTranslation('selectLanguage'),
                builder: (context, snapshot) {
                  return Text(
                    snapshot.data ?? '选择语言',
                    style: Theme.of(context).textTheme.titleLarge,
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildLanguageOption(
                language: AppLanguage.chinese,
                isSelected: currentLanguage == AppLanguage.chinese,
                onTap: () => _selectLanguage(context, AppLanguage.chinese),
              ),
              _buildLanguageOption(
                language: AppLanguage.english,
                isSelected: currentLanguage == AppLanguage.english,
                onTap: () => _selectLanguage(context, AppLanguage.english),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLanguageOption({
    required AppLanguage language,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Icon(
          isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: isSelected ? Colors.blue : Colors.grey,
        ),
        title: Text(
          language.displayName,
          style: TextStyle(
            fontSize: 18,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        trailing: isSelected
            ? const Icon(Icons.check, color: Colors.blue)
            : null,
        onTap: onTap,
      ),
    );
  }

  Future<void> _selectLanguage(
    BuildContext context,
    AppLanguage language,
  ) async {
    // Get navigator state before async gap
    final navigator = Navigator.of(context);

    final localizationService = await LocalizationService.getInstance();
    await localizationService.setLanguage(language);

    // Notify parent to refresh
    if (widget.onLanguageChanged != null) {
      widget.onLanguageChanged!();
    }

    // Return to previous screen
    navigator.pop(true);
  }
}
