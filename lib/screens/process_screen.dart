import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

import '../models/lookup_item.dart';
import '../models/pre_record_model.dart';
import '../providers/auth_provider.dart';
import '../services/gate_service.dart';
import '../services/image_upload_service.dart';
import '../services/image_provider_service.dart';
import '../services/form_cache_service.dart';
import '../screens/continuous_camera_screen.dart';
import '../screens/image_preview_viewer.dart';
import '../utils/error_handler.dart';

class ProcessScreen extends StatefulWidget {
  const ProcessScreen({super.key, required this.record});

  final PreRecord record;

  @override
  State<ProcessScreen> createState() => _ProcessScreenState();
}

class ContainerSearchResult {
  final int id;
  final String containerNo;
  final String clientName;
  final int clientId;
  final String sizeType;
  final int sizeTypeId;
  final String isoCode;
  final String className;
  final String gateInRemarks;
  final String plateNo;
  final String hauler;

  ContainerSearchResult({
    required this.id,
    required this.containerNo,
    required this.clientName,
    required this.clientId,
    required this.sizeType,
    required this.sizeTypeId,
    required this.isoCode,
    required this.className,
    required this.gateInRemarks,
    required this.plateNo,
    required this.hauler,
  });
}

class _ProcessScreenState extends State<ProcessScreen> {
  static const int _maxTotalImages = 100;
  final GateService _gateService = GateService();
  final ImageUploadService _imageUploadService = ImageUploadService();
  final _imageProvider = ImageProviderService();
  final _formCache = FormCacheService();
  final ScrollController _formScrollController = ScrollController();
  final ScrollController _galleryScrollController = ScrollController();

  Timer? _searchDebounce;
  final _containerSearchKey = GlobalKey();
  OverlayEntry? _dropdownOverlay;

  // Image Upload Variables
  bool _uploadingImages = false;
  double _uploadProgress = 0.0;
  bool _showUploadProgress = false;
  StreamSubscription? _uploadSubscription;

  // Gate IN Controllers
  final _containerNoIn = TextEditingController();
  final _dateManufactured = TextEditingController();
  final _isoCodeIn = TextEditingController();
  final _remarksIn = TextEditingController();

  // Gate OUT Controllers
  final _containerNoOut = TextEditingController();
  final _isoCodeOut = TextEditingController();
  final _gateInRemarks = TextEditingController();
  final _remarksOut = TextEditingController();

  bool _loading = false;
  bool _submitting = false;
  bool _cameraEnabled = false;
  // Camera is only allowed after a successful submit
  bool _allowCamera = false;
  bool _showContainerDropdown = false;
  // Tracks whether the user has edited key fields since the last fetch/load
  bool _userEdited = false;
  // If true, the next fetch was triggered by a user selecting from the dropdown
  bool _lastFetchFromSelection = false;
  bool _isoFetched = false;
  bool _containerFetched = false;
  bool _refreshingUploadedImages = false;
  bool _refreshUploadedImagesQueued = false;
  String _imageDateCompleted = '';
  // Flag to prevent saving cache while applying cached values
  bool _applyingCache = false;
  // Flag to prevent listener side effects while hydrating Gate IN fields from API
  bool _hydratingGateInFromApi = false;
  List<ContainerSearchResult> _containerSearchResults = [];
  int? _selectedContainerId;

  // Store pending status value if options aren't loaded yet
  String _pendingStatusOutValue = '';

  List<LookupItem> _statusOptions = const [];
  List<LookupItem> _sizeTypeOptions = const [];
  List<LookupItem> _classOptions = const [];

  int? _selectedStatusIn;
  int? _selectedSizeTypeIn;
  int? _selectedClassIn; // No default - must be selected explicitly

  int? _selectedStatusOut;
  int? _selectedSizeTypeOut;
  int? _selectedClassOut;
  int? _selectedLoadTypeOut;

  String _clientNameIn = '';
  String _clientNameOut = '';
  int? _clientIdOut;
  int? _clientIdIn;

  // Checker information
  int? _checkerIdIn;
  String _checkerNameIn = '';
  int? _checkerIdOut;
  String _checkerNameOut = '';

  // Gate OUT - Plate number and Hauler
  String _plateNoOut = '';
  String _haulerOut = '';
  // Stable cache key for the specific Pre-Out record.
  String _outCacheKey = '';
  String _buildOutCacheKey({String? plate, String? hauler, String? dateAdded}) {
    final p = (plate ?? widget.record.plateNo).trim().toUpperCase();
    final h = (hauler ?? widget.record.hauler).trim().toUpperCase();
    final d = (dateAdded ?? widget.record.dateAdded).trim().toUpperCase();
    if (p.isEmpty && h.isEmpty && d.isEmpty) return '';
    return '$p|$h|$d';
  }

  // Gate OUT - Additional details from inventory
  String _approvalNotesOut = '';
  String _gateInRemarksOut = '';

  bool get _isOut => widget.record.gateStatus.toUpperCase() == 'OUT';

  String _buildImageCacheKey(String containerNo) {
    final cno = containerNo.trim();
    if (_isOut) {
      final recordKey = _buildOutCacheKey();
      return recordKey.isEmpty ? '' : 'OUT|$recordKey';
    }
    if (cno.isEmpty) return '';
    final completionDate = _imageDateForRecord() ?? 'NO_DATE';
    return 'IN|$completionDate|${cno.toUpperCase()}';
  }

  void _setImageProviderContextForContainer(String containerNo) {
    final key = _buildImageCacheKey(containerNo);
    if (key.isEmpty) return;
    _imageProvider.setCurrentContainer(key);
  }

  void _handleSubmitFieldChanged() {
    if (mounted) setState(() {});
  }

  bool get _hasSubmitImages {
    final containerNo = (_isOut ? _containerNoOut : _containerNoIn).text.trim();
    if (containerNo.isEmpty) return false;

    final hasTakenImages = _imageProvider.images.any((file) => file.existsSync());
    return hasTakenImages || _imageProvider.uploadedImages.isNotEmpty;
  }

  bool get _canSubmit {
    if (_submitting || _uploadingImages || !_hasSubmitImages) return false;

    if (_isOut) {
      return _containerNoOut.text.trim().isNotEmpty &&
          _remarksOut.text.trim().isNotEmpty;
    }

    return _selectedSizeTypeIn != null &&
        _isoCodeIn.text.trim().isNotEmpty &&
        _isValidManufacturedDate(_dateManufactured.text.trim()) &&
        _selectedClassIn != null &&
        _selectedStatusIn != null &&
        _remarksIn.text.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _imageDateCompleted = widget.record.dateCompleted.trim();
    if (_isOut) {
      // Initialize Gate OUT fields from PreRecord
      // Only pre-fill container number when it's a valid, non-placeholder value.
      final containerNoFromRecord = widget.record.containerNo.toString().trim();
      if (containerNoFromRecord.isNotEmpty && containerNoFromRecord != '-' && containerNoFromRecord.toLowerCase() != 'record not found') {
        _containerNoOut.text = containerNoFromRecord;
      }
      _plateNoOut = widget.record.plateNo;
      _haulerOut = widget.record.hauler;
      _outCacheKey = _buildOutCacheKey(
        plate: widget.record.plateNo,
        hauler: widget.record.hauler,
        dateAdded: widget.record.dateAdded,
      );
      // Get current user as checker
      final user = context.read<AuthProvider>().user;
      if (user != null) {
        _checkerIdOut = user.id;
        _checkerNameOut = user.username;
      }
    } else {
      // Initialize Gate IN fields from PreRecord
      _clientNameIn = widget.record.clientName;
      _containerNoIn.text = widget.record.containerNo;
      _clientIdIn = widget.record.clientId;
    }
    // If container was provided from previous screen (pre-in / pre-out), set provider
    final initialCno = _isOut ? _containerNoOut.text.trim() : _containerNoIn.text.trim();
    if (initialCno.isNotEmpty) {
      _setImageProviderContextForContainer(initialCno);
      // set form cache current key for IN (container no)
      if (!_isOut) {
        _formCache.setCurrent(initialCno, gate: 'IN');
        _applyCachedForm(initialCno, gate: 'IN');
      } else {
        // For OUT, use the specific record identity: plate, hauler, date added.
        final combined = _buildOutCacheKey();
        if (combined.isNotEmpty && _formCache.getCached(combined, gate: 'OUT') != null) {
          _formCache.setCurrent(combined, gate: 'OUT');
          _applyCachedForm(combined, gate: 'OUT');
        }
      }
      // Fetch server images for this date, gate direction, and container immediately.
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshUploadedImages());

      // Listen for upload progress/completion events so UI stays disabled until finished
      _uploadSubscription = _imageUploadService.uploadStream.listen((status) {
        final containerNo = _isOut ? _containerNoOut.text.trim() : _containerNoIn.text.trim();
        if (status.containerNo == containerNo) {
          if (mounted) {
            setState(() {
              _uploadProgress = status.progress;
              if (!status.completed) {
                _showUploadProgress = true;
                _uploadingImages = true;
              }
            });
          }
        }
      });
    }
    _loadLookups();
    if (!_isOut) {
      _loadContainerDetails();
    }
    // Mark as user-edited when the user changes key fields (disables fetched-based camera)
    _containerNoIn.addListener(() {
      if (mounted) {
        _userEdited = true;
        _allowCamera = false;
        _updateCameraEnabled();
        final cno = _containerNoIn.text.trim();
        if (cno.isNotEmpty) {
          _setImageProviderContextForContainer(cno);
          // Debounce refresh of uploaded images when user types/selects container
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 600), () {
            _refreshUploadedImages();
            // Save cache for current container before switching to new one
            _saveCache();
            // Set cache key and load/apply cached values for new container
            _formCache.setCurrent(cno, gate: 'IN');
            _applyCachedForm(cno, gate: 'IN');
          });
        }
      }
    });
    _containerNoOut.addListener(() {
      if (mounted) {
        _selectedContainerId = null;
        _userEdited = true;
        _allowCamera = false;
        _updateCameraEnabled();
        final cno = _containerNoOut.text.trim();
        if (cno.isNotEmpty) {
          // Debounce refresh only. Do not apply/save OUT cache while typing,
          // otherwise partial search text can overwrite cached container_no.
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 600), () {
            _refreshUploadedImages();
          });
        }
      }
    });
    _isoCodeIn.addListener(() {
      if (mounted && !_applyingCache && !_hydratingGateInFromApi) {
        _userEdited = true;
        _allowCamera = false;
        _updateCameraEnabled();
        // Refresh uploaded images for this fetched container
        WidgetsBinding.instance.addPostFrameCallback((_) => _refreshUploadedImages());
        _saveCache();
      }
    });
    // listen for Gate IN field changes to persist cache on every character
    _isoCodeIn.addListener(() {
      if (mounted && !_applyingCache && !_hydratingGateInFromApi) _saveCache();
    });
    _remarksIn.addListener(() {
      _handleSubmitFieldChanged();
      if (mounted && !_applyingCache && !_hydratingGateInFromApi) _saveCache();
    });
    _dateManufactured.addListener(() {
      _handleSubmitFieldChanged();
      if (mounted && !_applyingCache && !_hydratingGateInFromApi) _saveCache();
    });
    // listen for Gate OUT field changes to persist cache
    _remarksOut.addListener(() {
      _handleSubmitFieldChanged();
      if (mounted && !_applyingCache) _saveCache();
    });
    _isoCodeOut.addListener(() {
      if (mounted && !_applyingCache) _saveCache();
    });
    _imageProvider.addListener(_handleSubmitFieldChanged);
    // Initialize camera enabled state (will be updated after loads)
    _updateCameraEnabled();
    // Refresh uploaded images and load persisted form cache when opening the screen
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshUploadedImages();
      await _formCache.loadAll();

      // After cache is loaded, apply cached values for current key if present
      try {
        if (!_isOut) {
          final key = _containerNoIn.text.trim();
          if (key.isNotEmpty) {
            final hasInCache = _formCache.getCached(key, gate: 'IN') != null;
            _formCache.setCurrent(key, gate: 'IN');
            _applyCachedForm(key, gate: 'IN');
            // If cache is missing, fall back to DB values.
            if (!hasInCache) {
              await _loadContainerDetails();
            }
          }
        } else {
          final combined = _buildOutCacheKey();
          if (combined.isNotEmpty && _formCache.getCached(combined, gate: 'OUT') != null) {
            _formCache.setCurrent(combined, gate: 'OUT');
            _applyCachedForm(combined, gate: 'OUT');
          }
        }
      } catch (_) {}
    });
  }

  void _clearGateInFields() {
    _dateManufactured.text = '';
    _isoCodeIn.text = '';
    _remarksIn.text = '';
  }

  /// Try to match a container status value (numeric id or text label) to _statusOptions.
  /// If options aren't loaded yet, store it as pending for later matching.
  void _tryApplyContainerStatus(String rawStatus) {
    if (rawStatus.isEmpty) return;

    if (_statusOptions.isEmpty) {
      // Options not loaded yet - store for later
      _pendingStatusOutValue = rawStatus;
      return;
    }

    // Try numeric ID first
    int? containerStatusId = int.tryParse(rawStatus);
    if (containerStatusId != null &&
        containerStatusId > 0 &&
        _statusOptions.any((opt) => opt.id == containerStatusId)) {
      _selectedStatusOut = containerStatusId;
      _pendingStatusOutValue = ''; // Clear pending
      return;
    }

    // Try matching by label (case-insensitive)
    final match = _statusOptions.firstWhere(
        (opt) => opt.label.toLowerCase() == rawStatus.toLowerCase(),
        orElse: () => LookupItem(id: 0, label: ''));
    if (match.id > 0) {
      _selectedStatusOut = match.id;
      _pendingStatusOutValue = ''; // Clear pending
      return;
    }

    // Couldn't match - store for retry if options change
    _pendingStatusOutValue = rawStatus;
  }

  void _applyCachedForm(String key, {required String gate}) {
    try {
      try { print('ProcessScreen: applying cache for key=$key gate=$gate'); } catch (_) {}
      _applyingCache = true; // Prevent cache save during apply
      final cache = _formCache.getCached(key, gate: gate);

      if (gate.toUpperCase() == 'IN') {
        // If no cache for this container, clear the form fields
        if (cache == null) {
          // Keep current values (usually fetched from DB) when cache is missing.
          // This prevents blank ISO/remarks after cache is cleared post-submit.
          try { print('ProcessScreen: no cache found for IN $key - keeping current field values'); } catch (_) {}
          _applyingCache = false;
          return;
        }
        try { print('ProcessScreen: found cache for IN $key keys=${cache.keys.toList()}'); } catch (_) {}
        // Apply cached values
        if (cache.containsKey('date_manufactured')) {
          _dateManufactured.text = cache['date_manufactured'] ?? '';
        } else {
          _dateManufactured.text = '';
        }
        _isoCodeIn.text = cache.containsKey('iso_code') ? (cache['iso_code'] ?? '') : '';
        _remarksIn.text = cache.containsKey('remarks') ? (cache['remarks'] ?? '') : '';
        if (cache.containsKey('size_type')) _selectedSizeTypeIn = cache['size_type'] as int?;
        if (cache.containsKey('class')) _selectedClassIn = cache['class'] as int?;
        if (cache.containsKey('status')) _selectedStatusIn = cache['status'] as int?;
        if (cache.containsKey('checker_name')) _checkerNameIn = cache['checker_name'] ?? '';
      } else {
        if (cache != null) {
          try { print('ProcessScreen: OUT cache keys=${cache.keys.toList()}'); } catch (_) {}
          try { print('ProcessScreen: OUT cache iso="${cache['iso_code']}" remarks="${cache['remarks']}" class=${cache['class']} status=${cache['status']}'); } catch (_) {}
          if (cache.containsKey('container_no')) _containerNoOut.text = cache['container_no'] ?? '';
          if (cache.containsKey('iso_code')) _isoCodeOut.text = cache['iso_code'] ?? '';
          if (cache.containsKey('remarks')) _remarksOut.text = cache['remarks'] ?? '';
          if (cache.containsKey('size_type')) {
            _selectedSizeTypeOut = cache['size_type'] as int?;
            try { print('ProcessScreen: Applied cached size_type: ${cache['size_type']} (type: ${cache['size_type'].runtimeType})'); } catch (_) {}
          }
          if (cache.containsKey('class') && cache['class'] != null) {
            final classVal = cache['class'];
            _selectedClassOut = classVal as int?;
            try { print('ProcessScreen: Applied cached class: $classVal (type: ${classVal.runtimeType}) -> _selectedClassOut=$_selectedClassOut'); } catch (_) {}
          }
          if (cache.containsKey('status') && cache['status'] != null) {
            final statusVal = cache['status'];
            _selectedStatusOut = statusVal as int?;
            try { print('ProcessScreen: Applied cached status: $statusVal (type: ${statusVal.runtimeType}) (statusOptions.length=${_statusOptions.length}) -> _selectedStatusOut=$_selectedStatusOut'); } catch (_) {}
          }
          if (cache.containsKey('client_id')) _clientIdOut = cache['client_id'] as int?;
          if (cache.containsKey('client_name')) _clientNameOut = cache['client_name'] ?? '';
          if (cache.containsKey('plate_no')) _plateNoOut = cache['plate_no'] ?? _plateNoOut;
          if (cache.containsKey('hauler')) _haulerOut = cache['hauler'] ?? _haulerOut;
        } else {
          try { print('ProcessScreen: No cache found for OUT gate key=$key'); } catch (_) {}
        }
      }
      if (mounted) setState(() {});
      // Ensure image provider uses the applied container key and refresh uploaded images
      try {
        if (gate.toUpperCase() == 'IN') {
          final cno = _containerNoIn.text.trim();
          if (cno.isNotEmpty) {
            _setImageProviderContextForContainer(cno);
            WidgetsBinding.instance.addPostFrameCallback((_) => _refreshUploadedImages());
          }
        } else {
          final cno = _containerNoOut.text.trim();
          if (cno.isNotEmpty) {
            _setImageProviderContextForContainer(cno);
            WidgetsBinding.instance.addPostFrameCallback((_) => _refreshUploadedImages());
          }
        }
      } catch (_) {}
      _applyingCache = false;
    } catch (e) {
      try { print('ProcessScreen: Error applying cache: $e'); } catch (_) {}
    }
  }

  void _saveCache() {
    try {
        final key = !_isOut
          ? _containerNoIn.text.trim()
          : _buildOutCacheKey();
      if (key.isEmpty) return;
      final Map<String, dynamic> data = {};
      if (!_isOut) {
        final existing = _formCache.getCached(key, gate: 'IN');
        final currentDateManufactured = _dateManufactured.text.trim();
        final cachedDateManufactured =
          (existing?['date_manufactured'] ?? '').toString().trim();
        final currentIsoCode = _isoCodeIn.text.trim();
        final cachedIsoCode = (existing?['iso_code'] ?? '').toString().trim();
        final currentRemarks = _remarksIn.text.trim();
        final cachedRemarks = (existing?['remarks'] ?? '').toString().trim();

        // Avoid wiping non-empty cached values during API/bootstrap timing.
        data['date_manufactured'] = currentDateManufactured.isNotEmpty
          ? currentDateManufactured
          : cachedDateManufactured;
        data['iso_code'] =
          currentIsoCode.isNotEmpty ? currentIsoCode : cachedIsoCode;
        data['remarks'] =
          currentRemarks.isNotEmpty ? currentRemarks : cachedRemarks;
        data['size_type'] = _selectedSizeTypeIn;
        data['class'] = _selectedClassIn;
        data['status'] = _selectedStatusIn;
        data['checker_name'] = _checkerNameIn;
      } else {
        final existing = _formCache.getCached(key, gate: 'OUT');
        data['iso_code'] = _isoCodeOut.text.trim();
        data['container_no'] = _containerNoOut.text.trim();
        final currentRemarks = _remarksOut.text.trim();
        final cachedRemarks = (existing?['remarks'] ?? '').toString().trim();
        // Do not overwrite a non-empty cached remarks value with an empty value
        // that can come from API/bootstrap timing.
        data['remarks'] = currentRemarks.isNotEmpty ? currentRemarks : cachedRemarks;
        data['size_type'] = _selectedSizeTypeOut;
        data['class'] = _selectedClassOut ?? existing?['class'];
        data['status'] = _selectedStatusOut ?? existing?['status'];
        data['client_id'] = _clientIdOut;
        data['client_name'] = _clientNameOut;
        data['plate_no'] = _plateNoOut;
        data['hauler'] = _haulerOut;
      }
      // For OUT, always save against the specific record identity.
      if (_isOut) {
        final combined = _buildOutCacheKey();
        if (combined.isNotEmpty) _formCache.setCurrent(combined, gate: 'OUT');
      } else {
        _formCache.setCurrent(key, gate: 'IN');
      }
      try { print('ProcessScreen: saving cache for key=$key gate=${_isOut ? 'OUT' : 'IN'} data_keys=${data.keys.toList()} iso="${data['iso_code']}" remarks="${data['remarks']}"'); } catch (_) {}
      _formCache.saveForCurrent(data);
    } catch (_) {}
  }

  Future<void> _refreshUploadedImages() async {
    // Initialization, lookup loading, and container selection can all request
    // a refresh at nearly the same time. Queue a follow-up instead of dropping
    // the request while the first server fetch is still running.
    if (_refreshingUploadedImages) {
      _refreshUploadedImagesQueued = true;
      return;
    }

    _refreshingUploadedImages = true;
    try {
      final containerNo = _isOut ? _containerNoOut.text.trim() : _containerNoIn.text.trim();
      if (containerNo.isEmpty) {
        // No container — clear uploaded images so old images from previous plate don't persist
        _setImageProviderContextForContainer('');
        _imageProvider.clearUploaded();
        if (mounted) setState(() {});
        _refreshingUploadedImages = false;
        return;
      }

      final dateStr = _imageDateForRecord();
      if (dateStr == null) {
        // Pending records have no completed date, so they must not fetch from
        // any date folder and must not display unrelated images.
        _imageProvider.clearUploaded();
        if (mounted) setState(() {});
        _refreshingUploadedImages = false;
        return;
      }

      final uploadPath = "container_pics/$dateStr/${_isOut ? 'out' : 'in'}/";

      try {
        // Ensure provider is set for this container key, then clear any cached uploaded entries
        _setImageProviderContextForContainer(containerNo);
        _imageProvider.clearUploaded();

        // Fetch server images for the specific date/path only. Do NOT show local cached images.
        final files = await _imageUploadService.fetchExistingImages(
          containerNo: containerNo,
          gateStatus: _isOut ? 'out' : 'in',
          date: dateStr,
          uploadPath: uploadPath + containerNo,
        );

        if (mounted) {
          // Clear any existing uploaded images in provider for current context
          _imageProvider.clearUploaded();
          if (files.isNotEmpty) {
            _imageProvider.addUploadedImages(files);
          }
          setState(() {});
        }
      } finally {
        _refreshingUploadedImages = false;
        if (_refreshUploadedImagesQueued && mounted) {
          _refreshUploadedImagesQueued = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _refreshUploadedImages();
          });
        }
      }
    } catch (_) {
      // Keep future refreshes working if the date/path lookup itself fails.
      _refreshingUploadedImages = false;
    }
  }

  String? _imageDateForRecord() {
    // Only completed records have a valid server image date. Pending records
    // have no date_completed and must not fetch images from any date folder.
    final raw = _imageDateCompleted.trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;

    DateTime? date = DateTime.tryParse(raw);

    // Also support dates returned as MM-DD-YYYY or MM/DD/YYYY.
    if (date == null) {
      final match = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})')
          .firstMatch(raw);
      if (match != null) {
        date = DateTime.tryParse(
          '${match.group(3)}-${match.group(1)!.padLeft(2, '0')}-${match.group(2)!.padLeft(2, '0')}',
        );
      }
    }

    if (date == null) return null;
    return '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}-${date.year}';
  }

  void _updateCameraEnabled() {
    if (!mounted) return;

    // For Gate OUT: enable camera only after user selected a container from search
    if (_isOut) {
      // Enable camera when either a container was selected from the dropdown
      // or the Container No. field contains any value (including cached values).
      final enabled = _selectedContainerId != null || _containerNoOut.text.trim().isNotEmpty;
      setState(() => _cameraEnabled = enabled);
      return;
    }

    // For Gate IN: keep previous behavior (camera enabled)
    setState(() => _cameraEnabled = true);
  }

  Future<void> _loadLookups() async {
    final user = context.read<AuthProvider>().user;
    if (user == null || user.username.isEmpty) {
      return;
    }

    setState(() => _loading = true);

    try {
      final statusOpts = await _gateService.getStatusOptions(user.username);
      final sizeTypeOpts = await _gateService.getSizeTypeOptions(user.username);
      final classOpts = await _gateService.getClassOptions(user.username);

      setState(() {
        _statusOptions = statusOpts;
        _sizeTypeOptions = sizeTypeOpts;
        _classOptions = classOpts;

        // Do NOT set any defaults - leave all as null (no selection)
        // Values will only be set if API returns non-empty data
        
        // If we have a pending status from a fetch that happened before options loaded,
        // try to apply it now that options are available
        if (_pendingStatusOutValue.isNotEmpty) {
          _tryApplyContainerStatus(_pendingStatusOutValue);
        }

        // Also re-validate cached status/class values that may have been applied before
        // options were loaded. This ensures they display correctly in dropdowns.
        if (_isOut && _selectedStatusOut != null && _selectedStatusOut! > 0) {
          // Verify cached status exists in options, if not clear it
          if (!_statusOptions.any((opt) => opt.id == _selectedStatusOut)) {
            try { print('ProcessScreen: Cached status $_selectedStatusOut not found in loaded options, clearing'); } catch (_) {}
            _selectedStatusOut = null;
          } else {
            try { print('ProcessScreen: Cached status $_selectedStatusOut validated against loaded options'); } catch (_) {}
          }
        }
      });

      // NOW that options are loaded, reload container details so they can be properly validated and set
      if (!_isOut && _containerNoIn.text.isNotEmpty) {
        await _loadContainerDetails();
      } else if (_isOut && _containerNoOut.text.isNotEmpty) {
        // For Gate OUT, fetch all container details after lookups are loaded
        await _loadGateOutContainerDetails();
      }

      // After loading options, ensure UI reflects any cached values that were applied before options loaded
      if (mounted) {
        setState(() {
          try { print('ProcessScreen: Final rebuild after options loaded - statusOptions.length=${_statusOptions.length}, _selectedStatusOut=$_selectedStatusOut, _selectedClassOut=$_selectedClassOut'); } catch (_) {}
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Error loading options: ${ErrorHandler.getUserFriendlyMessage(e)}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadContainerDetails() async {
    final user = context.read<AuthProvider>().user;
    if (user == null || user.username.isEmpty || _containerNoIn.text.isEmpty) {
      return;
    }

    try {
      final details = await _gateService.getContainerDetails(
        username: user.username,
        containerNo: _containerNoIn.text,
      );

      if (mounted) {
        _hydratingGateInFromApi = true;
        setState(() {
          final completedDate = details['date_completed']?.toString().trim() ?? '';
          if (completedDate.isNotEmpty && completedDate.toLowerCase() != 'null') {
            _imageDateCompleted = completedDate;
          }
          _clientNameIn = details['client_name']?.toString() ?? '';

          // Set ISO code - ensure it's not null and trim whitespace
          final isoCode = details['iso_code']?.toString().trim() ?? '';
          _isoCodeIn.text = isoCode;
          _isoFetched = isoCode.isNotEmpty && isoCode != '-' && isoCode.toLowerCase() != 'record not found';

          // Set date manufactured (format: MM/YYYY from database date)
          final dateMnfg = details['date_mnfg']?.toString().trim();
          if (dateMnfg != null &&
              dateMnfg.isNotEmpty &&
              dateMnfg != '0000-00-00') {
            try {
              final date = DateTime.parse(dateMnfg);
              _dateManufactured.text =
                  '${date.month.toString().padLeft(2, '0')}/${date.year}';
            } catch (_) {
              _dateManufactured.text = '';
            }
          }

          // Set remarks from pre_inventory
          final remarks = details['remarks']?.toString().trim() ?? '';
          _remarksIn.text = remarks;

          // Set checker information from pre_inventory
          final checkerId =
              int.tryParse(details['checker_id']?.toString() ?? '0');
          _checkerIdIn =
              (checkerId != null && checkerId > 0) ? checkerId : null;
          _checkerNameIn = details['checker_name']?.toString().trim() ?? '';

          // Set size type ONLY if API returns valid non-zero ID and it exists in options
          final sizeTypeId =
              int.tryParse(details['sizetype_id']?.toString() ?? '0');
          if (sizeTypeId != null &&
              sizeTypeId > 0 &&
              _sizeTypeOptions.any((opt) => opt.id == sizeTypeId)) {
            _selectedSizeTypeIn = sizeTypeId;
          }
          // If API doesn't return valid data, leave _selectedSizeTypeIn as null (no selection)

          // Set class ONLY if API returns valid non-empty value
          final classStr = details['class']?.toString().trim() ?? '';
          if (classStr.isNotEmpty) {
            if (classStr == 'A') {
              _selectedClassIn = 1;
            } else if (classStr == 'B') {
              _selectedClassIn = 2;
            } else if (classStr == 'C') {
              _selectedClassIn = 3;
            }
          }
          // If API doesn't return valid class, leave _selectedClassIn as null (no selection)

          // Set container status ONLY if API returns valid non-zero ID and it exists in options
          final cntStatusId =
              int.tryParse(details['cnt_status']?.toString() ?? '0');
          if (cntStatusId != null &&
              cntStatusId > 0 &&
              _statusOptions.any((opt) => opt.id == cntStatusId)) {
            _selectedStatusIn = cntStatusId;
          }
          // If API doesn't return valid status, leave _selectedStatusIn as null (no selection)
        });
        // Mark that these values came from a fetch/load, not from user typing
        _userEdited = false;
        _updateCameraEnabled();
        // Load cached uploaded images (or fetch if none) via centralized refresh
        try {
          _setImageProviderContextForContainer(_containerNoIn.text.trim());
          await _refreshUploadedImages();
          // Apply any cached form values for this container
          _formCache.setCurrent(_containerNoIn.text.trim(), gate: 'IN');
          _applyCachedForm(_containerNoIn.text.trim(), gate: 'IN');
        } catch (_) {}
        _hydratingGateInFromApi = false;
      }
    } catch (e) {
      _hydratingGateInFromApi = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Error loading container details: ${ErrorHandler.getUserFriendlyMessage(e)}')),
        );
      }
    } finally {
      _hydratingGateInFromApi = false;
    }
  }

  Future<void> _loadGateOutContainerDetails() async {
    final user = context.read<AuthProvider>().user;
    if (user == null || user.username.isEmpty || _containerNoOut.text.isEmpty) {
      return;
    }

    try {
      final details = await _gateService.getContainerDetails(
        username: user.username,
        containerNo: _containerNoOut.text,
        gateStatus: 'OUT',
      );

      if (mounted) {
        setState(() {
          final completedDate = details['date_completed']?.toString().trim() ?? '';
          if (completedDate.isNotEmpty && completedDate.toLowerCase() != 'null') {
            _imageDateCompleted = completedDate;
          }
          // Set client name
          _clientNameOut = details['client_name']?.toString() ?? '';
          _clientIdOut = int.tryParse(details['client_id']?.toString() ?? '0');

          // Set ISO code
          final isoCode = details['iso_code']?.toString().trim() ?? '';
          _isoCodeOut.text = isoCode;
          _containerFetched = _hasValidContainerDetails(details);

          // Set size type ONLY if valid
          final sizeTypeId =
              int.tryParse(details['sizetype_id']?.toString() ?? '0');
          if (sizeTypeId != null &&
              sizeTypeId > 0 &&
              _sizeTypeOptions.any((opt) => opt.id == sizeTypeId)) {
            _selectedSizeTypeOut = sizeTypeId;
          }

          // Set class
          final classStr = details['class']?.toString().trim() ?? '';
          if (classStr.isNotEmpty) {
            if (classStr == 'A') {
              _selectedClassOut = 1;
            } else if (classStr == 'B') {
              _selectedClassOut = 2;
            } else if (classStr == 'C') {
              _selectedClassOut = 3;
            }
          }

          // Set container status from inventory. API may return either an
          // integer id (foreign key) or the status string. Handle both.
          // May need to retry after options load if they weren't available yet.
          final rawStatus = details['container_status']?.toString() ?? '';
          _tryApplyContainerStatus(rawStatus);

          // Set approval notes from inventory
          _approvalNotesOut =
              details['approval_notes']?.toString().trim() ?? '';

          // Set gate in remarks from inventory remarks field
          _gateInRemarksOut = details['remarks']?.toString().trim() ?? '';

          // Set remarks from pre_inventory only when API has a value.
          // Keep cached/user-entered remarks if API remarks is empty.
          final preRemarks =
              details['pre_inventory_remarks']?.toString().trim() ?? '';
          if (preRemarks.isNotEmpty) {
            _remarksOut.text = preRemarks;
          }
        });
        // Mark that these values came from a fetch/load, not from user typing
        _userEdited = false;
        _updateCameraEnabled();
        // Load cached uploaded images (or fetch if none) via centralized refresh
        try {
          _setImageProviderContextForContainer(_containerNoOut.text.trim());
          await _refreshUploadedImages();
          // Apply cached form values for this specific Pre-Out record.
          final combined = _buildOutCacheKey();
          if (combined.isNotEmpty && _formCache.getCached(combined, gate: 'OUT') != null) {
            _formCache.setCurrent(combined, gate: 'OUT');
            _applyCachedForm(combined, gate: 'OUT');
          }
        } catch (_) {}
      }
    } catch (e) {
      print('DEBUG: Error loading Gate OUT container details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Error loading container details: ${ErrorHandler.getUserFriendlyMessage(e)}')),
        );
      }
    }
  }

  Future<void> _searchContainers(String query) async {
    if (query.isEmpty || query.length < 3) {
      _hideContainerDropdown();
      return;
    }

    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    try {
      print('DEBUG: Searching containers with query: $query');
      final results = await _gateService.searchAvailableContainers(
        username: user.username,
        searchTerm: query,
      );

      print('DEBUG: API returned ${results.length} results');

      if (mounted) {
        setState(() {
          _containerSearchResults = results.map((item) {
            print('DEBUG: Full item data: $item');
            print(
                'DEBUG: plate_no = ${item['plate_no']}, hauler = ${item['hauler']}');
            return ContainerSearchResult(
              id: (item['i_id'] as num?)?.toInt() ?? 0,
              containerNo: item['container_no'].toString(),
              clientName: item['client_name'].toString(),
              clientId: (item['client_id'] as num?)?.toInt() ?? 0,
              sizeType: item['size_type'].toString(),
              sizeTypeId: (item['sizetype_id'] as num?)?.toInt() ?? 0,
              isoCode: item['iso_code'].toString(),
              className: item['class']?.toString() ??
                  item['className']?.toString() ??
                  'A',
              gateInRemarks: item['location'].toString(),
              plateNo: item['plate_no']?.toString() ?? '',
              hauler: item['hauler']?.toString() ?? '',
            );
          }).toList();
        });

      }
    } catch (e) {
      print('DEBUG: Search error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Error searching containers: ${ErrorHandler.getUserFriendlyMessage(e)}')),
        );
      }
    }
  }

  String _formatDateForDisplay(String input) {
    // Remove all non-numeric characters
    String cleaned = input.replaceAll(RegExp(r'\D'), '');

    // If cleaned is empty, return empty
    if (cleaned.isEmpty) return '';

    // If length > 6, keep only first 6 digits
    if (cleaned.length > 6) cleaned = cleaned.substring(0, 6);

    // Format as mm/yyyy
    if (cleaned.length <= 2) {
      return cleaned;
    } else if (cleaned.length <= 6) {
      return '${cleaned.substring(0, 2)}/${cleaned.substring(2)}';
    }
    return cleaned;
  }

  void _handleDateManufacturedChange(String value) {
    String cleaned = value.replaceAll(RegExp(r'\D'), '');

    // Accept only month prefixes that can become 01-12.
    String accepted = '';
    if (cleaned.isNotEmpty && (cleaned[0] == '0' || cleaned[0] == '1')) {
      accepted = cleaned[0];
    }
    if (cleaned.length >= 2 && accepted.length == 1) {
      final month = int.tryParse(cleaned.substring(0, 2));
      if (month != null && month >= 1 && month <= 12) {
        accepted = cleaned.substring(0, 2);
      }
    }

    // After the month, accept only year prefixes that can become a year from
    // 1900 through the current year. This prevents invalid digits while still
    // allowing the user to enter a partial year.
    if (accepted.length == 2 && cleaned.length > 2) {
      final yearEnd = cleaned.length > 6 ? 6 : cleaned.length;
      final yearDigits = cleaned.substring(2, yearEnd);
      for (var length = 1; length <= yearDigits.length; length++) {
        final prefix = yearDigits.substring(0, length);
        final canBecomeValidYear = List.generate(
          DateTime.now().year - 1900 + 1,
          (index) => (1900 + index).toString(),
        ).any((year) => year.startsWith(prefix));
        if (!canBecomeValidYear) break;
        accepted += prefix.substring(prefix.length - 1);
      }
    }

    final formatted = accepted.length <= 2
        ? accepted
        : '${accepted.substring(0, 2)}/${accepted.substring(2)}';

    // Only update if different from current
    if (_dateManufactured.text != formatted) {
      _dateManufactured.text = formatted;
      // Keep cursor at the end
      _dateManufactured.selection = TextSelection.fromPosition(
        TextPosition(offset: formatted.length),
      );
      _saveCache();
    }
  }

  /// Convert MM/YYYY format to YYYY-MM-01 format (first day of month)
  /// Input: "02/2025" → Output: "2025-02-01"
  bool _isValidManufacturedDate(String value) {
    final match = RegExp(r'^(0[1-9]|1[0-2])/(\d{4})$').firstMatch(value);
    if (match == null) return false;

    final year = int.parse(match.group(2)!);
    final currentYear = DateTime.now().year;
    return year >= 1900 && year <= currentYear;
  }

  String _convertDateManufacturedToDb(String mmYyyyFormat) {
    final parts = mmYyyyFormat.split('/');
    if (parts.length != 2) return '';

    final month = parts[0].padLeft(2, '0');
    final year = parts[1];

    return '$year-$month-01';
  }

  bool _hasValidContainerDetails(Map details) {
    if (details.isEmpty) return false;
    
    // Check for error indicators
    final error = details['error']?.toString().toLowerCase() ?? '';
    if (error.contains('not found') || error.contains('no record')) return false;
    
    final iso = details['iso_code']?.toString().trim() ?? '';
    if (iso.toLowerCase().contains('not found') || iso == '-') return false;
    
    final clientId = int.tryParse(details['client_id']?.toString() ?? '0') ?? 0;
    final containerStatus =
        int.tryParse(details['container_status']?.toString() ?? '0') ?? 0;
    
    // Only valid if we have at least client data or status data (not just empty ISO code)
    if (clientId > 0 || containerStatus > 0) return true;
    if (iso.isNotEmpty) return true;
    return false;
  }

  bool _handleGalleryScrollNotification(ScrollNotification notification) {
    if (notification is OverscrollNotification &&
        _formScrollController.hasClients) {
      final parentPosition = _formScrollController.position;
      final nextOffset = (parentPosition.pixels + notification.overscroll)
          .clamp(parentPosition.minScrollExtent, parentPosition.maxScrollExtent)
          .toDouble();

      if (nextOffset != parentPosition.pixels) {
        _formScrollController.jumpTo(nextOffset);
      }
    }

    // Reposition dropdown on any scroll to keep it attached below container search
    if (_dropdownOverlay != null && _containerSearchResults.isNotEmpty) {
      _dropdownOverlay!.markNeedsBuild();
    }

    return false;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _dropdownOverlay?.remove();
    _uploadSubscription?.cancel();
    _imageProvider.removeListener(_handleSubmitFieldChanged);
    _formScrollController.dispose();
    _galleryScrollController.dispose();
    _containerNoIn.dispose();
    _dateManufactured.dispose();
    _isoCodeIn.dispose();
    _remarksIn.dispose();
    _containerNoOut.dispose();
    _isoCodeOut.dispose();
    _gateInRemarks.dispose();
    _remarksOut.dispose();
    super.dispose();
  }

  void _hideContainerDropdown() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;
    if (mounted) {
      setState(() {
        _showContainerDropdown = false;
        _containerSearchResults = [];
      });
    }
  }

  void _showContainerDropdownOverlay() {
    _hideContainerDropdown();

    if (_containerSearchResults.isEmpty) return;

    final RenderBox? renderBox =
      _containerSearchKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    _dropdownOverlay = OverlayEntry(
      builder: (context) {
        // Recalculate position on every build to follow scroll
        final RenderBox? currentRenderBox =
            _containerSearchKey.currentContext?.findRenderObject() as RenderBox?;
        if (currentRenderBox == null) {
          return const SizedBox.shrink();
        }

        final size = currentRenderBox.size;
        final offset = currentRenderBox.localToGlobal(Offset.zero);

        return Positioned(
          left: offset.dx,
          top: offset.dy + size.height + 4,
          width: size.width,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 250),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _containerSearchResults.length,
                itemBuilder: (context, index) {
                  final container = _containerSearchResults[index];
                  return ListTile(
                    dense: true,
                    title: Text(container.containerNo,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () {
                      _selectContainer(container);
                      _hideContainerDropdown();
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_dropdownOverlay!);
  }

  void _handleContainerSearchChange(String value) {
    _setUppercaseValue(_containerNoOut, value);
    value = value.toUpperCase();

    // Debounce the search - only trigger after 3+ characters
    _searchDebounce?.cancel();
    _selectedContainerId = null;
    // Editing search should disable camera until a successful submit
    if (mounted) {
      _allowCamera = false;
      _updateCameraEnabled();
    }
    if (value.length >= 3) {
      _searchDebounce = Timer(const Duration(milliseconds: 500), () {
        _searchContainers(value.toUpperCase());
      });
    } else {
      _hideContainerDropdown();
    }
  }

  void _handleRemarksOutChange(String value) {
    _setUppercaseValue(_remarksOut, value);
  }

  void _handleIsoCodeInChange(String value) {
    _setUppercaseValue(_isoCodeIn, value);
    if (!_applyingCache) _saveCache();
  }

  void _handleRemarksInChange(String value) {
    _setUppercaseValue(_remarksIn, value);
    if (!_applyingCache) _saveCache();
  }

  void _setUppercaseValue(TextEditingController controller, String value) {
    final uppercase = value.toUpperCase();
    if (value == uppercase) return;

    final selection = controller.selection;
    controller.value = controller.value.copyWith(
      text: uppercase,
      selection: selection,
      composing: TextRange.empty,
    );
  }

  void _selectContainer(ContainerSearchResult container) {
    _hideContainerDropdown();

    // Keep the OUT cache key stable for this plate/hauler/date-added record.
    if (_outCacheKey.isEmpty) {
      _outCacheKey = _buildOutCacheKey();
    }

    setState(() {
      _containerNoOut.text = container.containerNo;
      _selectedContainerId = container.id;
      _clientNameOut = container.clientName;
      _clientIdOut = container.clientId;
      _selectedSizeTypeOut = container.sizeTypeId;
      _isoCodeOut.text = container.isoCode;
      _haulerOut = container.hauler;
      // When user selects from search, treat container as not yet fetched/saved
      _containerFetched = false;

      // Convert className (A, B, C) to class integer (1, 2, 3)
      if (container.className == 'A') {
        _selectedClassOut = 1;
      } else if (container.className == 'B') {
        _selectedClassOut = 2;
      } else if (container.className == 'C') {
        _selectedClassOut = 3;
      } else {
        _selectedClassOut = 1;
      }

      _gateInRemarks.text = container.gateInRemarks;
      // When user selects from search, treat container as not yet fetched/saved
      _containerFetched = false;
      _updateCameraEnabled();
    });

    _setImageProviderContextForContainer(container.containerNo);

    // Mark that the upcoming fetch was triggered by a user selection
    _lastFetchFromSelection = true;

      // Save selected container immediately to the combined OUT cache key.
      final combined = _buildOutCacheKey();
      if (combined.isNotEmpty) {
        _formCache.setCurrent(combined, gate: 'OUT');
        _saveCache();
      }

    // Fetch additional container details from inventory.
    // After fetch completes, _saveCache() will be called with full/fetched data
    _fetchContainerDetailsForGateOut(container.containerNo);
  }

  Future<void> _fetchContainerDetailsForGateOut(String containerNo) async {
    final user = context.read<AuthProvider>().user;
    if (user == null || user.username.isEmpty) {
      return;
    }

    try {
      final details = await _gateService.getContainerDetails(
        username: user.username,
        containerNo: containerNo,
        gateStatus: 'OUT',
      );

      if (mounted) {
        setState(() {
          // Set approval notes from inventory
          _approvalNotesOut =
              details['approval_notes']?.toString().trim() ?? '';

          // Set gate in remarks from inventory remarks field
          _gateInRemarksOut = details['remarks']?.toString().trim() ?? '';

          // Set remarks from pre_inventory only when API has a value.
          // Keep cached/user-entered remarks if API remarks is empty.
          final preRemarks =
              details['pre_inventory_remarks']?.toString().trim() ?? '';
          if (preRemarks.isNotEmpty) {
            _remarksOut.text = preRemarks;
          }

          // Set class from API response if provided
          final classStr = details['class']?.toString().trim() ?? '';
          if (classStr.isNotEmpty) {
            if (classStr == 'A') {
              _selectedClassOut = 1;
            } else if (classStr == 'B') {
              _selectedClassOut = 2;
            } else if (classStr == 'C') {
              _selectedClassOut = 3;
            }
          }
          try { print('DEBUG: Fetched class from API: classStr="$classStr" _selectedClassOut=$_selectedClassOut'); } catch (_) {}

          // Pre-fill container status from inventory. Accept numeric id or
          // textual status and map to the corresponding lookup option.
          // May need to retry after options load if they weren't available yet.
          final rawStatus = details['container_status']?.toString() ?? '';
          try { print('DEBUG: Fetched container_status from API: rawStatus="$rawStatus" container_status=${details['container_status']}'); } catch (_) {}
          _tryApplyContainerStatus(rawStatus);
          // Only consider container as "fetched" when API returned meaningful data
          _containerFetched = _hasValidContainerDetails(details);
        });
        // If this fetch was NOT triggered by a user selection, mark that
        // values came from a fetch/load so fetched-based camera enabling can apply.
        if (!_lastFetchFromSelection) {
          _userEdited = false;
        }
        _lastFetchFromSelection = false;
        _updateCameraEnabled();
        // Save the fetched status and other fields to cache
        _saveCache();
      }
    } catch (e) {
      print('DEBUG: Error fetching container details for Gate OUT: $e');
    }
  }

  Future<void> _openCameraScreen() async {
    try {
      final containerNo = _isOut ? _containerNoOut.text.trim() : _containerNoIn.text.trim();
      final imageCacheKey = _buildImageCacheKey(containerNo);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ContinuousCameraScreen(
            maxImages: _maxTotalImages,
            containerNo: imageCacheKey,
          ),
        ),
      );
      // Images are stored in provider, no need to return them
      if (mounted) {
        setState(() {}); // Rebuild to show updated images
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening camera: ${e.toString()}')),
        );
      }
    }
  }

  int get _remainingImageCapacity {
    final remaining = _maxTotalImages - _imageProvider.uploadedImages.length;
    return remaining < 0 ? 0 : remaining;
  }

  Future<void> _uploadImages() async {
    // Existing uploaded images do not need to be uploaded again.
    if (_imageProvider.images.isEmpty) {
      return;
    }

    String containerNo =
        _isOut ? _containerNoOut.text.trim() : _containerNoIn.text.trim();
    if (containerNo.isEmpty) {
      throw Exception('Container number is required to upload images');
    }

    setState(() {
      _uploadingImages = true;
      _showUploadProgress = true;
      _uploadProgress = 0.0;
    });

    try {
      // Prepare date and upload path for server-side organization
      final now = DateTime.now();
      final dateStr = "${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}-${now.year}";
      final uploadPath = "container_pics/$dateStr/${_isOut ? 'out' : 'in'}/$containerNo/";

      // Prepare images snapshot to upload and to move on success
      final imagesToUpload = List<File>.from(_imageProvider.images);

      // Determine last existing image index so filenames continue incrementally
      final lastIndex = await _imageUploadService.getLastImageIndex(
        containerNo: containerNo,
        gateStatus: _isOut ? 'out' : 'in',
        date: dateStr,
        uploadPath: uploadPath,
      );

      // Wait for the complete server upload before saving anything locally.
      final _user = context.read<AuthProvider>().user;
      final result = await _imageUploadService.uploadContainerPictures(
        containerNo: containerNo,
        gateStatus: _isOut ? 'out' : 'in',
        images: imagesToUpload,
        date: dateStr,
        uploadPath: uploadPath,
        startingIndex: lastIndex,
        username: _user?.username,
        userId: _user?.id,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );

      if (result['success'] != true) {
        throw Exception(result['message']?.toString() ?? 'Image upload failed');
      }

      // Save every successfully uploaded image to phone storage.
      final appDir = await getApplicationDocumentsDirectory();
      final localCacheFolderName =
          _isOut ? '${containerNo}_${_plateNoOut.trim()}' : containerNo;
      final localDirPath = p.join(appDir.path, uploadPath, localCacheFolderName);
      final localDir = Directory(localDirPath);
      if (!localDir.existsSync()) await localDir.create(recursive: true);

      final destinations = <File>[];
      for (var i = 0; i < imagesToUpload.length; i++) {
        destinations.add(File(p.join(
          localDir.path,
          '$containerNo(${lastIndex + i + 1}).jpg',
        )));
      }

      // These files are independent, so copy them concurrently while still
      // awaiting every result before continuing.
      final savedFiles = await Future.wait(
        List.generate(imagesToUpload.length, (i) async {
          try {
            return await imagesToUpload[i].copy(destinations[i].path);
          } catch (_) {
            return await imagesToUpload[i].rename(destinations[i].path);
          }
        }),
      );

      await _saveUploadedImagesToPhoneStorage(savedFiles);

      for (final f in imagesToUpload) {
        _imageProvider.removeImageByFile(f);
      }

    } catch (e) {
      rethrow;
    } finally {
      if (mounted) {
        setState(() {
          _uploadingImages = false;
          _showUploadProgress = false;
        });
      }
    }
  }

  Future<void> _saveUploadedImagesToPhoneStorage(List<File> files) async {
    if (files.isEmpty) return;

    await Future.wait(files.map((file) async {
      final result = await ImageGallerySaverPlus.saveFile(file.path);
      if (result is! Map || result['isSuccess'] != true) {
        throw Exception('Could not save ${p.basename(file.path)} to phone storage');
      }
    }));
  }

  void _deleteImage(int index) {
    _imageProvider.removeImage(index);
    setState(() {});
  }

  int _extractUploadedImageNumber(File file) {
    final name = p.basenameWithoutExtension(file.path);
    final match = RegExp(r'\((\d+)\)$').firstMatch(name);
    if (match == null) return -1;
    return int.tryParse(match.group(1) ?? '') ?? -1;
  }

  List<File> _getSortedUploadedImages() {
    final files = List<File>.from(_imageProvider.uploadedImages);
    files.sort((a, b) {
      final aNum = _extractUploadedImageNumber(a);
      final bNum = _extractUploadedImageNumber(b);

      if (aNum > 0 && bNum > 0) return aNum.compareTo(bNum);
      if (aNum > 0) return -1;
      if (bNum > 0) return 1;
      return p.basename(a.path).compareTo(p.basename(b.path));
    });
    return files;
  }

  Widget _buildCameraSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Camera Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.camera_alt),
            label: const Text('Open Camera'),
            style: ButtonStyle(
              backgroundColor: MaterialStateProperty.resolveWith<Color>((states) {
                if (states.contains(MaterialState.disabled)) return Colors.grey;
                return Colors.blue;
              }),
              padding: MaterialStateProperty.all(const EdgeInsets.symmetric(vertical: 14)),
              foregroundColor: MaterialStateProperty.all(Colors.white),
            ),
            onPressed: _cameraEnabled ? _openCameraScreen : null,
          ),
        ),
        const SizedBox(height: 16),

        // Submit Button (placed directly under Open Camera)
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 14),
              foregroundColor: Colors.white,
            ),
            onPressed: _canSubmit ? _submit : null,
            icon: _submitting || _uploadingImages
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(_uploadingImages
                ? 'Uploading and saving images...'
                : (_submitting ? 'Submitting...' : 'Submit')),
          ),
        ),
        const SizedBox(height: 12),

        // Image Count
        if (_imageProvider.images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pictures taken: ${_imageProvider.count}/$_remainingImageCapacity',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.blue,
                  ),
                ),
                if (_imageProvider.count > 0)
                  TextButton.icon(
                    icon: const Icon(Icons.delete, size: 18),
                    label: const Text('Clear All'),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Clear all images?'),
                          content: const Text('This will remove all images from the preview. Continue?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Clear', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        _imageProvider.clearAll();
                        if (mounted) setState(() {});
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
              ],
            ),
          ),

        // Upload Progress (shown when background upload is active)
        if (_showUploadProgress)
          Column(
            children: [
              LinearProgressIndicator(value: _uploadProgress),
              const SizedBox(height: 8),
              Text(
                '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),

        // Image Gallery - 3 Columns
        if (_imageProvider.uploadedImages.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Uploaded',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 100,
                child: Builder(
                  builder: (context) {
                    final uploadedImages = _getSortedUploadedImages();
                    const uploadTileHeight = 100.0;
                    const uploadTileWidth = uploadTileHeight * (4 / 3);
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: uploadedImages.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                        final file = uploadedImages[index];
                        final imageNumber = _extractUploadedImageNumber(file);
                        final badgeText = imageNumber > 0
                            ? imageNumber.toString()
                            : (index + 1).toString();

                        return Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            SizedBox(
                              width: uploadTileWidth,
                              height: uploadTileHeight,
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => ImagePreviewViewer(images: uploadedImages, initialIndex: index),
                                  ));
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(file, fit: BoxFit.cover),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 6,
                              left: 6,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: Text(
                                  badgeText,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),

        // Image Gallery - 3 Columns
        if (_imageProvider.images.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Gallery',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  const crossAxisCount = 3;
                  const spacing = 8.0;
                  const tileAspectRatio = 4 / 3;
                  const visibleRows = 3;

                  final tileWidth = (constraints.maxWidth -
                          ((crossAxisCount - 1) * spacing)) /
                      crossAxisCount;
                  final tileHeight = tileWidth / tileAspectRatio;
                  final maxPreviewHeight = (tileHeight * visibleRows) +
                      (spacing * (visibleRows - 1));

                  return SizedBox(
                    height: maxPreviewHeight,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _handleGalleryScrollNotification,
                      child: GridView.builder(
                        controller: _galleryScrollController,
                        primary: false,
                        physics: const ClampingScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: spacing,
                          mainAxisSpacing: spacing,
                          childAspectRatio: tileAspectRatio,
                        ),
                        itemCount: _imageProvider.images.length,
                        itemBuilder: (context, index) {
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: GestureDetector(
                                  onTap: () {
                                    final imgs = List<File>.from(_imageProvider.images);
                                    Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => ImagePreviewViewer(images: imgs, initialIndex: index),
                                    ));
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(
                                        _imageProvider.images[index],
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () => _deleteImage(index),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.only(
                                        topRight: Radius.circular(8),
                                        bottomLeft: Radius.circular(8),
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(3),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 4,
                                left: 4,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
      ],
    );
  }

  Future<void> _submit() async {
    final user = context.read<AuthProvider>().user;
    if (user == null || user.username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated')),
      );
      return;
    }

    // A gate transaction (IN or OUT) must include at least one picture either
    // taken now or already uploaded for this container/gate. Re-sync the image
    // context to the current container first so stale images from another
    // container can never satisfy this check.
    final currentContainerNo =
        (_isOut ? _containerNoOut.text : _containerNoIn.text).trim();
    if (currentContainerNo.isNotEmpty) {
      _setImageProviderContextForContainer(currentContainerNo);
    }
    final hasTakenImages = currentContainerNo.isNotEmpty &&
        _imageProvider.images.any((f) => f.existsSync());
    final hasUploadedImages = currentContainerNo.isNotEmpty &&
        _imageProvider.uploadedImages.isNotEmpty;
    if (!hasTakenImages && !hasUploadedImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('At least 1 picture (taken or uploaded) is required before submitting'),
        ),
      );
      return;
    }

    // Common validations
    if (_isOut) {
      if (_containerNoOut.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a container')),
        );
        return;
      }
      if (_clientIdOut == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please select a valid container from the list')),
        );
        return;
      }
      if (_selectedSizeTypeOut == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Container size/type is required')),
        );
        return;
      }
      if (_isoCodeOut.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ISO code is required')),
        );
        return;
      }
      if (_selectedStatusOut == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select container status')),
        );
        return;
      }
    } else {
      if (_containerNoIn.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Container number is required')),
        );
        return;
      }
      if (_selectedSizeTypeIn == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select size/type')),
        );
        return;
      }
      if (_isoCodeIn.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter ISO code')),
        );
        return;
      }
      if (_dateManufactured.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter manufactured date')),
        );
        return;
      }
      if (!_isValidManufacturedDate(_dateManufactured.text.trim())) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Manufactured date must use a month from 01-12 and a year from 1900-${DateTime.now().year}',
            ),
          ),
        );
        return;
      }
      if (_selectedStatusIn == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select container status')),
        );
        return;
      }
    }

    setState(() => _submitting = true);

    try {
      // Complete image upload and phone save before processing the gate record.
      // Any failure keeps the gate action pending and prevents a success notice.
      await _uploadImages();

      if (_isOut) {
        await _gateService.processGateOut(
          username: user.username,
          payload: {
            'p_id': widget.record.pId,
            'container_no': _containerNoOut.text.trim(),
            'client_id': _clientIdOut,
            'container_status': _selectedStatusOut,
            'size_type': _selectedSizeTypeOut,
            'iso_code': _isoCodeOut.text.trim(),
            'class': _selectedClassOut == 1
                ? 'A'
                : (_selectedClassOut == 2 ? 'B' : 'C'),
            'remarks': _remarksOut.text.trim(),
            'checker_id': _checkerIdOut,
          },
        );

        // Submission succeeded; clear this specific OUT record's cache.
        final combinedKey = _buildOutCacheKey();
        if (combinedKey.isNotEmpty) await _formCache.clearFor(combinedKey, gate: 'OUT');
      } else {
        final classValue =
            _selectedClassIn == 1 ? 'A' : (_selectedClassIn == 2 ? 'B' : 'C');

        // Convert date from MM/YYYY to YYYY-MM-01 format
        final dbDateFormat =
            _convertDateManufacturedToDb(_dateManufactured.text.trim());

        await _gateService.processGateIn(
          username: user.username,
          payload: {
            'p_id': widget.record.pId,
            'container_no': _containerNoIn.text.trim(),
            'client_id': widget.record.clientId,
            'size_type': _selectedSizeTypeIn,
            'date_mnfg': dbDateFormat,
            'iso_code': _isoCodeIn.text.trim(),
            'cnt_status': _selectedStatusIn,
            'cnt_class': classValue,
            'remarks': _remarksIn.text.trim(),
          },
        );

        // Submission succeeded; clear IN cache for this container.
        final inContainerKey = _containerNoIn.text.trim();
        if (inContainerKey.isNotEmpty) {
          await _formCache.clearFor(inContainerKey, gate: 'IN');
        }
      }

      if (!mounted) return;

      final gateLabel = _isOut ? 'gated out' : 'gated in';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully $gateLabel')),
      );

      // Add a delay to allow snackbar to be shown before popping
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      // The image upload/save and gate request have both completed.
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Error: ${ErrorHandler.getUserFriendlyMessage(e)}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {bool enabled = true,
      int maxLines = 1,
      String? hint,
      ValueChanged<String>? onChanged,
      List<TextInputFormatter>? inputFormatters,
      TextCapitalization textCapitalization = TextCapitalization.none}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        inputFormatters: inputFormatters,
        textCapitalization: textCapitalization,
        enabled: enabled,
        maxLines: maxLines,
        style: TextStyle(
          color: enabled ? Colors.black87 : Colors.black,
          fontWeight: enabled ? FontWeight.normal : FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[400]!, width: 1.5),
          ),
          filled: true,
          fillColor: enabled ? Colors.white : Colors.grey[50],
        ),
      ),
    );
  }

  Widget _buildDropdown<T>(String label, T? value, List<LookupItem> options,
      ValueChanged<T?> onChanged,
      {bool enabled = true, String hintText = 'Select an option'}) {
    // Ensure value exists in options, otherwise set to null
    final T? safeValue = options.isEmpty || value == null
        ? null
        : (options.any((e) => e.id == value) ? value : null);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<T>(
        value: safeValue,
        items: options
            .map((e) =>
                DropdownMenuItem<T>(value: e.id as T, child: Text(e.label)))
            .toList(),
        onChanged: enabled ? onChanged : null,
        style: TextStyle(
          color: enabled ? Colors.black87 : Colors.black,
          fontWeight: enabled ? FontWeight.normal : FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[400]!, width: 1.5),
          ),
          filled: true,
          fillColor: enabled ? Colors.white : Colors.grey[50],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label, {bool required = false}) {
    final labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: Colors.grey[700],
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: label, style: labelStyle),
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: Colors.red),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = _isOut
        ? const Color(0xFFf44336) // Red for OUT
        : const Color(0xFF4CAF50); // Green for IN

    return Scaffold(
      appBar: AppBar(
        title: Text(_isOut ? 'Process Gate OUT' : 'Process Gate IN'),
        backgroundColor: primaryColor,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _refreshUploadedImages();
                if (!_isOut) {
                  await _loadContainerDetails();
                }
              },
              child: SingleChildScrollView(
                controller: _formScrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  // Info Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: primaryColor, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isOut ? 'Gate OUT Processing' : 'Gate IN Processing',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF31393C),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text.rich(
                          TextSpan(
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
                            children: const [
                              TextSpan(text: 'Complete all required fields marked with '),
                              TextSpan(
                                text: '*',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (_isOut) ...[
                    // Plate No. (Read-only)
                    Text(
                      'Plate No.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField(
                        '', TextEditingController(text: _plateNoOut),
                        enabled: false),
                    const SizedBox(height: 16),

                    // Hauler (Read-only)
                    Text(
                      'Hauler',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField('', TextEditingController(text: _haulerOut),
                        enabled: false),
                    const SizedBox(height: 16),
                    // GATE OUT FIELDS
                    _buildFieldLabel('Container No.', required: true),
                    const SizedBox(height: 4),
                    Container(
                      key: _containerSearchKey,
                      child: TextField(
                        controller: _containerNoOut,
                        onChanged: _handleContainerSearchChange,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(11),
                        ],
                        decoration: InputDecoration(
                          hintText: 'Type to search containers...',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                        ),
                      ),
                    ),
                    if (_containerSearchResults.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        constraints: const BoxConstraints(maxHeight: 250),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _containerSearchResults.length,
                          itemBuilder: (context, index) {
                            final container = _containerSearchResults[index];
                            return ListTile(
                              dense: true,
                              title: Text(
                                container.containerNo,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              onTap: () => _selectContainer(container),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Client (Read-only)
                    Text(
                      'Client',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField(
                        '', TextEditingController(text: _clientNameOut),
                        enabled: false),
                    const SizedBox(height: 16),

                    // Size/Type (Read-only)
                    Text(
                      'Size/Type',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField(
                      '',
                      TextEditingController(
                          text: _selectedSizeTypeOut == null
                              ? ''
                              : (_sizeTypeOptions
                                  .firstWhere(
                                    (opt) => opt.id == _selectedSizeTypeOut,
                                    orElse: () => LookupItem(id: 0, label: ''),
                                  )
                                  .label)),
                      enabled: false,
                    ),
                    const SizedBox(height: 16),

                    // ISO Code (Read-only)
                    Text(
                      'ISO Code',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField('', _isoCodeOut, enabled: false),
                    const SizedBox(height: 16),

                    // Class (Read-only)
                    Text(
                      'Class',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField(
                      '',
                      TextEditingController(
                          text: _selectedClassOut == null
                              ? ''
                              : (_selectedClassOut == 1
                                  ? 'A'
                                  : (_selectedClassOut == 2 ? 'B' : 'C'))),
                      enabled: false,
                    ),
                    const SizedBox(height: 16),

                    // Container Status (Editable)
                    _buildFieldLabel('Container Status', required: true),
                    const SizedBox(height: 4),
                    _buildDropdown(
                      '',
                      _selectedStatusOut,
                      _statusOptions,
                      (value) {
                        setState(() => _selectedStatusOut = value);
                        _saveCache();
                      },
                      hintText: 'Container Status',
                      enabled: false,
                    ),
                    const SizedBox(height: 16),

                    // Approval Remarks (Read-only)
                    Text(
                      'Approval Remarks',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField(
                        '', TextEditingController(text: _approvalNotesOut),
                        enabled: false, maxLines: 3),
                    const SizedBox(height: 16),

                    // Gate IN Remarks (Read-only)
                    Text(
                      'Gate IN Remarks',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField(
                        '', TextEditingController(text: _gateInRemarksOut),
                        enabled: false, maxLines: 3),
                    const SizedBox(height: 16),

                    // Remarks (Editable)
                    _buildFieldLabel('Remarks', required: true),
                    const SizedBox(height: 4),
                    _buildTextField(
                      '',
                      _remarksOut,
                      maxLines: 4,
                      onChanged: _handleRemarksOutChange,
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ] else ...[
                    // GATE IN FIELDS
                    _buildFieldLabel('Container No.', required: true),
                    const SizedBox(height: 4),
                    _buildTextField('', _containerNoIn,
                        enabled: false, hint: 'Auto-filled'),
                    const SizedBox(height: 16),

                    // Client
                    Text(
                      'Client',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField(
                        '', TextEditingController(text: _clientNameIn),
                        enabled: false),
                    const SizedBox(height: 16),

                    // Checker (Read-only if already set)
                    if (_checkerNameIn.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Checker',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildTextField(
                              '', TextEditingController(text: _checkerNameIn),
                              enabled: false),
                          const SizedBox(height: 16),
                        ],
                      ),

                    // Size/Type
                    _buildFieldLabel('Size/Type', required: true),
                    const SizedBox(height: 4),
                    _buildDropdown(
                      '',
                      _selectedSizeTypeIn,
                      _sizeTypeOptions,
                      (value) {
                        setState(() {
                          _selectedSizeTypeIn = value;
                          if (value != null) {
                            final item = _sizeTypeOptions.firstWhere(
                                (opt) => opt.id == value,
                                orElse: () => LookupItem(id: 0, label: '', extra: ''));

                            // Hard-coded legacy mapping from Size/Type label -> ISO
                            const Map<String, String> legacySizeToIso = {
                              '20DC': '22G1',
                              '20FR': '22P1',
                              '20OT': '22U1',
                              '20RF': '22R1',
                              '20RH': '25R1',
                              '40DC': '42G1',
                              '40FR': '42P1',
                              '40HC': '45G1',
                              '40OT': '42U1',
                              '40RH': '45R1',
                              '45HC': 'L5G1',
                            };

                            String isoValue = '';
                            if (item.label.isNotEmpty) {
                              // Prefer exact mapping by label (e.g., '20DC')
                              isoValue = legacySizeToIso[item.label] ?? '';
                            }

                            // If mapping not found, fall back to parsing label after '-' or use full label
                            if (isoValue.isEmpty && item.label.isNotEmpty) {
                              if (item.label.contains('-')) {
                                final parts = item.label.split('-');
                                isoValue = parts.isNotEmpty ? parts.last : item.label;
                              } else {
                                isoValue = item.label;
                              }
                            }

                            if (isoValue.isNotEmpty) _isoCodeIn.text = isoValue;
                          }
                        });
                        _saveCache();
                      },
                      hintText: 'Select Size/Type',
                    ),
                    const SizedBox(height: 16),

                    // ISO Code
                    _buildFieldLabel('ISO Code', required: true),
                    const SizedBox(height: 4),
                    _buildTextField(
                      '',
                      _isoCodeIn,
                      onChanged: _handleIsoCodeInChange,
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 16),

                    // Manufactured Date
                    _buildFieldLabel('Manufactured Date', required: true),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: _dateManufactured,
                        keyboardType: TextInputType.number,
                        onChanged: _handleDateManufacturedChange,
                        decoration: InputDecoration(
                          hintText: 'mm/yyyy',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey[200]!),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Class
                    _buildFieldLabel('Class', required: true),
                    const SizedBox(height: 4),
                    _buildDropdown(
                      '',
                      _selectedClassIn,
                      _classOptions,
                      (value) {
                        setState(() => _selectedClassIn = value);
                        _saveCache();
                      },
                      hintText: 'Select Class',
                    ),

                    // Container Status
                    _buildFieldLabel('Container Status', required: true),
                    const SizedBox(height: 4),
                    _buildDropdown(
                      '',
                      _selectedStatusIn,
                      _statusOptions,
                      (value) {
                        setState(() => _selectedStatusIn = value);
                        _saveCache();
                      },
                      hintText: 'Container Status',
                    ),
                    const SizedBox(height: 16),

                    // Remarks
                    _buildFieldLabel('Remarks', required: true),
                    const SizedBox(height: 4),
                    _buildTextField(
                      '',
                      _remarksIn,
                      maxLines: 4,
                      onChanged: _handleRemarksInChange,
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Camera Section
                  _buildCameraSection(),

                  const SizedBox(height: 16),
                ],
                ),
              ),
            ),
    );
  }
}
