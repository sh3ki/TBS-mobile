import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

import '../services/image_provider_service.dart';

class ContinuousCameraScreen extends StatefulWidget {
  final int maxImages;
  final String? containerNo;

  const ContinuousCameraScreen({
    super.key,
    this.maxImages = 100,
    this.containerNo,
  });

  @override
  State<ContinuousCameraScreen> createState() => _ContinuousCameraScreenState();
}

class _ContinuousCameraScreenState extends State<ContinuousCameraScreen> {
  final _imageProvider = ImageProviderService();
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;

  bool _isTakingPhoto = false;
  bool _isInitializingCamera = true;
  bool _isPreviewExpanded = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    _lockToPortrait();
    // Set provider's current container if provided so images are cached per container
    if (widget.containerNo != null && widget.containerNo!.trim().isNotEmpty) {
      _imageProvider.setCurrentContainer(widget.containerNo!);
    }
    _initializeCamera();
  }

  Future<void> _lockToPortrait() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  Future<void> _unlockOrientations() async {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No camera found on this device');
      }

      CameraDescription selectedCamera = cameras.first;
      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.back) {
          selectedCamera = camera;
          break;
        }
      }

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _initializeControllerFuture = _cameraController!.initialize();
      await _initializeControllerFuture;

      if (!mounted) return;
      setState(() {
        _isInitializingCamera = false;
        _cameraError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitializingCamera = false;
        _cameraError = e.toString();
      });
    }
  }

  Future<File> _saveToLocalStorage(File capturedFile) async {
    final appDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${appDir.path}/captured_images');
    if (!photosDir.existsSync()) {
      photosDir.createSync(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final savedPath = '${photosDir.path}/IMG_$timestamp.jpg';
    final File copied = await capturedFile.copy(savedPath);

    try {
      // Read bytes and resize to 640x480
      final bytes = await copied.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        final resized = img.copyResize(decoded, width: 640, height: 480);
        final jpg = img.encodeJpg(resized, quality: 85);
        await copied.writeAsBytes(jpg, flush: true);
      }
    } catch (e) {
      // If resizing fails, keep original copied file
      print('DEBUG: Error resizing image: $e');
    }

    return copied;
  }

  Future<void> _takePicture() async {
    if (_isTakingPhoto ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _imageProvider.count >= widget.maxImages) {
      if (_imageProvider.count >= widget.maxImages && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maximum 100 pictures reached')),
        );
      }
      return;
    }

    setState(() => _isTakingPhoto = true);

    try {
      await _initializeControllerFuture;
      final XFile picture = await _cameraController!.takePicture();
      final File savedFile = await _saveToLocalStorage(File(picture.path));

      if (!mounted) return;
      _imageProvider.addImage(savedFile);
      setState(() => _isTakingPhoto = false);
    } catch (e) {
      setState(() => _isTakingPhoto = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error taking photo: $e')),
        );
      }
    }
  }

  void _backToProcess() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _unlockOrientations();
    _cameraController?.dispose();
    super.dispose();
  }

  Widget _buildGalleryPanel() {
    if (_imageProvider.images.isEmpty) {
      return Center(
        child: Text(
          'Photos will appear here',
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 14,
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Preview (${_imageProvider.count})',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 3 / 4,
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
                      onTap: () {
                        _imageProvider.removeImage(index);
                        setState(() {});
                      },
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
      ],
    );
  }

  Widget _buildPreviewToggleHandle() {
    final icon = _isPreviewExpanded
        ? Icons.keyboard_arrow_up
        : Icons.keyboard_arrow_down;

    return Positioned(
      top: 12,
      left: 12,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isPreviewExpanded = !_isPreviewExpanded;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 4),
              const Text(
                'Preview',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewPopup({required double height}) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      left: 12,
      right: 12,
      bottom: 132,
      height: _isPreviewExpanded ? height : 0,
      child: IgnorePointer(
        ignoring: !_isPreviewExpanded,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.78),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _buildGalleryPanel(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewPanelHeight = 360.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera'),
        elevation: 0,
        backgroundColor: Colors.black,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: InkWell(
              onTap: _backToProcess,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                child: Text(
                  '${_imageProvider.count}/${widget.maxImages}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Container(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: 100,
              child: _isInitializingCamera
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : _cameraError != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'Camera error: $_cameraError',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : Center(
                          child: AspectRatio(
                            // Keep camera area strictly portrait 3:4.
                            aspectRatio: 3 / 4,
                            child: ColoredBox(
                              color: Colors.black,
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _cameraController!
                                      .value.previewSize!.height,
                                  height: _cameraController!
                                      .value.previewSize!.width,
                                  child: CameraPreview(_cameraController!),
                                ),
                              ),
                            ),
                          ),
                        ),
            ),
            _buildPreviewToggleHandle(),
            _buildPreviewPopup(height: previewPanelHeight),
            Positioned(
              bottom: 18,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _isTakingPhoto ? null : _takePicture,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 4,
                      ),
                    ),
                    child: Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            _isTakingPhoto ? Colors.grey : Colors.red.shade400,
                      ),
                      child: _isTakingPhoto
                          ? const Center(
                              child: SizedBox(
                                width: 40,
                                height: 40,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 40,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
