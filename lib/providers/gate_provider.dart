import 'package:flutter/foundation.dart';

import '../models/lookup_item.dart';
import '../models/pre_record_model.dart';
import '../services/gate_service.dart';

class GateProvider extends ChangeNotifier {
  final GateService _service = GateService();

  bool _isLoading = false;
  List<PreRecord> _preIn = const [];
  List<PreRecord> _preOut = const [];
  List<LookupItem> _clients = const [];

  bool get isLoading => _isLoading;
  List<PreRecord> get preIn => _preIn;
  List<PreRecord> get preOut => _preOut;
  List<LookupItem> get clients => _clients;

  Future<void> loadAll(String username) async {
    _isLoading = true;
    notifyListeners();

    try {
      final all = await _service.getPendingList(username);
      _preIn = all.where((e) => e.gateStatus.toUpperCase() == 'IN').toList();
      _preOut = all.where((e) => e.gateStatus.toUpperCase() == 'OUT').toList();
      _clients = await _service.getClients(username);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String> addPreIn({
    required String username,
    required String containerNo,
    required String clientHash,
  }) async {
    final message = await _service.addPreIn(
      username: username,
      containerNo: containerNo,
      clientHash: clientHash,
    );
    await loadAll(username);
    return message;
  }

  Future<String> addPreOut({
    required String username,
    required String plateNo,
    required String hauler,
  }) async {
    final message = await _service.addPreOut(
      username: username,
      plateNo: plateNo,
      hauler: hauler,
    );
    await loadAll(username);
    return message;
  }
}
