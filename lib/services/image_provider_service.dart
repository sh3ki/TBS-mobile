import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ImageProviderService extends ChangeNotifier {
  static final ImageProviderService _instance = ImageProviderService._internal();

  factory ImageProviderService() {
    return _instance;
  }

  ImageProviderService._internal();

  // Cache images per container number (keyed by containerNo)
  final Map<String, List<File>> _cache = {};
  // Cache uploaded images per container number
  final Map<String, List<File>> _uploadedCache = {};

  // Current active container key
  String? _currentContainer;

  // Set the current container context. Creates cache entry if missing.
  void setCurrentContainer(String containerNo) {
    _currentContainer = containerNo.trim().toUpperCase();
    _cache.putIfAbsent(_currentContainer!, () => []);
    notifyListeners();
    // Load any persisted uploaded images for this container in background
    _loadCachedUploadedFor(_currentContainer!);
  }

  // Persisted cache file name
  Future<File> get _cacheIndexFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/image_cache_index.json');
  }

  // Load cached uploaded images for a container (background)
  Future<void> _loadCachedUploadedFor(String containerNo) async {
    try {
      final f = await _cacheIndexFile;
      if (!f.existsSync()) return;
      final content = await f.readAsString();
      if (content.trim().isEmpty) return;
      final Map<String, dynamic> data = json.decode(content) as Map<String, dynamic>;
      final entries = (data[containerNo] as List?)?.cast<String>() ?? [];
      if (entries.isEmpty) return;

      final List<File> files = [];
      for (final p in entries) {
        final file = File(p);
        if (file.existsSync()) files.add(file);
      }

      if (files.isNotEmpty) {
        final list = _uploadedCache.putIfAbsent(containerNo, () => []);
        final existing = list.map((e) => e.path).toSet();
        for (final file in files) {
          if (!existing.contains(file.path)) {
            list.add(file);
            existing.add(file.path);
          }
        }
        notifyListeners();
      }
    } catch (_) {
      // ignore cache load errors
    }
  }

  // Save current uploaded cache index to disk (async, fire-and-forget)
  Future<void> _saveCacheIndex() async {
    try {
      final f = await _cacheIndexFile;
      final Map<String, List<String>> out = {};
      _uploadedCache.forEach((key, list) {
        out[key] = list.map((e) => e.path).toList();
      });
      await f.writeAsString(json.encode(out));
    } catch (_) {
      // ignore save errors
    }
  }

  // Get images for current container
  List<File> get images {
    if (_currentContainer == null) return [];
    return _cache[_currentContainer!] ?? [];
  }

  // Get uploaded images for current container
  List<File> get uploadedImages {
    if (_currentContainer == null) return [];
    return _uploadedCache[_currentContainer!] ?? [];
  }

  // Get images for a specific container
  List<File> imagesFor(String containerNo) {
    return _cache[containerNo.trim().toUpperCase()] ?? [];
  }

  void addImage(File image) {
    if (_currentContainer == null) return;
    final list = _cache.putIfAbsent(_currentContainer!, () => []);
    list.add(image);
    notifyListeners();
  }

  void addUploadedImage(File image) {
    if (_currentContainer == null) return;
    final list = _uploadedCache.putIfAbsent(_currentContainer!, () => []);
    // avoid duplicates by path
    final exists = list.any((f) => f.path == image.path);
    if (!exists) list.add(image);
    notifyListeners();
    // persist index
    _saveCacheIndex();
  }

  void addUploadedImages(List<File> images) {
    if (_currentContainer == null) return;
    final list = _uploadedCache.putIfAbsent(_currentContainer!, () => []);
    final existingPaths = list.map((f) => f.path).toSet();
    for (final img in images) {
      if (!existingPaths.contains(img.path)) {
        list.add(img);
        existingPaths.add(img.path);
      }
    }
    notifyListeners();
    // persist index
    _saveCacheIndex();
  }

  // Remove a specific file from the camera-taken images list (by reference)
  void removeImageByFile(File file) {
    if (_currentContainer == null) return;
    final list = _cache[_currentContainer!];
    if (list == null) return;
    final idx = list.indexWhere((f) => f.path == file.path);
    if (idx != -1) {
      list.removeAt(idx);
      notifyListeners();
    }
  }

  void removeImage(int index) {
    if (_currentContainer == null) return;
    final list = _cache[_currentContainer!];
    if (list == null) return;
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      notifyListeners();
    }
  }

  // Clear images for current container
  void clearAll({String? containerNo}) {
    if (containerNo != null) {
      _cache.remove(containerNo.trim().toUpperCase());
    } else if (_currentContainer != null) {
      _cache[_currentContainer!] = [];
    } else {
      _cache.clear();
    }
    notifyListeners();
  }

  // Clear uploaded images for current or specified container
  void clearUploaded({String? containerNo}) {
    if (containerNo != null) {
      _uploadedCache.remove(containerNo.trim().toUpperCase());
    } else if (_currentContainer != null) {
      _uploadedCache[_currentContainer!] = [];
    } else {
      _uploadedCache.clear();
    }
    notifyListeners();
    _saveCacheIndex();
  }

  int get count => images.length;
}
