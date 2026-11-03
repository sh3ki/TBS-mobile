import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/app_update_service.dart';
import '../widgets/tbs_logo.dart';
import 'login_screen.dart';
import 'menu_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    await auth.restoreSession();
    final updateInfo = await AppUpdateService().checkForUpdate();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) {
      return;
    }

    if (updateInfo?.shouldUpdate == true) {
      await _showUpdateDialog(updateInfo!);
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            auth.isLoggedIn ? const MenuScreen() : const LoginScreen(),
      ),
    );
  }

  Future<void> _showUpdateDialog(AppUpdateInfo updateInfo) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var downloading = false;
        var progress = 0.0;
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> installUpdate() async {
              setDialogState(() {
                downloading = true;
                errorMessage = null;
              });

              try {
                await AppUpdateService().downloadAndInstall(
                  updateInfo.apkUrl,
                  onProgress: (received, total) {
                    if (total > 0) {
                      setDialogState(() => progress = received / total);
                    }
                  },
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              } catch (error) {
                setDialogState(() {
                  downloading = false;
                  errorMessage = error.toString().contains('UNKNOWN_SOURCES_PERMISSION_REQUIRED')
                      ? 'Allow this app to install unknown apps in Settings, then try again.'
                      : 'Unable to download or open the update.';
                });
                print('[SplashScreen] App update failed: $error');
              }
            }

            return AlertDialog(
              title: const Text('Update available'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('A newer version (${updateInfo.latestVersion}) is available.'),
                  const SizedBox(height: 12),
                  if (downloading) ...[
                    LinearProgressIndicator(value: progress == 0 ? null : progress),
                    const SizedBox(height: 8),
                    Text('${(progress * 100).round()}% downloaded'),
                  ],
                  if (errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(errorMessage!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: downloading
                      ? null
                      : () {
                          AppUpdateService.deferUpdate(updateInfo);
                          Navigator.of(dialogContext).pop();
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Later'),
                ),
                ElevatedButton(
                  onPressed: downloading ? null : installUpdate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(downloading ? 'Downloading...' : 'Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF3E9AF4),
              const Color(0xFF3E9AF4).withOpacity(0.85),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const TbsLogo(width: 180),
              ),
              const SizedBox(height: 28),
              const Text(
                'TBS',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'CONTAINER YARD MANAGEMENT',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Colors.white70,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white.withOpacity(0.9),
                  ),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Loading...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
