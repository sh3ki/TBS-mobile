import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../config/app_config.dart';

class ImageUploadService {
  final Dio _dio = Dio();

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
  }) async {
    try {
      // Prepare multipart form data
      final Map<String, dynamic> map = {
        'container_no': containerNo,
        'gate_status': gateStatus,
      };
      if (date != null) map['date'] = date;
      if (uploadPath != null) map['upload_path'] = uploadPath;

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
              }
            },
          )
          .timeout(const Duration(seconds: 300)); // 5 minutes timeout

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': 'Images uploaded successfully',
          'data': response.data,
        };
      } else {
        return {
          'success': false,
          'message': 'Upload failed with status ${response.statusCode}',
          'data': null,
        };
      }
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _extractDioErrorMessage(e),
        'data': null,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error uploading images: $e',
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
      // Derive static base (strip '/api' if present)
      final staticBase = AppConfig.baseUrl.replaceFirst(RegExp(r'\/api\/?\z'), '');

      final statusFolder = (gateStatus.toLowerCase() == 'out') ? 'out' : 'in';
      final remoteDir = uploadPath != null && uploadPath.trim().isNotEmpty
          ? uploadPath.trim()
          : 'container_pics/$date/$statusFolder/$containerNo';

      // Local storage path
      final appDir = await getApplicationDocumentsDirectory();
      final localDir = Directory('${appDir.path}/$remoteDir');
      if (!localDir.existsSync()) {
        localDir.createSync(recursive: true);
      }

      final dio = Dio();

      int consecutiveMisses = 0;
      for (int i = 1; i <= maxToCheck; i++) {
        final fileName = '$containerNo($i).jpg';
        final remoteUrl = '$staticBase/$remoteDir/$fileName'.replaceAll('\\', '/');
        try {
          final resp = await dio.get<List<int>>(remoteUrl,
              options: Options(responseType: ResponseType.bytes));
          if (resp.statusCode == 200 && resp.data != null && resp.data!.isNotEmpty) {
            final localPath = p.join(localDir.path, fileName);
            final f = File(localPath);
            await f.writeAsBytes(resp.data!, flush: true);
            downloaded.add(f);
            consecutiveMisses = 0;
          } else {
            consecutiveMisses++;
          }
        } catch (e) {
          consecutiveMisses++;
        }

        if (consecutiveMisses >= 3) break; // stop after 3 consecutive misses
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
      final staticBase = AppConfig.baseUrl.replaceFirst(RegExp(r'\/api\/?\z'), '');
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
