import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io';

import '../models/lookup_item.dart';
import '../models/pre_record_model.dart';
import '../providers/auth_provider.dart';
import '../services/gate_service.dart';
import '../services/image_upload_service.dart';
import '../services/image_provider_service.dart';
import '../screens/continuous_camera_screen.dart';
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
  final GateService _gateService = GateService();
  final ImageUploadService _imageUploadService = ImageUploadService();
  final _imageProvider = ImageProviderService();
  final ScrollController _formScrollController = ScrollController();
  final ScrollController _galleryScrollController = ScrollController();

  Timer? _searchDebounce;
  final _containerSearchKey = GlobalKey();
  OverlayEntry? _dropdownOverlay;

  // Image Upload Variables
  bool _uploadingImages = false;
  double _uploadProgress = 0.0;
  bool _showUploadProgress = false;

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
  List<ContainerSearchResult> _containerSearchResults = [];
  int? _selectedContainerId;

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

  // Gate OUT - Additional details from inventory
  String _approvalNotesOut = '';
  String _gateInRemarksOut = '';

  bool get _isOut => widget.record.gateStatus.toUpperCase() == 'OUT';

  @override
  void initState() {
    super.initState();
    if (_isOut) {
      // Initialize Gate OUT fields from PreRecord
      // Only pre-fill container number when it's a valid, non-placeholder value.
      final containerNoFromRecord = widget.record.containerNo?.toString().trim() ?? '';
      if (containerNoFromRecord.isNotEmpty && containerNoFromRecord != '-' && containerNoFromRecord.toLowerCase() != 'record not found') {
        _containerNoOut.text = containerNoFromRecord;
      }
      _plateNoOut = widget.record.plateNo;
      _haulerOut = widget.record.hauler;
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
          _imageProvider.setCurrentContainer(cno);
        }
      }
    });
    _containerNoOut.addListener(() {
      if (mounted) {
        _userEdited = true;
        _allowCamera = false;
        _updateCameraEnabled();
        final cno = _containerNoOut.text.trim();
        if (cno.isNotEmpty) {
          _imageProvider.setCurrentContainer(cno);
        }
      }
    });
    _isoCodeIn.addListener(() {
      if (mounted) {
        _userEdited = true;
        _allowCamera = false;
        _updateCameraEnabled();
      }
    });
    // Initialize camera enabled state (will be updated after loads)
    _updateCameraEnabled();
  }

  void _updateCameraEnabled() {
    final fetchedEnabled = _isOut ? _containerFetched : (_isoFetched || _containerFetched);
    final enabled = _allowCamera || (fetchedEnabled && !_userEdited);
    if (mounted) {
      setState(() => _cameraEnabled = enabled);
    }
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
      });

      // NOW that options are loaded, reload container details so they can be properly validated and set
      if (!_isOut && _containerNoIn.text.isNotEmpty) {
        await _loadContainerDetails();
      } else if (_isOut && _containerNoOut.text.isNotEmpty) {
        // For Gate OUT, fetch all container details after lookups are loaded
        await _loadGateOutContainerDetails();
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
        setState(() {
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
        // Fetch any existing server images for this container and show them in gallery
        try {
          final now = DateTime.now();
          final dateStr = "${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}-${now.year}";
          final uploadPath = "container_pics/$dateStr/${_isOut ? 'out' : 'in'}/";
          _imageProvider.setCurrentContainer(_containerNoIn.text.trim());
          final files = await _imageUploadService.fetchExistingImages(
            containerNo: _containerNoIn.text.trim(),
            gateStatus: _isOut ? 'out' : 'in',
            date: dateStr,
            uploadPath: uploadPath + _containerNoIn.text.trim(),
          );
          if (mounted && files.isNotEmpty) {
            for (final f in files) {
              _imageProvider.addImage(f);
            }
            setState(() {});
          }
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Error loading container details: ${ErrorHandler.getUserFriendlyMessage(e)}')),
        );
      }
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

          // Set container status from inventory
          final containerStatusId =
              int.tryParse(details['container_status']?.toString() ?? '0');
          if (containerStatusId != null &&
              containerStatusId > 0 &&
              _statusOptions.any((opt) => opt.id == containerStatusId)) {
            _selectedStatusOut = containerStatusId;
          }

          // Set approval notes from inventory
          _approvalNotesOut =
              details['approval_notes']?.toString().trim() ?? '';

          // Set gate in remarks from inventory remarks field
          _gateInRemarksOut = details['remarks']?.toString().trim() ?? '';

          // Set remarks from pre_inventory
          _remarksOut.text =
              details['pre_inventory_remarks']?.toString().trim() ?? '';
        });
        // Mark that these values came from a fetch/load, not from user typing
        _userEdited = false;
        _updateCameraEnabled();
        // Fetch any existing server images for this container and show them in gallery
        try {
          final now = DateTime.now();
          final dateStr = "${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}-${now.year}";
          final uploadPath = "container_pics/$dateStr/out/";
          _imageProvider.setCurrentContainer(_containerNoOut.text.trim());
          final files = await _imageUploadService.fetchExistingImages(
            containerNo: _containerNoOut.text.trim(),
            gateStatus: 'out',
            date: dateStr,
            uploadPath: uploadPath + _containerNoOut.text.trim(),
          );
          if (mounted && files.isNotEmpty) {
            for (final f in files) {
              _imageProvider.addImage(f);
            }
            setState(() {});
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

        // Show overlay after state is updated
        _showContainerDropdownOverlay();
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
    // Remove non-numeric characters
    String cleaned = value.replaceAll(RegExp(r'\D'), '');

    // If cleaned is empty, clear the field
    if (cleaned.isEmpty) {
      _dateManufactured.text = '';
      return;
    }

    // If length > 6, keep only first 6 digits
    if (cleaned.length > 6) cleaned = cleaned.substring(0, 6);

    // Format as mm/yyyy
    String formatted = '';
    if (cleaned.length <= 2) {
      formatted = cleaned;
    } else if (cleaned.length <= 6) {
      formatted = '${cleaned.substring(0, 2)}/${cleaned.substring(2)}';
    }

    // Only update if different from current
    if (_dateManufactured.text != formatted) {
      _dateManufactured.text = formatted;
      // Keep cursor at the end
      _dateManufactured.selection = TextSelection.fromPosition(
        TextPosition(offset: formatted.length),
      );
    }
  }

  /// Convert MM/YYYY format to YYYY-MM-01 format (first day of month)
  /// Input: "02/2025" → Output: "2025-02-01"
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

    return false;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _dropdownOverlay?.remove();
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
      setState(() => _showContainerDropdown = false);
    }
  }

  void _showContainerDropdownOverlay() {
    _hideContainerDropdown();

    if (_containerSearchResults.isEmpty) return;

    final RenderBox renderBox =
        _containerSearchKey.currentContext?.findRenderObject() as RenderBox;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    _dropdownOverlay = OverlayEntry(
      builder: (context) => Positioned(
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
      ),
    );

    Overlay.of(context).insert(_dropdownOverlay!);
  }

  void _handleContainerSearchChange(String value) {
    // Debounce the search - only trigger after 3+ characters
    _searchDebounce?.cancel();
    // Editing search should disable camera until a successful submit
    if (mounted) {
      _allowCamera = false;
      _updateCameraEnabled();
    }
    if (value.length >= 3) {
      _searchDebounce = Timer(const Duration(milliseconds: 500), () {
        _searchContainers(value);
      });
    } else {
      _hideContainerDropdown();
    }
  }

  void _selectContainer(ContainerSearchResult container) {
    _hideContainerDropdown();

    setState(() {
      _containerNoOut.text = container.containerNo;
      _selectedContainerId = container.id;
      _clientNameOut = container.clientName;
      _clientIdOut = container.clientId;
      _selectedSizeTypeOut = container.sizeTypeId;
      _isoCodeOut.text = container.isoCode;
      _plateNoOut = container.plateNo;
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
      _cameraEnabled = false;
      _allowCamera = false;
      _updateCameraEnabled();
    });

    // Mark that the upcoming fetch was triggered by a user selection
    _lastFetchFromSelection = true;
    // Fetch additional container details from inventory
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

          // Set remarks from pre_inventory
          _remarksOut.text =
              details['pre_inventory_remarks']?.toString().trim() ?? '';

          // Pre-fill container status from inventory
          final containerStatusId =
              int.tryParse(details['container_status']?.toString() ?? '0');
          if (containerStatusId != null &&
              containerStatusId > 0 &&
              _statusOptions.any((opt) => opt.id == containerStatusId)) {
            _selectedStatusOut = containerStatusId;
          }
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
      }
    } catch (e) {
      print('DEBUG: Error fetching container details for Gate OUT: $e');
    }
  }

  Future<void> _openCameraScreen() async {
    try {
      final containerNo = _isOut ? _containerNoOut.text.trim() : _containerNoIn.text.trim();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ContinuousCameraScreen(maxImages: 100, containerNo: containerNo),
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

  Future<void> _uploadImages() async {
    if (_imageProvider.images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No images to upload')),
      );
      return;
    }

    String containerNo =
        _isOut ? _containerNoOut.text.trim() : _containerNoIn.text.trim();
    if (containerNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Container number is required to upload images')),
      );
      return;
    }

    setState(() {
      _uploadingImages = true;
      _showUploadProgress = true;
      _uploadProgress = 0.0;
    });

    try {
      // Show 5-second upload feedback
      await Future.delayed(const Duration(seconds: 5));

      // Prepare date and upload path for server-side organization
      final now = DateTime.now();
      final dateStr = "${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}-${now.year}";
      final uploadPath = "container_pics/$dateStr/${_isOut ? 'out' : 'in'}/$containerNo/";

      // Determine last existing image index so filenames continue incrementally
      final lastIndex = await _imageUploadService.getLastImageIndex(
        containerNo: containerNo,
        gateStatus: _isOut ? 'out' : 'in',
        date: dateStr,
        uploadPath: uploadPath,
      );

      // Start upload in background but keep gallery visible and cached per-container
      _imageUploadService
          .uploadContainerPictures(
        containerNo: containerNo,
        gateStatus: _isOut ? 'out' : 'in',
        images: _imageProvider.images,
        date: dateStr,
        uploadPath: uploadPath,
        startingIndex: lastIndex,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      )
          .then((result) {
        if (mounted) {
          setState(() {
            _uploadingImages = false;
            _showUploadProgress = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Upload finished')),
          );
        }
      }).catchError((e) {
        if (mounted) {
          setState(() {
            _uploadingImages = false;
            _showUploadProgress = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload error: $e')),
          );
        }
      });

      if (mounted) {
        // Immediately allow interaction; keep gallery (do not clear)
        setState(() {
          _uploadingImages = false;
          _showUploadProgress = true; // show until background finishes
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Images uploading in background'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadingImages = false;
          _showUploadProgress = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload error: ${e.toString()}')),
        );
      }
    }
  }

  void _deleteImage(int index) {
    _imageProvider.removeImage(index);
    setState(() {});
  }

  Widget _buildCameraSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Submit Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 14),
              foregroundColor: Colors.white,
            ),
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(_submitting ? 'Submitting...' : 'Submit'),
          ),
        ),
        const SizedBox(height: 12),

        // Camera Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.camera_alt),
            label: const Text('Open Camera'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: const EdgeInsets.symmetric(vertical: 14),
              foregroundColor: Colors.white,
            ),
            onPressed: _cameraEnabled ? _openCameraScreen : null,
          ),
        ),
        const SizedBox(height: 16),

        // Image Count
        if (_imageProvider.images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pictures taken: ${_imageProvider.count}/100',
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
                    onPressed: () {
                      _imageProvider.clearAll();
                      setState(() {});
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
              ],
            ),
          ),

        // Upload Button
        if (_imageProvider.images.isNotEmpty)
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _uploadingImages
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.cloud_upload),
                  label: Text(
                      _uploadingImages ? 'Uploading...' : 'Upload Pictures'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _uploadingImages ? null : _uploadImages,
                ),
              ),
              const SizedBox(height: 16),

              // Upload Progress
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
                  const tileAspectRatio = 3 / 4;
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
      if (_selectedStatusIn == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select container status')),
        );
        return;
      }
    }

    setState(() => _submitting = true);

    try {
      String message;

      if (_isOut) {
        message = await _gateService.processGateOut(
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
      } else {
        final classValue =
            _selectedClassIn == 1 ? 'A' : (_selectedClassIn == 2 ? 'B' : 'C');

        // Convert date from MM/YYYY to YYYY-MM-01 format
        final dbDateFormat =
            _convertDateManufacturedToDb(_dateManufactured.text.trim());

        message = await _gateService.processGateIn(
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
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

      // Add a delay to allow snackbar to be shown before popping
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      // Stay on the process screen; enable camera after successful submit
      if (mounted) {
        setState(() {
          if (_isOut) {
            _containerFetched = true;
          } else {
            _isoFetched = true;
          }
          // Allow camera only after a successful submit
          _allowCamera = true;
          _userEdited = false;
        });
        _updateCameraEnabled();
      }
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
      {bool enabled = true, int maxLines = 1, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
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
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
        ),
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
          : SingleChildScrollView(
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
                        Text(
                          'Complete all required fields marked with *',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
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
                    Text(
                      'Container No. *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      key: _containerSearchKey,
                      child: TextField(
                        controller: _containerNoOut,
                        onChanged: _handleContainerSearchChange,
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
                    Text(
                      'Container Status *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildDropdown(
                      '',
                      _selectedStatusOut,
                      _statusOptions,
                      (value) => setState(() => _selectedStatusOut = value),
                      hintText: 'Select Container Status',
                      enabled: true,
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
                    Text(
                      'Remarks *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField('', _remarksOut, maxLines: 4),
                  ] else ...[
                    // GATE IN FIELDS
                    Text(
                      'Container No. *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
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
                    Text(
                      'Size/Type *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildDropdown(
                      '',
                      _selectedSizeTypeIn,
                      _sizeTypeOptions,
                      (value) => setState(() => _selectedSizeTypeIn = value),
                      hintText: 'Select Size/Type',
                    ),
                    const SizedBox(height: 16),

                    // ISO Code
                    Text(
                      'ISO Code *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField('', _isoCodeIn),
                    const SizedBox(height: 16),

                    // Manufactured Date
                    Text(
                      'Manufactured Date *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: _dateManufactured,
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
                    Text(
                      'Class *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildDropdown(
                      '',
                      _selectedClassIn,
                      _classOptions,
                      (value) => setState(() => _selectedClassIn = value),
                      hintText: 'Select Class',
                    ),

                    // Container Status
                    Text(
                      'Container Status *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildDropdown(
                      '',
                      _selectedStatusIn,
                      _statusOptions,
                      (value) => setState(() => _selectedStatusIn = value),
                      hintText: 'Select Container Status',
                    ),
                    const SizedBox(height: 16),

                    // Remarks
                    Text(
                      'Remarks',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField('', _remarksIn, maxLines: 4),
                  ],

                  const SizedBox(height: 24),

                  // Camera Section
                  _buildCameraSection(),

                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}
