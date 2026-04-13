import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_strings.dart';
import '../models/item_config.dart';
import '../services/item_config_service.dart';

class ItemsConfigPage extends StatefulWidget {
  const ItemsConfigPage({super.key});

  @override
  State<ItemsConfigPage> createState() => _ItemsConfigPageState();
}

class _ItemsConfigPageState extends State<ItemsConfigPage> {
  final _service = ItemConfigService.instance;
  late final List<TextEditingController> _nameControllers;
  late final List<TextEditingController> _descControllers;
  List<ItemConfig> _configs = List.filled(3, const ItemConfig());
  AppStrings _strings = AppStrings.of('en');
  String? _importDirectoryPath;
  bool _importing = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _nameControllers = List.generate(3, (_) => TextEditingController());
    _descControllers = List.generate(3, (_) => TextEditingController());
    _loadConfigs();
    _loadImportDirectoryPath();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    setState(() => _strings = AppStrings.of(locale.languageCode));
  }

  @override
  void dispose() {
    for (final c in _nameControllers) {
      c.dispose();
    }
    for (final c in _descControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadConfigs() async {
    try {
      await _service.importSetupBundleIfChanged();
    } catch (e, st) {
      dev.log(
        'Item setup auto-import failed: $e',
        name: 'EdgeShop.Items',
        error: e,
        stackTrace: st,
        level: 1000,
      );
    }

    final configs = await Future.wait([
      _service.load(1),
      _service.load(2),
      _service.load(3),
    ]);
    if (!mounted) return;
    setState(() {
      _configs = configs;
      _loading = false;
      for (int i = 0; i < 3; i++) {
        _nameControllers[i].text = configs[i].customName ?? '';
        _descControllers[i].text = configs[i].description ?? '';
      }
    });
  }

  Future<void> _loadImportDirectoryPath() async {
    try {
      final importDir = await _service.getSetupImportDirectory();
      if (!mounted) return;
      setState(() => _importDirectoryPath = importDir.path);
    } catch (_) {
      if (!mounted) return;
      setState(() => _importDirectoryPath = null);
    }
  }

  Future<void> _importFromAdbBundle() async {
    setState(() => _importing = true);
    try {
      final result = await _service.importSetupBundle();
      await _loadConfigs();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${result.importedItems} item(s) from ${result.directoryPath}/config.json',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  Widget _buildImportCard() {
    final importPath = _importDirectoryPath ?? 'Loading import folder...';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.adb),
                SizedBox(width: 8),
                Text(
                  'ADB import',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Push config.json and any referenced images into this folder from your PC, then tap Import.',
            ),
            const SizedBox(height: 12),
            SelectableText(
              importPath,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Expected config.json shape: {"items":[{"giftIndex":1,"name":"Item","description":"Text","image":"item_1.png"}]}',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _importing ? null : _importFromAdbBundle,
                icon: _importing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: Text(_importing ? 'Importing…' : 'Import from ADB'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickIcon(int index) async {
    final picked = await showDialog<IconData>(
      context: context,
      builder: (_) => const _IconPickerDialog(),
    );
    if (picked == null) return;
    await _service.saveIcon(index + 1, picked);
    final updated = await _service.load(index + 1);
    if (!mounted) return;
    setState(() => _configs[index] = updated);
  }

  Future<void> _pickImage(int index) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
        ],
      ),
    );
    if (source == null) return;

    final file = await ImagePicker().pickImage(source: source);
    if (file == null) return;

    await _service.saveImage(index + 1, file.path);
    final updated = await _service.load(index + 1);
    if (!mounted) return;
    setState(() => _configs[index] = updated);
  }

  Future<void> _reset(int index) async {
    await _service.reset(index + 1);
    final updated = await _service.load(index + 1);
    if (!mounted) return;
    setState(() {
      _configs[index] = updated;
      _nameControllers[index].text = '';
      _descControllers[index].text = '';
    });
  }

  Widget _buildIconPreview(ItemConfig config) {
    switch (config.iconType) {
      case IconType.image:
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(config.imagePath!),
            width: 48,
            height: 48,
            fit: BoxFit.cover,
          ),
        );
      case IconType.material:
        return Icon(resolveCuratedItemIcon(config.materialIconCode), size: 48);
      case IconType.defaultIcon:
        return const Icon(Icons.card_giftcard, size: 48);
    }
  }

  Widget _buildItemCard(int index) {
    final config = _configs[index];
    final defaultName = _strings.giftNames[index];
    final resolvedName = config.customName ?? defaultName;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview
            Row(
              children: [
                _buildIconPreview(config),
                const SizedBox(width: 16),
                Text(resolvedName, style: const TextStyle(fontSize: 18)),
              ],
            ),
            const SizedBox(height: 12),
            // Name field
            TextField(
              controller: _nameControllers[index],
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: defaultName,
                border: const OutlineInputBorder(),
              ),
              onChanged: (val) async {
                await _service.saveName(index + 1, val.isEmpty ? null : val);
                final updated = await _service.load(index + 1);
                if (!mounted) return;
                setState(() => _configs[index] = updated);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descControllers[index],
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              onChanged: (val) async {
                await _service.saveDescription(index + 1, val);
                final updated = await _service.load(index + 1);
                if (!mounted) return;
                setState(() => _configs[index] = updated);
              },
            ),
            const SizedBox(height: 8),
            // Actions
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _pickIcon(index),
                  icon: const Icon(Icons.emoji_symbols, size: 18),
                  label: const Text('Pick Icon'),
                ),
                TextButton.icon(
                  onPressed: () => _pickImage(index),
                  icon: const Icon(Icons.image, size: 18),
                  label: const Text('Pick Image'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _reset(index),
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('Reset'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      children: [
        const SizedBox(height: 8),
        _buildImportCard(),
        _buildItemCard(0),
        _buildItemCard(1),
        _buildItemCard(2),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _IconPickerDialog extends StatelessWidget {
  const _IconPickerDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pick an icon'),
      content: SizedBox(
        width: double.maxFinite,
        child: GridView.builder(
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: curatedItemIcons.length,
          itemBuilder: (ctx, i) => InkWell(
            onTap: () => Navigator.pop(ctx, curatedItemIcons[i]),
            borderRadius: BorderRadius.circular(8),
            child: Icon(curatedItemIcons[i], size: 36),
          ),
        ),
      ),
    );
  }
}
