import 'dart:io';
import 'package:flutter/material.dart';

class ImageProviderService extends ChangeNotifier {
  static final ImageProviderService _instance = ImageProviderService._internal();

  factory ImageProviderService() {
    return _instance;
  }

  ImageProviderService._internal();

  final List<File> _images = [];

  List<File> get images => _images;

  void addImage(File image) {
    _images.add(image);
    notifyListeners();
  }

  void removeImage(int index) {
    if (index >= 0 && index < _images.length) {
      _images.removeAt(index);
      notifyListeners();
    }
  }

  void clearAll() {
    _images.clear();
    notifyListeners();
  }

  int get count => _images.length;
}
