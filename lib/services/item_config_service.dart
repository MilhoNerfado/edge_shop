import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/item_config.dart';

class ItemSetupImportResult {
  final String directoryPath;
  final int importedItems;

  const ItemSetupImportResult({
    required this.directoryPath,
    required this.importedItems,
  });
}

class ItemConfigService {
  ItemConfigService._();
  static final ItemConfigService instance = ItemConfigService._();
  static const setupImportFolderName = 'item_setup_import';
  static const _importSignatureKey = 'item_setup_import_signature';

  static String _nameKey(int gi) => 'item_${gi}_name';
  static String _typeKey(int gi) => 'item_${gi}_icon_type';
  static String _codeKey(int gi) => 'item_${gi}_icon_code';
  static String _pathKey(int gi) => 'item_${gi}_image_path';
  static String _descriptionKey(int gi) => 'item_${gi}_description';

  Future<Directory> getSetupImportDirectory() async {
    final externalDir = await getExternalStorageDirectory();
    if (externalDir == null) {
      throw StateError('External storage directory is unavailable.');
    }

    final importDir = Directory('${externalDir.path}/$setupImportFolderName');
    if (!importDir.existsSync()) {
      importDir.createSync(recursive: true);
    }
    return importDir;
  }

  Future<ItemConfig> load(int giftIndex) async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_nameKey(giftIndex));
    final typeStr = prefs.getString(_typeKey(giftIndex)) ?? 'default';
    final code = prefs.getInt(_codeKey(giftIndex));
    final path = prefs.getString(_pathKey(giftIndex));
    final description = prefs.getString(_descriptionKey(giftIndex));

    IconType type;
    switch (typeStr) {
      case 'material':
        type = IconType.material;
      case 'image':
        type = IconType.image;
      default:
        type = IconType.defaultIcon;
    }

    return ItemConfig(
      customName: name,
      iconType: type,
      materialIconCode: code,
      imagePath: path,
      description: description,
    );
  }

  Future<void> saveName(int giftIndex, String? name) async {
    final prefs = await SharedPreferences.getInstance();
    if (name == null || name.trim().isEmpty) {
      await prefs.remove(_nameKey(giftIndex));
    } else {
      await prefs.setString(_nameKey(giftIndex), name);
    }
  }

  Future<void> saveDescription(int giftIndex, String? description) async {
    final prefs = await SharedPreferences.getInstance();
    if (description == null || description.trim().isEmpty) {
      await prefs.remove(_descriptionKey(giftIndex));
    } else {
      await prefs.setString(_descriptionKey(giftIndex), description);
    }
  }

  Future<void> saveIcon(int giftIndex, IconData icon) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_typeKey(giftIndex), 'material');
    await prefs.setInt(_codeKey(giftIndex), icon.codePoint);
    await prefs.remove(_pathKey(giftIndex));
  }

  // Copies the picked image into the app documents dir and persists the path.
  Future<void> saveImage(int giftIndex, String sourcePath) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final imgDir = Directory('${docsDir.path}/item_images');
    if (!imgDir.existsSync()) imgDir.createSync(recursive: true);

    final ext = sourcePath.split('.').last;
    final destPath = '${imgDir.path}/item_$giftIndex.$ext';
    await File(sourcePath).copy(destPath);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_typeKey(giftIndex), 'image');
    await prefs.remove(_codeKey(giftIndex));
    await prefs.setString(_pathKey(giftIndex), destPath);
  }

  Future<void> clearVisualConfig(int giftIndex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_typeKey(giftIndex));
    await prefs.remove(_codeKey(giftIndex));
    await prefs.remove(_pathKey(giftIndex));
  }

  Future<ItemSetupImportResult> importSetupBundle() async {
    final importDir = await getSetupImportDirectory();
    final configFile = File('${importDir.path}/config.json');
    if (!configFile.existsSync()) {
      throw FileSystemException(
        'Missing config.json in import directory',
        configFile.path,
      );
    }

    final decoded = jsonDecode(await configFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'config.json must contain a top-level object.',
      );
    }

    final items = decoded['items'];
    if (items is! List) {
      throw const FormatException('config.json must contain an "items" array.');
    }

    int importedItems = 0;
    final signature = await _buildImportSignature(importDir, items);
    for (final rawItem in items) {
      if (rawItem is! Map) {
        throw const FormatException('Each imported item must be an object.');
      }

      final item = Map<String, dynamic>.from(rawItem);
      final giftIndex = _parseGiftIndex(item['giftIndex']);
      await saveName(giftIndex, _readOptionalString(item['name']));
      await saveDescription(
        giftIndex,
        _readOptionalString(item['description']),
      );

      if (item.containsKey('image')) {
        final imageName = _readOptionalString(item['image']);
        if (imageName == null) {
          await clearVisualConfig(giftIndex);
        } else {
          final imageFile = File('${importDir.path}/$imageName');
          if (!imageFile.existsSync()) {
            throw FileSystemException(
              'Missing imported image file',
              imageFile.path,
            );
          }
          await saveImage(giftIndex, imageFile.path);
        }
      }

      importedItems++;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_importSignatureKey, signature);

    return ItemSetupImportResult(
      directoryPath: importDir.path,
      importedItems: importedItems,
    );
  }

  Future<bool> importSetupBundleIfChanged() async {
    final importDir = await getSetupImportDirectory();
    final configFile = File('${importDir.path}/config.json');
    if (!configFile.existsSync()) {
      return false;
    }

    final decoded = jsonDecode(await configFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'config.json must contain a top-level object.',
      );
    }

    final items = decoded['items'];
    if (items is! List) {
      throw const FormatException('config.json must contain an "items" array.');
    }

    final signature = await _buildImportSignature(importDir, items);
    final prefs = await SharedPreferences.getInstance();
    final previousSignature = prefs.getString(_importSignatureKey);
    if (previousSignature == signature) {
      return false;
    }

    await importSetupBundle();
    return true;
  }

  Future<void> reset(int giftIndex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nameKey(giftIndex));
    await prefs.remove(_typeKey(giftIndex));
    await prefs.remove(_codeKey(giftIndex));
    await prefs.remove(_pathKey(giftIndex));
    await prefs.remove(_descriptionKey(giftIndex));
  }

  int _parseGiftIndex(dynamic value) {
    final giftIndex = switch (value) {
      int v => v,
      num v => v.toInt(),
      String v => int.tryParse(v),
      _ => null,
    };

    if (giftIndex == null || giftIndex < 1 || giftIndex > 3) {
      throw FormatException(
        'giftIndex must be an integer from 1 to 3. Got: $value',
      );
    }
    return giftIndex;
  }

  String? _readOptionalString(dynamic value) {
    if (value == null) return null;
    if (value is! String) {
      throw FormatException(
        'Expected a string value, got ${value.runtimeType}.',
      );
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<String> _buildImportSignature(Directory importDir, List items) async {
    final buffer = StringBuffer();
    for (final rawItem in items) {
      if (rawItem is! Map) {
        throw const FormatException('Each imported item must be an object.');
      }

      final item = Map<String, dynamic>.from(rawItem);
      final giftIndex = _parseGiftIndex(item['giftIndex']);
      final name = _readOptionalString(item['name']) ?? '';
      final description = _readOptionalString(item['description']) ?? '';
      final imageName = _readOptionalString(item['image']) ?? '';
      buffer
        ..write(giftIndex)
        ..write('|')
        ..write(name)
        ..write('|')
        ..write(description)
        ..write('|')
        ..write(imageName);

      if (imageName.isNotEmpty) {
        final imageFile = File('${importDir.path}/$imageName');
        if (!imageFile.existsSync()) {
          throw FileSystemException(
            'Missing imported image file',
            imageFile.path,
          );
        }
        final stat = await imageFile.stat();
        buffer
          ..write('|')
          ..write(stat.size)
          ..write('|')
          ..write(stat.modified.millisecondsSinceEpoch);
      }

      buffer.write(';');
    }

    return buffer.toString();
  }
}
