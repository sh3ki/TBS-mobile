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

  int get count => images.length;
}
