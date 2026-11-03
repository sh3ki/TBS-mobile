import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants/app_info.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';
import 'pre_in_screen.dart';
import 'pre_out_screen.dart';
import 'inventory_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with WidgetsBindingObserver {
  bool _needsPermissions = false;
  Map<Permission, PermissionStatus> _statuses = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check permissions when the app comes back from Settings
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    // Check required permissions individually and treat file access as
    // satisfied when any of photos/videos/storage is granted.
    final cam = await Permission.camera.status;
    final mic = await Permission.microphone.status;
    final photos = await Permission.photos.status;
    final videos = await Permission.videos.status;
    final storage = await Permission.storage.status;

    final results = <Permission, PermissionStatus>{
      Permission.camera: cam,
      Permission.microphone: mic,
      Permission.photos: photos,
      Permission.videos: videos,
      Permission.storage: storage,
    };

    final fileOk = photos.isGranted || videos.isGranted || storage.isGranted;
    final needs = !(cam.isGranted && mic.isGranted && fileOk);
    if (!mounted) return;
    setState(() {
      _statuses = results;
      _needsPermissions = needs;
    });
  }

  Future<void> _requestAllPermissions() async {
    final perms = [
      Permission.camera,
      Permission.microphone,
      Permission.photos,
      Permission.videos,
      Permission.storage,
    ];
    final statuses = await perms.request();
    if (!mounted) return;
    // Combine results and treat file access as satisfied when any of the
    // file-related permissions are granted.
    final cam = statuses[Permission.camera] ?? _statuses[Permission.camera] ?? PermissionStatus.denied;
    final mic = statuses[Permission.microphone] ?? _statuses[Permission.microphone] ?? PermissionStatus.denied;
    final photos = statuses[Permission.photos] ?? _statuses[Permission.photos] ?? PermissionStatus.denied;
    final videos = statuses[Permission.videos] ?? _statuses[Permission.videos] ?? PermissionStatus.denied;
    final storage = statuses[Permission.storage] ?? _statuses[Permission.storage] ?? PermissionStatus.denied;

    final fileOk = photos.isGranted || videos.isGranted || storage.isGranted;
    final needs = !(cam.isGranted && mic.isGranted && fileOk);

    setState(() {
      _statuses[Permission.camera] = cam;
      _statuses[Permission.microphone] = mic;
      _statuses[Permission.photos] = photos;
      _statuses[Permission.videos] = videos;
      _statuses[Permission.storage] = storage;
      _needsPermissions = needs;
    });
    if (_needsPermissions) {
      // Some permissions may be permanently denied
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable required permissions in Settings')),
      );
    }
  }

  void _openAppSettings() async {
    await openAppSettings();
    // After returning from settings, re-check permissions
    _checkPermissions();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final fullName = auth.user?.fullName.trim();
    final username = auth.user?.username.trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF3E9AF4),
        elevation: 0,
        title: const Text(
          'TBS Container Yard',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'v$appVersion',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ],
        centerTitle: false,
      ),
      body: Container(
        color: Colors.grey[50],
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              if (_needsPermissions)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade700),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Permissions required',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'The app needs Camera, Microphone and File access to work properly. Please grant permissions.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          ElevatedButton(
                            onPressed: _requestAllPermissions,
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                            child: const Text('Grant'),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: _openAppSettings,
                            child: const Text('Open Settings'),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3E9AF4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fullName != null && fullName.isNotEmpty
                                    ? fullName
                                    : username,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF31393C),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                username,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: Column(
                  children: [
                    _buildMenuButton(
                      context: context,
                      icon: Icons.login,
                      label: 'GATE IN',
                      subtitle: 'Process incoming containers',
                      color: const Color(0xFF4CAF50),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PreInScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildMenuButton(
                      context: context,
                      icon: Icons.logout,
                      label: 'GATE OUT',
                      subtitle: 'Process outgoing containers',
                      color: const Color(0xFFf44336),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PreOutScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildMenuButton(
                      context: context,
                      icon: Icons.inventory_2,
                      label: 'INVENTORY',
                      subtitle: 'Search inventory',
                      color: const Color(0xFF3E9AF4),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const InventoryScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await context.read<AuthProvider>().logout();
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'LOGOUT',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF31393C),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
