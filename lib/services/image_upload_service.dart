import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import '../config/app_config.dart';

class ImageUploadService {
  final Dio _dio = Dio();

  /// Upload images to server
  /// Returns a Future that completes when all images are uploaded
  Future<Map<String, dynamic>> uploadContainerPictures({
    required String containerNo,
    required String gateStatus,
    required List<File> images,
    Function(double)? onProgress,
  }) async {
    try {
      // Prepare multipart form data
      FormData formData = FormData.fromMap({
        'container_no': containerNo,
        'gate_status': gateStatus,
      });

      // Add each image
      for (int i = 0; i < images.length; i++) {
        final file = images[i];
        if (await file.exists()) {
          formData.files.add(
            MapEntry(
              'pictures',
              await MultipartFile.fromFile(
                file.path,
                filename: '$containerNo(${i + 1}).jpg',
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

  /// Background upload - doesn't wait for completion
  void uploadInBackground({
    required String containerNo,
    required String gateStatus,
    required List<File> images,
  }) {
    // Fire and forget
    uploadContainerPictures(
      containerNo: containerNo,
      gateStatus: gateStatus,
      images: images,
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
