import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../config/app_config.dart';

class UploadStatus {
  final String containerNo;
  final double progress; // 0.0 - 1.0
  final bool completed;
  final bool success;
  final String? message;

  UploadStatus({
    required this.containerNo,
    required this.progress,
    required this.completed,
    required this.success,
    this.message,
  });
}

class ImageUploadService {
  static final ImageUploadService _instance = ImageUploadService._internal();
  factory ImageUploadService() => _instance;

  ImageUploadService._internal() {
  }

  final Dio _dio = Dio();
  final Map<String, bool> _uploading = {};
  final Map<String, double> _progress = {};
  final StreamController<UploadStatus> _uploadController = StreamController<UploadStatus>.broadcast();

  Stream<UploadStatus> get uploadStream => _uploadController.stream;

  // notifications removed to avoid native plugin build issues; use upload stream instead

  /// Upload images to server
  /// Returns a Future that completes when all images are uploaded
  Future<Map<String, dynamic>> uploadContainerPictures({
    required String containerNo,
    required String gateStatus,
    required List<File> images,
    String? date, // formatted as MM-DD-YYYY
    String? uploadPath, // optional explicit upload path on server
    Function(double)? onProgress,
    int? startingIndex,
    String? username,
    int? userId,
  }) async {
    _uploading[containerNo] = true;
    _progress[containerNo] = 0.0;
    _uploadController.add(UploadStatus(containerNo: containerNo, progress: 0.0, completed: false, success: false));
    try {
      // Prepare multipart form data
      final Map<String, dynamic> map = {
        'container_no': containerNo,
        'gate_status': gateStatus,
      };
      if (date != null) map['date'] = date;
      if (uploadPath != null) map['upload_path'] = uploadPath;
      // Include username/userId when available so server can attribute actions
      if (username != null && username.trim().isNotEmpty) map['username'] = username.trim();
      if (userId != null && userId > 0) map['user_id'] = userId;

      FormData formData = FormData.fromMap(map);

      // Add each image
      for (int i = 0; i < images.length; i++) {
        final file = images[i];
        if (await file.exists()) {
          // Use 'pictures[]' so PHP/Laravel treats multiple files as an array
          formData.files.add(
            MapEntry(
              'pictures[]',
              await MultipartFile.fromFile(
                file.path,
                filename: '$containerNo(${(startingIndex ?? 0) + i + 1}).jpg',
              ),
            ),
          );
        }
      }

      // Upload with timeout and progress tracking
      final response = await _dio
          .post(
            '${AppConfig.baseUrl}/mobile/gateinout/upload-pictures',
            data: formData,
            onSendProgress: (sent, total) {
              if (total > 0) {
                onProgress?.call(sent / total);
                _progress[containerNo] = sent / total;
                _uploadController.add(UploadStatus(containerNo: containerNo, progress: _progress[containerNo] ?? 0.0, completed: false, success: false));
              }
            },
          )
          .timeout(const Duration(seconds: 300)); // 5 minutes timeout

      if (response.statusCode == 200) {
          _uploading[containerNo] = false;
          _progress[containerNo] = 1.0;
          _uploadController.add(UploadStatus(containerNo: containerNo, progress: 1.0, completed: true, success: true, message: 'Images uploaded successfully'));
        return {
          'success': true,
          'message': 'Images uploaded successfully',
          'data': response.data,
        };
      } else {
        _uploading[containerNo] = false;
        _uploadController.add(UploadStatus(containerNo: containerNo, progress: _progress[containerNo] ?? 0.0, completed: true, success: false, message: 'Upload failed with status ${response.statusCode}'));
        return {
          'success': false,
          'message': 'Upload failed with status ${response.statusCode}',
          'data': null,
        };
      }
    } on DioException catch (e) {
      _uploading[containerNo] = false;
      final msg = _extractDioErrorMessage(e);
      _uploadController.add(UploadStatus(containerNo: containerNo, progress: _progress[containerNo] ?? 0.0, completed: true, success: false, message: msg));
      return {
        'success': false,
        'message': msg,
        'data': null,
      };
    } catch (e) {
      _uploading[containerNo] = false;
      final msg = 'Error uploading images: $e';
      _uploadController.add(UploadStatus(containerNo: containerNo, progress: _progress[containerNo] ?? 0.0, completed: true, success: false, message: msg));
      return {
        'success': false,
        'message': msg,
        'data': null,
      };
    }
  }

  /// Attempts to fetch existing images for a container from the public container_pics path.
  /// Downloads found images to local app documents under 'container_pics/...'
  /// Returns a list of local File objects for successfully downloaded images.
  Future<List<File>> fetchExistingImages({
    required String containerNo,
    required String gateStatus,
    required String date, // MM-DD-YYYY
    String? uploadPath,
    int maxToCheck = 100,
  }) async {
    final List<File> downloaded = [];
    try {
      // Use the server API to list container pictures for the given date/status
      // Robustly derive public static base (strip trailing '/api' or '/api/')
      String staticBase = AppConfig.baseUrl;
      if (staticBase.endsWith('/api')) {
        staticBase = staticBase.substring(0, staticBase.length - 4);
      } else if (staticBase.endsWith('/api/')) {
        staticBase = staticBase.substring(0, staticBase.length - 5);
      }
      final dio = Dio();

      final apiUrl = '${AppConfig.baseUrl}/mobile/gateinout/container-pictures';
      final params = {
        'container_no': containerNo,
        'gate_status': gateStatus,
        'date': date,
      };
      if (uploadPath != null && uploadPath.trim().isNotEmpty) {
        params['upload_path'] = uploadPath.trim();
      }

      final resp = await dio.get(apiUrl, queryParameters: params);
      print('[ImageUploadService] fetchExistingImages: GET $apiUrl -> status=${resp.statusCode}');
      if (resp.statusCode == 200 && resp.data != null && resp.data['success'] == true) {
        final List items = resp.data['data'] as List? ?? [];
        print('[ImageUploadService] fetchExistingImages: server returned ${items.length} items');

        // Prepare local dir base
        final remoteDir = uploadPath != null && uploadPath.trim().isNotEmpty
            ? uploadPath.trim()
            : 'container_pics/$date/${(gateStatus.toLowerCase() == 'out') ? 'out' : 'in'}/$containerNo';
        final appDir = await getApplicationDocumentsDirectory();
        final localDir = Directory('${appDir.path}/$remoteDir');
        if (!localDir.existsSync()) {
          localDir.createSync(recursive: true);
        }

        for (final item in items) {
          print('[ImageUploadService] fetchExistingImages: item=$item');
          try {
            final name = item['name']?.toString() ?? '';
            final path = item['path']?.toString() ?? '';
            if (name.isEmpty || path.isEmpty) continue;

            final remoteUrl = (staticBase.replaceAll(RegExp(r'\/$'), '')) + '/' + path.replaceAll(RegExp(r'^\/'), '');
            final normalizedRemoteUrl = remoteUrl.replaceAll('\\', '/');
            print('[ImageUploadService] fetchExistingImages: normalized URL = $normalizedRemoteUrl');
            print('[ImageUploadService] fetchExistingImages: downloading $normalizedRemoteUrl');
            final res = await dio.get<List<int>>(normalizedRemoteUrl,
                options: Options(responseType: ResponseType.bytes));
            print('[ImageUploadService] fetchExistingImages: download status=${res.statusCode} size=${res.data?.length ?? 0}');
            if (res.statusCode == 200 && res.data != null && res.data!.isNotEmpty) {
              final localPath = p.join(localDir.path, name);
              final f = File(localPath);
              await f.writeAsBytes(res.data!, flush: true);
              downloaded.add(f);
            }
          } catch (e) {
            // ignore per-file errors and continue
            print('[ImageUploadService] fetchExistingImages: error downloading item: $e');
          }
        }
      }
    } catch (e) {
      // ignore errors and return what we have
    }

    return downloaded;
  }

  /// Probe server to find last existing image index for a container.
  /// Returns 0 if none found, otherwise returns highest existing index.
  Future<int> getLastImageIndex({
    required String containerNo,
    required String gateStatus,
    required String date,
    String? uploadPath,
    int maxToCheck = 200,
  }) async {
    try {
      String staticBase = AppConfig.baseUrl;
      if (staticBase.endsWith('/api')) {
        staticBase = staticBase.substring(0, staticBase.length - 4);
      } else if (staticBase.endsWith('/api/')) {
        staticBase = staticBase.substring(0, staticBase.length - 5);
      }
      final statusFolder = (gateStatus.toLowerCase() == 'out') ? 'out' : 'in';
      final remoteDir = uploadPath != null && uploadPath.trim().isNotEmpty
          ? uploadPath.trim()
          : 'container_pics/$date/$statusFolder/$containerNo';

      final dio = Dio();
      int lastFound = 0;
      int consecutiveMisses = 0;

      for (int i = 1; i <= maxToCheck; i++) {
        final fileName = '$containerNo($i).jpg';
        final remoteUrl = '$staticBase/$remoteDir/$fileName'.replaceAll('\\', '/');
        try {
          final resp = await dio.head(remoteUrl);
          if (resp.statusCode == 200) {
            lastFound = i;
            consecutiveMisses = 0;
          } else {
            consecutiveMisses++;
          }
        } catch (e) {
          consecutiveMisses++;
        }

        if (consecutiveMisses >= 3) break;
      }

      return lastFound;
    } catch (e) {
      return 0;
    }
  }

  /// Background upload - doesn't wait for completion
  void uploadInBackground({
    required String containerNo,
    required String gateStatus,
    required List<File> images,
    String? date,
    String? uploadPath,
  }) {
    // Fire and forget
    uploadContainerPictures(
      containerNo: containerNo,
      gateStatus: gateStatus,
      images: images,
      date: date,
      uploadPath: uploadPath,
    ).then((result) {
      print('[ImageUploadService] Background upload completed: ${result['message']}');
    }).catchError((error) {
      print('[ImageUploadService] Background upload error: $error');
    });
  }

  String _extractDioErrorMessage(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timeout. Please check your internet connection.';
      case DioExceptionType.sendTimeout:
        return 'Send timeout. Please try again.';
      case DioExceptionType.receiveTimeout:
        return 'Receive timeout. Please try again.';
      case DioExceptionType.badResponse:
        return 'Server error: ${error.response?.statusCode}';
      case DioExceptionType.cancel:
        return 'Upload cancelled.';
      default:
        return 'Network error. Please try again.';
    }
  }
}
