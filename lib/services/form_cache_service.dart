import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class FormCacheService extends ChangeNotifier {
  static final FormCacheService _instance = FormCacheService._internal();
  factory FormCacheService() => _instance;
  FormCacheService._internal();

  final Map<String, Map<String, dynamic>> _inCache = {};
  final Map<String, Map<String, dynamic>> _outCache = {};

  String? _currentKey;
  String _currentGate = 'IN';

  Future<File> get _cacheFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/form_cache.json');
  }

  Future<void> _loadFromDisk() async {
    try {
      final f = await _cacheFile;
      if (!f.existsSync()) return;
      final content = await f.readAsString();
      if (content.trim().isEmpty) return;
      final Map<String, dynamic> data = json.decode(content) as Map<String, dynamic>;
      final inData = (data['IN'] as Map?)?.cast<String, dynamic>() ?? {};
      final outData = (data['OUT'] as Map?)?.cast<String, dynamic>() ?? {};

      _inCache.clear();
      _outCache.clear();

      inData.forEach((k, v) {
        _inCache[k] = (v as Map).cast<String, dynamic>();
      });
      outData.forEach((k, v) {
        _outCache[k] = (v as Map).cast<String, dynamic>();
      });
      // debug
      try {
        print('FormCacheService: loaded IN keys=${_inCache.keys.toList()} OUT keys=${_outCache.keys.toList()}');
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _saveToDisk() async {
    try {
      final f = await _cacheFile;
      final out = {
        'IN': _inCache,
        'OUT': _outCache,
      };
      await f.writeAsString(json.encode(out));
      try {
        print('FormCacheService: saved cache to disk (IN=${_inCache.length}, OUT=${_outCache.length})');
      } catch (_) {}
    } catch (_) {}
  }

  void setCurrent(String key, {required String gate}) {
    _currentKey = key.trim().toUpperCase();
    _currentGate = gate.toUpperCase();
    notifyListeners();
    try {
      print('FormCacheService: setCurrent key=$_currentKey gate=$_currentGate');
    } catch (_) {}
  }

  Map<String, dynamic>? getCached(String key, {required String gate}) {
    final k = key.trim().toUpperCase();
    if (gate.toUpperCase() == 'IN') return _inCache[k];
    return _outCache[k];
  }

  Future<void> saveForCurrent(Map<String, dynamic> data) async {
    if (_currentKey == null) return;
    if (_currentGate == 'IN') {
      _inCache[_currentKey!] = Map.from(data);
    } else {
      _outCache[_currentKey!] = Map.from(data);
    }
    try {
      print('FormCacheService: saving for key=$_currentKey gate=$_currentGate data=${data.keys.toList()}');
    } catch (_) {}
    await _saveToDisk();
    notifyListeners();
  }

  Future<void> loadAll() async {
    await _loadFromDisk();
    notifyListeners();
  }

  Future<void> clearFor(String key, {required String gate}) async {
    final k = key.trim().toUpperCase();
    if (gate.toUpperCase() == 'IN') {
      _inCache.remove(k);
    } else {
      _outCache.remove(k);
    }
    await _saveToDisk();
    notifyListeners();
  }
}
