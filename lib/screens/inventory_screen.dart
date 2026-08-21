import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/inventory_service.dart';
import '../utils/error_handler.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final InventoryService _service = InventoryService();
  late TextEditingController _searchController;
  Timer? _debounce;
  bool _loading = false;
  List<Map<String, dynamic>> _records = [];
  bool _isListView = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(_searchController.text.trim());
    });
  }

  Future<void> _loadInitial() async {
    final user = context.read<AuthProvider>().user;
    if (user == null || user.username.isEmpty) return;

    setState(() => _loading = true);
    try {
      final data = await _service.loadCurrentInventory(username: user.username);
      setState(() => _records = data);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorHandler.getUserFriendlyMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _performSearch(String term) async {
    final user = context.read<AuthProvider>().user;
    if (user == null || user.username.isEmpty) return;

    setState(() => _loading = true);
    try {
      final data = await _service.searchInventory(username: user.username, searchTerm: term);
      setState(() => _records = data);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorHandler.getUserFriendlyMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        backgroundColor: const Color(0xFF3E9AF4),
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3E9AF4).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF3E9AF4),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Inventory',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF31393C),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Search inventory by container number',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                ),
              ),
                const SizedBox(height: 16),
                // Search field with view toggle
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by container no.',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: IconButton(
                        onPressed: () => setState(() => _isListView = !_isListView),
                        color: const Color(0xFF3E9AF4),
                        icon: Icon(_isListView ? Icons.list : Icons.grid_view),
                        tooltip: _isListView ? 'List view' : 'Card view',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF3E9AF4),
              onRefresh: _loadInitial,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  const SizedBox(height: 8),
                  if (_loading)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: CircularProgressIndicator(
                          color: const Color(0xFF3E9AF4),
                        ),
                      ),
                    )
                  else if (_records.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Column(
                          children: [
                            Icon(
                              Icons.inbox,
                              size: 64,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isEmpty
                                  ? 'No inventory records'
                                  : 'No records found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...(
                    _isListView ? _records.map((r) => _buildInventoryListRow(r)) : _records.map((r) => _buildInventoryCard(r))
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryCard(Map<String, dynamic> r) {
    const Color primaryColor = Color(0xFF3E9AF4);
    const Color secondaryColor = Color(0xFF31393C);

    final containerNo = (r['container_no'] ?? r['cno'] ?? '').toString();
    final client = (r['client_name'] ?? r['client'] ?? '').toString();
    final sizeType = (r['size_type'] ?? r['size'] ?? r['size_type_label'] ?? '').toString();
    final iso = (r['iso_code'] ?? '').toString();
    final clas = (r['condition'] ?? r['class'] ?? '').toString();
    final status = (r['container_status'] ?? r['status'] ?? '').toString();
    final approval = (r['approval_notes'] ?? r['approval'] ?? r['app_notes'] ?? '').toString();
    final gateRemarks = (r['remarks'] ?? r['gate_remarks'] ?? r['eir_notes'] ?? '').toString();
    final remarks = (r['remarks'] ?? r['eir_notes'] ?? '').toString();
    final holdNotes = (r['hold_notes'] ?? r['hold_note'] ?? r['hold'] ?? r['hold_notes_text'] ?? r['hold_reason'] ?? r['hold_notes_display'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.inventory_2, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    containerNo.isEmpty ? 'N/A' : containerNo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(Icons.person, 'Client', client),
                const SizedBox(height: 8),
                _infoRow(Icons.straighten, 'Size/Type', sizeType),
                const SizedBox(height: 8),
                _infoRow(Icons.qr_code, 'ISO Code', iso),
                const SizedBox(height: 8),
                _infoRow(Icons.category, 'Class', clas),
                const SizedBox(height: 8),
                _infoRow(Icons.info_outline, 'Container Status', status),
                const SizedBox(height: 8),
                _infoRow(Icons.check_circle_outline, 'Approval remarks', approval),
                const SizedBox(height: 8),
                _infoRow(Icons.note, 'Remarks', remarks),
                const SizedBox(height: 8),
                if (holdNotes.isNotEmpty) ...[
                  _infoRow(Icons.lock, 'Hold notes', holdNotes),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryListRow(Map<String, dynamic> r) {
    final containerNo = (r['container_no'] ?? r['containerNo'] ?? '').toString();
    final status = (r['container_status'] ?? r['status'] ?? '').toString();
    final holdNotes = (r['hold_notes'] ?? r['hold_note'] ?? r['hold'] ?? r['hold_notes_text'] ?? r['hold_reason'] ?? r['hold_notes_display'] ?? '').toString();
    const Color primaryColor = Color(0xFF3E9AF4);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.inventory_2, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    containerNo.isEmpty ? 'N/A' : containerNo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                if (holdNotes.isNotEmpty) ...[
                  IconButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Hold notes'),
                          content: Text(holdNotes),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.lock, color: Colors.white, size: 18),
                    tooltip: 'Hold notes',
                  ),
                ],
                Text(
                  status.isEmpty ? '-' : status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF31393C), size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value.isEmpty ? 'N/A' : value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
