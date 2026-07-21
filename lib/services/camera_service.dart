import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class CameraService {
  final ImagePicker _picker = ImagePicker();

  /// Open camera and take a picture
  Future<File?> takePicture() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (photo != null) {
        return File(photo.path);
      }
      return null;
    } catch (e) {
      print('[CameraService] Error taking picture: $e');
      return null;
    }
  }

  /// Get local temporary directory for storing images
  Future<Directory> getLocalImageDirectory() async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory imagesDir = Directory('${appDir.path}/container_pics');
    
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    
    return imagesDir;
  }

  /// Save image to local storage
  Future<File?> saveImageLocally(File imageFile, int imageNumber) async {
    try {
      final Directory localDir = await getLocalImageDirectory();
      final String fileName = '$imageNumber.jpg';
      final File savedImage = File('${localDir.path}/$fileName');
      
      // Copy the image to the local directory
      final File copiedImage = await imageFile.copy(savedImage.path);
      print('[CameraService] Image saved locally: ${copiedImage.path}');
      
      return copiedImage;
    } catch (e) {
      print('[CameraService] Error saving image locally: $e');
      return null;
    }
  }

  /// Format date to mm-dd-yyyy format
  String formatDateForServer() {
    return DateFormat('MM-dd-yyyy').format(DateTime.now());
  }

  /// Generate server path for image
  String generateServerPath(String containerNo, String gateStatus, int imageNumber) {
    final String dateFolder = formatDateForServer();
    final String statusFolder = gateStatus.toLowerCase() == 'out' ? 'out' : 'in';
    final String fileName = '$containerNo($imageNumber).jpg';
    return 'container_pics/$dateFolder/$statusFolder/$fileName';
  }
}
