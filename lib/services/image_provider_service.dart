import 'dart:io';
import 'package:flutter/material.dart';

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
  }

  int get count => images.length;
}
