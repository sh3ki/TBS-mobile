import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lookup_item.dart';
import '../models/pre_record_model.dart';
import '../providers/auth_provider.dart';
import '../services/gate_service.dart';

class ProcessScreen extends StatefulWidget {
  const ProcessScreen({super.key, required this.record});

  final PreRecord record;

  @override
  State<ProcessScreen> createState() => _ProcessScreenState();
}

class _ProcessScreenState extends State<ProcessScreen> {
  final GateService _gateService = GateService();

  final _containerNo = TextEditingController();
  final _dateManufactured = TextEditingController();
  final _isoCode = TextEditingController();
  final _vessel = TextEditingController();
  final _voyage = TextEditingController();
  final _checker = TextEditingController();
  final _exConsignee = TextEditingController();
  final _plateNo = TextEditingController();
  final _hauler = TextEditingController();
  final _haulerDriver = TextEditingController();
  final _licenseNo = TextEditingController();
  final _location = TextEditingController();
  final _chasis = TextEditingController();
  final _contactNo = TextEditingController();
  final _bol = TextEditingController();
  final _remarks = TextEditingController();

  final _shipper = TextEditingController();
  final _bookingNo = TextEditingController();
  final _sealNo = TextEditingController();

  bool _loading = false;
  bool _submitting = false;

  List<LookupItem> _statusOptions = const [];
  List<LookupItem> _sizeTypeOptions = const [];
  List<LookupItem> _loadOptions = const [];

  int? _selectedStatus;
  int? _selectedSizeType;
  int? _selectedLoadType;
  int? _selectedClass = 1; // 1 = A, 2 = B, 3 = C
  int? _selectedSaveAndBook = 2; // 1 = YES, 2 = NO

  int? _clientId;
  String _clientName = '';

  bool get _isOut => widget.record.gateStatus.toUpperCase() == 'OUT';

  @override
  void initState() {
    super.initState();
    _clientId = widget.record.clientId;
    _clientName = widget.record.clientName;
    _containerNo.text = widget.record.containerNo;
    _plateNo.text = widget.record.plateNo;
    _hauler.text = widget.record.hauler;
    
    // Auto-fill checker with current user name (read-only)
    final user = context.read<AuthProvider>().user;
    if (user != null) {
      _checker.text = user.username;
    }
    
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    final user = context.read<AuthProvider>().user;
    if (user == null || user.username.isEmpty) {
      return;
    }

    setState(() => _loading = true);

    try {
      _statusOptions = await _gateService.getStatusOptions(user.username);
      _sizeTypeOptions = await _gateService.getSizeTypeOptions(user.username);
      _loadOptions = await _gateService.getLoadOptions(user.username);

      // Set defaults
      _selectedStatus ??=
          _statusOptions.isNotEmpty ? _statusOptions.first.id : null;
      _selectedSizeType ??=
          _sizeTypeOptions.isNotEmpty ? _sizeTypeOptions.first.id : null;
      
      // For Gate OUT, default load to "Empty"
      if (_isOut && _selectedLoadType == null) {
        final emptyLoad = _loadOptions.firstWhere(
          (e) => e.label.toUpperCase() == 'EMPTY',
          orElse: () => _loadOptions.isNotEmpty ? _loadOptions.first : LookupItem(id: 0, label: '', extra: ''),
        );
        _selectedLoadType = emptyLoad.id;
      } else if (_selectedLoadType == null && _loadOptions.isNotEmpty) {
        _selectedLoadType = _loadOptions.first.id;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading options: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _validateContainerForOut() async {
    final user = context.read<AuthProvider>().user;
    if (user == null || user.username.isEmpty) {
      return;
    }

    final container = _containerNo.text.trim().toUpperCase();
    if (container.isEmpty || container.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid 11-character container number.')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final data = await _gateService.validateContainer(
          username: user.username, containerNo: container);

      _clientId = (data['client_id'] as num?)?.toInt() ?? _clientId;
      _clientName = (data['client_name'] ?? _clientName).toString();

      _isoCode.text = (data['iso_code'] ?? '').toString();
      _plateNo.text = (data['plate_no'] ?? _plateNo.text).toString();
      _hauler.text = (data['hauler'] ?? _hauler.text).toString();

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Container validated successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submit() async {
    // Validation
    if (_containerNo.text.trim().length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Container number must be 11 characters.')),
      );
      return;
    }

    if (_selectedStatus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a status.')),
      );
      return;
    }

    if (_selectedSizeType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select size/type.')),
      );
      return;
    }

    if (_selectedLoadType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select load type.')),
      );
      return;
    }

    if (!_isOut) {
      if (_dateManufactured.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter date manufactured.')),
        );
        return;
      }
      if (_exConsignee.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter ex-consignee.')),
        );
        return;
      }
      if (_bol.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter bill of lading.')),
        );
        return;
      }
    } else {
      if (_bookingNo.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter booking number.')),
        );
        return;
      }
      if (_shipper.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter shipper.')),
        );
        return;
      }
      if (_sealNo.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter seal number.')),
        );
        return;
      }
    }

    setState(() => _submitting = true);

    try {
      final user = context.read<AuthProvider>().user;
      if (user == null || user.username.isEmpty) {
        throw Exception('User not authenticated');
      }

      String message;

      if (_isOut) {
        final saveAndBook = _selectedSaveAndBook == 1 ? 'YES' : 'NO';
        message = await _gateService.processGateOut(
          username: user.username,
          payload: {
            'p_id': widget.record.pId,
            'container_no': _containerNo.text.trim(),
            'client_id': _clientId,
            'container_status': _selectedStatus,
            'size_type': _selectedSizeType,
            'iso_code': _isoCode.text.trim(),
            'vessel': _vessel.text.trim(),
            'voyage': _voyage.text.trim(),
            'plate_no': _plateNo.text.trim(),
            'hauler': _hauler.text.trim(),
            'hauler_driver': _haulerDriver.text.trim(),
            'license_no': _licenseNo.text.trim(),
            'checker': _checker.text.trim(),
            'location': _location.text.trim(),
            'load_type': _selectedLoadType,
            'chasis': _chasis.text.trim(),
            'contact_no': _contactNo.text.trim(),
            'shipper': _shipper.text.trim(),
            'booking_no': _bookingNo.text.trim(),
            'seal_no': _sealNo.text.trim(),
            'remarks': _remarks.text.trim(),
            'save_and_book': saveAndBook,
          },
        );
      } else {
        final classValue = _selectedClass == 1 ? 'A' : (_selectedClass == 2 ? 'B' : 'C');
        message = await _gateService.processGateIn(
          username: user.username,
          payload: {
            'p_id': widget.record.pId,
            'container_no': _containerNo.text.trim(),
            'client_id': _clientId,
            'date_mnfg': _dateManufactured.text.trim(),
            'cnt_status': _selectedStatus,
            'size_type': _selectedSizeType,
            'iso_code': _isoCode.text.trim(),
            'cnt_class': classValue,
            'vessel': _vessel.text.trim(),
            'voyage': _voyage.text.trim(),
            'checker': _checker.text.trim(),
            'ex_consignee': _exConsignee.text.trim(),
            'load_type': _selectedLoadType,
            'plate_no': _plateNo.text.trim(),
            'hauler': _hauler.text.trim(),
            'hauler_driver': _haulerDriver.text.trim(),
            'license_no': _licenseNo.text.trim(),
            'location': _location.text.trim(),
            'chasis': _chasis.text.trim(),
            'contact_no': _contactNo.text.trim(),
            'bol': _bol.text.trim(),
            'remarks': _remarks.text.trim(),
          },
        );
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
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
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
          filled: !enabled,
          fillColor: !enabled ? Colors.grey[100] : null,
        ),
      ),
    );
  }

  Widget _buildDropdown<T>(
    String label,
    T? value,
    List<LookupItem> options,
    ValueChanged<T?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<T>(
        value: options.any((e) => e.id == value) ? value : null,
        items: options
            .map((e) => DropdownMenuItem<T>(
                value: e.id as T, child: Text(e.label)))
            .toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
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
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _containerNo,
      _dateManufactured,
      _isoCode,
      _vessel,
      _voyage,
      _checker,
      _exConsignee,
      _plateNo,
      _hauler,
      _haulerDriver,
      _licenseNo,
      _location,
      _chasis,
      _contactNo,
      _bol,
      _remarks,
      _shipper,
      _bookingNo,
      _sealNo,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = _isOut 
        ? const Color(0xFFf44336)  // Red for OUT
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
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info Card - Full Width
                  Container(
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Complete all required fields and save record.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Container No
                  Text(
                    'Container No. *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildTextField('', _containerNo, enabled: !_isOut),
                  const SizedBox(height: 16),

                  if (_isOut)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.search),
                          label: const Text('Validate Container'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                          ),
                          onPressed: _loading ? null : _validateContainerForOut,
                        ),
                      ),
                    ),

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
                  _buildTextField('', TextEditingController(text: _clientName), enabled: false),
                  const SizedBox(height: 16),

                  // Gate IN Specific Fields
                  if (!_isOut) ...[
                    Text(
                      'Date Manufactured (mm/yyyy) *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField('', _dateManufactured, hint: 'mm/yyyy'),
                    const SizedBox(height: 16),

                    Text(
                      'Status *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildDropdown(
                      '',
                      _selectedStatus,
                      _statusOptions,
                      (value) => setState(() => _selectedStatus = value),
                    ),
                    const SizedBox(height: 16),

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
                      _selectedSizeType,
                      _sizeTypeOptions,
                      (value) => setState(() => _selectedSizeType = value),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'ISO Code *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField('', _isoCode),
                    const SizedBox(height: 16),

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
                      _selectedClass,
                      [
                        LookupItem(id: 1, label: 'A', extra: ''),
                        LookupItem(id: 2, label: 'B', extra: ''),
                        LookupItem(id: 3, label: 'C', extra: ''),
                      ],
                      (value) => setState(() => _selectedClass = value),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'Ex-Consignee *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField('', _exConsignee),
                    const SizedBox(height: 16),
                  ] else ...[
                    // Gate OUT Specific Fields
                    Text(
                      'Status *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildDropdown(
                      '',
                      _selectedStatus,
                      _statusOptions,
                      (value) => setState(() => _selectedStatus = value),
                    ),
                    const SizedBox(height: 16),

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
                      _selectedSizeType,
                      _sizeTypeOptions,
                      (value) => setState(() => _selectedSizeType = value),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'ISO Code',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField('', _isoCode, enabled: false),
                    const SizedBox(height: 16),
                  ],

                  // Common Fields
                  Text(
                    'Vessel *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildTextField('', _vessel),
                  const SizedBox(height: 16),

                  Text(
                    'Voyage *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildTextField('', _voyage),
                  const SizedBox(height: 16),

                  Text(
                    'Checker (Read-only) *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildTextField('', _checker, enabled: false),
                  const SizedBox(height: 16),

                  // Gate-Specific Fields
                  Text(
                    'Plate No. *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildTextField('', _plateNo),
                  const SizedBox(height: 16),

                  Text(
                    'Hauler *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildTextField('', _hauler),
                  const SizedBox(height: 16),

                  Text(
                    'Hauler Driver *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildTextField('', _haulerDriver),
                  const SizedBox(height: 16),

                  Text(
                    'License No. *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildTextField('', _licenseNo),
                  const SizedBox(height: 16),

                  Text(
                    'Location *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildTextField('', _location),
                  const SizedBox(height: 16),

                  Text(
                    'Load Type *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildDropdown(
                    '',
                    _selectedLoadType,
                    _loadOptions,
                    (value) => setState(() => _selectedLoadType = value),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Chasis *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildTextField('', _chasis),
                  const SizedBox(height: 16),

                  Text(
                    'Contact No. *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildTextField('', _contactNo),
                  const SizedBox(height: 16),

                  if (_isOut) ...[
                    Text(
                      'Booking No. *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField('', _bookingNo),
                    const SizedBox(height: 16),

                    Text(
                      'Shipper *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField('', _shipper),
                    const SizedBox(height: 16),

                    Text(
                      'Seal No. *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField('', _sealNo),
                    const SizedBox(height: 16),

                    Text(
                      'Save and Book *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildDropdown(
                      '',
                      _selectedSaveAndBook,
                      [
                        LookupItem(id: 1, label: 'YES', extra: ''),
                        LookupItem(id: 2, label: 'NO', extra: ''),
                      ],
                      (value) => setState(() => _selectedSaveAndBook = value),
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    Text(
                      'Bill of Lading (BOL) *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildTextField('', _bol),
                    const SizedBox(height: 16),
                  ],

                  Text(
                    'Remarks',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildTextField(
                    '',
                    _remarks,
                    maxLines: 4,
                    hint: 'Optional remarks...',
                  ),

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              _isOut ? 'PROCESS OUT' : 'PROCESS IN',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}
