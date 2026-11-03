import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'api_service.dart';

class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String apkUrl;
  final bool updateEnabled;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.apkUrl,
    required this.updateEnabled,
  });

  bool get shouldUpdate =>
      currentVersion.isNotEmpty &&
      updateEnabled &&
      apkUrl.isNotEmpty &&
      _compareVersions(latestVersion, currentVersion) > 0;

  static int _compareVersions(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    final length = leftParts.length > rightParts.length ? leftParts.length : rightParts.length;

    for (var index = 0; index < length; index++) {
      final leftPart = index < leftParts.length ? leftParts[index] : 0;
      final rightPart = index < rightParts.length ? rightParts[index] : 0;
      if (leftPart != rightPart) {
        return leftPart.compareTo(rightPart);
      }
    }

    return 0;
  }

  static List<int> _versionParts(String version) {
    final versionName = version.split('+').first.trim();
    return versionName
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
  }
}

class AppUpdateService {
  static AppUpdateInfo? deferredUpdate;

  static const _installerChannel = MethodChannel(
    'com.tbs.mobile.tbs_mobile/apk_installer',
  );

  static void deferUpdate(AppUpdateInfo updateInfo) {
    deferredUpdate = updateInfo;
  }

  static Future<String> getInstalledVersion() async {
    if (!Platform.isAndroid) {
      return '';
    }

    try {
      return await _installerChannel.invokeMethod<String>('getAppVersion') ?? '';
    } catch (error) {
      print('[AppUpdateService] Failed to read installed app version: $error');
      return '';
    }
  }

  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final currentVersion = await getInstalledVersion();
      final response = await ApiService.get('/mobile/app-update');
      if (!response.isSuccessCode || response.data['success'] != true) {
        return null;
      }

      return AppUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: response.data['app_version']?.toString() ?? '',
        apkUrl: response.data['apk_url']?.toString() ?? '',
        updateEnabled: response.data['update_app_modal'] == true,
      );
    } catch (error) {
      // An update check must never prevent the app from opening offline.
      print('[AppUpdateService] Update check failed: $error');
      return null;
    }
  }

  Future<void> downloadAndInstall(
    String apkUrl, {
    void Function(int received, int total)? onProgress,
  }) async {
    final directory = await getApplicationSupportDirectory();
    final apkFile = File('${directory.path}/tbs_mobile_update.apk');

    if (await apkFile.exists()) {
      await apkFile.delete();
    }

    await Dio().download(
      apkUrl,
      apkFile.path,
      onReceiveProgress: onProgress,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        validateStatus: (status) => status != null && status >= 200 && status < 400,
      ),
    );

    if (!await apkFile.exists() || await apkFile.length() == 0) {
      throw Exception('The downloaded APK is empty.');
    }

    if (!Platform.isAndroid) {
      throw UnsupportedError('APK installation is supported on Android only.');
    }

    await _installerChannel.invokeMethod<void>('installApk', {
      'path': apkFile.path,
    });
  }
}
