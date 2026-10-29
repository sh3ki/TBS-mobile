import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:image_picker/image_picker.dart';

import '../services/image_provider_service.dart';
import 'image_preview_viewer.dart';

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

// Output dimensions are fixed; only the clarity of the result is improved.
const int _kTargetWidth = 640;
const int _kTargetHeight = 480;
const int _kMaxFileBytes = 2 * 1024 * 1024;

/// Short side the native decoder scales to: exactly 2x the 480px output, so
/// the final downscale averages clean 2x2 pixel blocks (sharp, no aliasing).
const int _kDecodeShortSide = _kTargetHeight * 2;

/// Downscales with area averaging (no pixel skipping, which caused the
/// jagged/blurry look) and applies a light sharpen like a phone camera does.
img.Image _resizeSharp(img.Image src, int width, int height) {
  final isDownscale = src.width >= width && src.height >= height;
  final resized = img.copyResize(
    src,
    width: width,
    height: height,
    interpolation:
        isDownscale ? img.Interpolation.average : img.Interpolation.cubic,
  );
  return img.convolution(
    resized,
    filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0],
    amount: 0.35,
  );
}

/// Highest JPEG quality that still fits under the 2MB limit.
Uint8List _encodeUnderLimit(img.Image image) {
  for (final quality in const [100, 98, 95, 92, 90, 85]) {
    final jpg = img.encodeJpg(image, quality: quality);
    if (jpg.length <= _kMaxFileBytes) return jpg;
  }
  return img.encodeJpg(image, quality: 80);
}

/// Crops to 4:3 (matching the on-screen preview), rotates by [rotation] and
/// downscales to exactly 640x480. Cropping happens before rotating so the
/// rotation touches fewer pixels.
Uint8List _finishCapture(img.Image image, int rotation) {
  final swaps = rotation % 180 != 0;
  final cropAspect =
      swaps ? _kTargetHeight / _kTargetWidth : _kTargetWidth / _kTargetHeight;
  final aspect = image.width / image.height;
  if ((aspect - cropAspect).abs() > 0.01) {
    int cropW = image.width;
    int cropH = image.height;
    if (aspect > cropAspect) {
      cropW = (image.height * cropAspect).round();
    } else {
      cropH = (image.width / cropAspect).round();
    }
    image = img.copyCrop(
      image,
      x: (image.width - cropW) ~/ 2,
      y: (image.height - cropH) ~/ 2,
      width: cropW,
      height: cropH,
    );
  }
  if (rotation != 0) image = img.copyRotate(image, angle: rotation);
  return _encodeUnderLimit(_resizeSharp(image, _kTargetWidth, _kTargetHeight));
}

/// Fits an image inside 640x480 with black letterboxing.
Uint8List _finishGallery(img.Image image) {
  const targetAspect = _kTargetWidth / _kTargetHeight;
  final aspect = image.width / image.height;

  int resizedWidth;
  int resizedHeight;
  if (aspect > targetAspect) {
    resizedWidth = _kTargetWidth;
    resizedHeight = (_kTargetWidth / aspect).round().clamp(1, _kTargetHeight);
  } else {
    resizedHeight = _kTargetHeight;
    resizedWidth = (_kTargetHeight * aspect).round().clamp(1, _kTargetWidth);
  }

  final resized = _resizeSharp(image, resizedWidth, resizedHeight);
  final canvas = img.Image(width: _kTargetWidth, height: _kTargetHeight);
  img.fill(canvas, color: img.ColorRgb8(0, 0, 0));
  img.compositeImage(
    canvas,
    resized,
    dstX: (_kTargetWidth - resizedWidth) ~/ 2,
    dstY: (_kTargetHeight - resizedHeight) ~/ 2,
  );
  return _encodeUnderLimit(canvas);
}

/// Fast single pass over raw RGBA bytes: center-crop to 4:3 (or letterbox
/// when [fit] is true), rotate by [rotation] (same pixel mapping as
/// img.copyRotate), area-average down to 640x480 and apply the same light
/// sharpen as [_resizeSharp]. Returns null when the source is smaller than
/// the output so the caller can use the library path for upscaling.
img.Image? _fastResample(
  Uint8List rgba,
  int w,
  int h, {
  int rotation = 0,
  bool fit = false,
}) {
  final r = rotation % 360;
  final swaps = r == 90 || r == 270;
  final rw = swaps ? h : w;
  final rh = swaps ? w : h;

  const targetAspect = _kTargetWidth / _kTargetHeight;
  final aspect = rw / rh;
  int cropX = 0, cropY = 0, cropW = rw, cropH = rh;
  int dstX = 0, dstY = 0, dstW = _kTargetWidth, dstH = _kTargetHeight;
  if (fit) {
    if (aspect > targetAspect) {
      dstH = (_kTargetWidth / aspect).round().clamp(1, _kTargetHeight);
    } else {
      dstW = (_kTargetHeight * aspect).round().clamp(1, _kTargetWidth);
    }
    dstX = (_kTargetWidth - dstW) ~/ 2;
    dstY = (_kTargetHeight - dstH) ~/ 2;
  } else {
    if (aspect > targetAspect) {
      cropW = (rh * targetAspect).round();
    } else {
      cropH = (rw / targetAspect).round();
    }
    cropX = (rw - cropW) ~/ 2;
    cropY = (rh - cropH) ~/ 2;
  }
  if (cropW < dstW || cropH < dstH) return null;

  // Byte offset of rotated-space pixel (rx, ry) = base + rx*stepX + ry*stepY.
  final row = w * 4;
  int base, stepX, stepY;
  switch (r) {
    case 90:
      base = (h - 1) * row;
      stepX = -row;
      stepY = 4;
      break;
    case 180:
      base = (h - 1) * row + (w - 1) * 4;
      stepX = -4;
      stepY = -row;
      break;
    case 270:
      base = (w - 1) * 4;
      stepX = row;
      stepY = -4;
      break;
    default:
      base = 0;
      stepX = 4;
      stepY = row;
  }

  // Area-average every source pixel into its output pixel.
  final avg = Float64List(dstW * dstH * 3);
  final dx = cropW / dstW;
  final dy = cropH / dstH;
  final xs1 = Int32List(dstW);
  final xs2 = Int32List(dstW);
  for (var x = 0; x < dstW; x++) {
    final a1 = (x * dx).toInt();
    var a2 = ((x + 1) * dx).toInt();
    if (a2 == a1) a2++;
    xs1[x] = cropX + a1;
    xs2[x] = cropX + a2;
  }
  var o = 0;
  for (var y = 0; y < dstH; y++) {
    final ay1 = cropY + (y * dy).toInt();
    var ay2 = cropY + ((y + 1) * dy).toInt();
    if (ay2 == ay1) ay2++;
    for (var x = 0; x < dstW; x++) {
      final x1 = xs1[x];
      final x2 = xs2[x];
      var sr = 0, sg = 0, sb = 0;
      for (var ry = ay1; ry < ay2; ry++) {
        var idx = base + ry * stepY + x1 * stepX;
        for (var rx = x1; rx < x2; rx++) {
          sr += rgba[idx];
          sg += rgba[idx + 1];
          sb += rgba[idx + 2];
          idx += stepX;
        }
      }
      final inv = 1.0 / ((ay2 - ay1) * (x2 - x1));
      avg[o++] = sr * inv;
      avg[o++] = sg * inv;
      avg[o++] = sb * inv;
    }
  }

  // Light sharpen: out = c + 0.35 * (4c - up - down - left - right).
  const amount = 0.35;
  final out = Uint8List(_kTargetWidth * _kTargetHeight * 3);
  final rowLen = dstW * 3;
  for (var y = 0; y < dstH; y++) {
    final up = (y > 0 ? y - 1 : y) * rowLen;
    final cur = y * rowLen;
    final down = (y < dstH - 1 ? y + 1 : y) * rowLen;
    var d = ((dstY + y) * _kTargetWidth + dstX) * 3;
    for (var x = 0; x < dstW; x++) {
      final cx = x * 3;
      final lx = (x > 0 ? x - 1 : x) * 3;
      final rx = (x < dstW - 1 ? x + 1 : x) * 3;
      for (var c = 0; c < 3; c++) {
        final center = avg[cur + cx + c];
        final v = center +
            amount *
                (4 * center -
                    avg[up + cx + c] -
                    avg[down + cx + c] -
                    avg[cur + lx + c] -
                    avg[cur + rx + c]);
        out[d++] = v <= 0 ? 0 : (v >= 255 ? 255 : v.round());
      }
    }
  }

  return img.Image.fromBytes(
    width: _kTargetWidth,
    height: _kTargetHeight,
    bytes: out.buffer,
    numChannels: 3,
  );
}

/// Converts raw RGBA pixels into the final JPEG bytes.
Uint8List _finishRgba(
  Uint8List rgba,
  int w,
  int h, {
  required int rotation,
  required bool gallery,
}) {
  final fast = _fastResample(rgba, w, h, rotation: rotation, fit: gallery);
  if (fast != null) return _encodeUnderLimit(fast);

  final image = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return gallery ? _finishGallery(image) : _finishCapture(image, rotation);
}

/// Background isolate: finishes an already natively-decoded RGBA frame.
/// Args: width, height, pixels (TransferableTypedData), dst, rotation, gallery.
void _processRgbaFrame(Map<String, Object> args) {
  final pixels =
      (args['pixels'] as TransferableTypedData).materialize().asUint8List();
  final jpg = _finishRgba(
    pixels,
    args['width'] as int,
    args['height'] as int,
    rotation: args['rotation'] as int,
    gallery: args['gallery'] as bool,
  );
  File(args['dst'] as String).writeAsBytesSync(jpg, flush: true);
}

/// Background isolate fallback: full pure-Dart decode (slower).
/// Args: src, dst, rotation, gallery.
void _processEncodedFile(Map<String, Object> args) {
  final decoded =
      img.decodeImage(File(args['src'] as String).readAsBytesSync());
  if (decoded == null) throw Exception('Could not decode image');
  final image = img.bakeOrientation(decoded).convert(
        format: img.Format.uint8,
        numChannels: 4,
      );
  final jpg = _finishRgba(
    image.getBytes(order: img.ChannelOrder.rgba),
    image.width,
    image.height,
    rotation: args['rotation'] as int,
    gallery: args['gallery'] as bool,
  );
  File(args['dst'] as String).writeAsBytesSync(jpg, flush: true);
}

/// Decodes with the platform's native (hardware-accelerated) JPEG decoder,
/// which also applies EXIF orientation and uses DCT scaling to reach
/// [_kDecodeShortSide] cheaply. Far faster than decoding in Dart.
Future<({int width, int height, Uint8List pixels})> _nativeDecode(
    String path) async {
  final bytes = await File(path).readAsBytes();
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  ui.Codec? codec;
  ui.Image? image;
  try {
    final shortSide = descriptor.width < descriptor.height
        ? descriptor.width
        : descriptor.height;
    int? targetWidth;
    if (shortSide > _kDecodeShortSide) {
      targetWidth = (descriptor.width * _kDecodeShortSide / shortSide).round();
    }
    codec = await descriptor.instantiateCodec(targetWidth: targetWidth);
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw Exception('Could not read decoded pixels');
    return (
      width: image.width,
      height: image.height,
      pixels: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}

/// Converts [srcPath] into a 640x480 JPEG at [dstPath]. Tries the fast native
/// path first and falls back to the pure-Dart decoder if that fails.
Future<void> _convertImage({
  required String srcPath,
  required String dstPath,
  int rotation = 0,
  bool gallery = false,
}) async {
  try {
    final frame = await _nativeDecode(srcPath);
    await compute(_processRgbaFrame, <String, Object>{
      'width': frame.width,
      'height': frame.height,
      'pixels': TransferableTypedData.fromList([frame.pixels]),
      'dst': dstPath,
      'rotation': rotation,
      'gallery': gallery,
    });
  } catch (e) {
    print('DEBUG: Native decode failed, using fallback: $e');
    await compute(_processEncodedFile, <String, Object>{
      'src': srcPath,
      'dst': dstPath,
      'rotation': rotation,
      'gallery': gallery,
    });
  }
}

class _ContinuousCameraScreenState extends State<ContinuousCameraScreen> {
  final _imageProvider = ImageProviderService();
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  int? _tiltRotationAngle;
  FlashMode _flashMode = FlashMode.off;

  bool _isTakingPhoto = false;
  bool _isInitializingCamera = true;
  bool _isPreviewExpanded = true;
  String? _cameraError;

  // Captured photos are converted one after another in the background so
  // the shutter is never blocked by image processing.
  Future<void> _processingQueue = Future.value();
  int _pendingCount = 0;
  bool _isLeaving = false;

  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;
  bool _showZoomLabel = false;
  Timer? _zoomLabelTimer;
  Offset? _focusIndicator;
  Timer? _focusIndicatorTimer;

  @override
  void initState() {
    super.initState();
    _lockToPortrait();
    _startOrientationTracking();
    // Set provider's current container if provided so images are cached per container
    if (widget.containerNo != null && widget.containerNo!.trim().isNotEmpty) {
      _imageProvider.setCurrentContainer(widget.containerNo!);
    }
    _imageProvider.addListener(_handleImageProviderChanged);
    _initializeCamera();
  }

  void _handleImageProviderChanged() {
    if (mounted) setState(() {});
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

      // 1080p capture: 2.25x more detail than the 640x480 output (crisp after
      // downscaling) while keeping shutter latency and decoding fast.
      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );
      _initializeControllerFuture = _cameraController!.initialize();
      await _initializeControllerFuture;

      // Apply initial flash mode after initialization
      try {
        await _cameraController!.setFlashMode(_flashMode);
      } catch (e) {
        // Some devices may not support certain flash modes
        print('DEBUG: Unable to set flash mode: $e');
      }

      try {
        await _cameraController!.setFocusMode(FocusMode.auto);
        await _cameraController!.setExposureMode(ExposureMode.auto);
      } catch (e) {
        print('DEBUG: Unable to set focus/exposure mode: $e');
      }

      try {
        _minZoom = await _cameraController!.getMinZoomLevel();
        _maxZoom = await _cameraController!.getMaxZoomLevel();
        _currentZoom = 1.0.clamp(_minZoom, _maxZoom).toDouble();
        await _cameraController!.setZoomLevel(_currentZoom);
      } catch (e) {
        print('DEBUG: Zoom not supported: $e');
        _minZoom = 1.0;
        _maxZoom = 1.0;
        _currentZoom = 1.0;
      }

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

  Future<void> _applyFlashMode() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized)
      return;
    try {
      await _cameraController!.setFlashMode(_flashMode);
    } catch (e) {
      print('DEBUG: Error applying flash mode: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Flash mode not supported on this device')),
        );
      }
    }
  }

  void _cycleFlashMode() {
    setState(() {
      if (_flashMode == FlashMode.off) {
        _flashMode = FlashMode.torch; // continuous light
      } else if (_flashMode == FlashMode.torch) {
        _flashMode = FlashMode.auto;
      } else {
        _flashMode = FlashMode.off;
      }
    });
    _applyFlashMode();
  }

  Future<void> _setZoom(double zoom) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    final clamped = zoom.clamp(_minZoom, _maxZoom).toDouble();
    if ((clamped - _currentZoom).abs() < 0.01) return;

    _zoomLabelTimer?.cancel();
    setState(() {
      _currentZoom = clamped;
      _showZoomLabel = true;
    });
    _zoomLabelTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _showZoomLabel = false);
    });

    try {
      await controller.setZoomLevel(clamped);
    } catch (e) {
      print('DEBUG: Error setting zoom: $e');
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) return;
    _setZoom(_baseZoom * details.scale);
  }

  /// Tap-to-focus: [localPosition] is relative to the visible preview box of
  /// [boxSize]; it is mapped back onto the full (cover-cropped) preview.
  Future<void> _onPreviewTap(Offset localPosition, Size boxSize) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return;

    // Preview is shown rotated to portrait: width/height are swapped.
    final childW = previewSize.height;
    final childH = previewSize.width;
    final scale = (boxSize.width / childW) > (boxSize.height / childH)
        ? boxSize.width / childW
        : boxSize.height / childH;
    final displayW = childW * scale;
    final displayH = childH * scale;
    final dx = (localPosition.dx + (displayW - boxSize.width) / 2) / displayW;
    final dy = (localPosition.dy + (displayH - boxSize.height) / 2) / displayH;
    final point = Offset(dx.clamp(0.0, 1.0), dy.clamp(0.0, 1.0));

    _focusIndicatorTimer?.cancel();
    setState(() => _focusIndicator = localPosition);
    _focusIndicatorTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _focusIndicator = null);
    });

    try {
      if (controller.value.focusPointSupported) {
        await controller.setFocusPoint(point);
      }
      if (controller.value.exposurePointSupported) {
        await controller.setExposurePoint(point);
      }
    } catch (e) {
      print('DEBUG: Error setting focus point: $e');
    }
  }

  List<double> _zoomPresets() {
    final presets = <double>[];
    if (_minZoom < 0.95) presets.add(_minZoom);
    for (final z in const [1.0, 2.0, 5.0, 10.0]) {
      if (z >= _minZoom && z <= _maxZoom) presets.add(z);
    }
    return presets;
  }

  String _formatZoom(double zoom) {
    final rounded = (zoom * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? '${rounded.toInt()}x'
        : '${rounded.toStringAsFixed(1)}x';
  }

  Widget _buildCameraPreview() {
    final controller = _cameraController!;
    return Center(
      child: AspectRatio(
        // Keep camera area strictly portrait 3:4.
        aspectRatio: 3 / 4,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final boxSize = Size(constraints.maxWidth, constraints.maxHeight);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onTapUp: (details) =>
                  _onPreviewTap(details.localPosition, boxSize),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Colors.black,
                    child: ClipRect(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: controller.value.previewSize!.height,
                          height: controller.value.previewSize!.width,
                          child: CameraPreview(controller),
                        ),
                      ),
                    ),
                  ),
                  if (_focusIndicator != null)
                    Positioned(
                      left: _focusIndicator!.dx - 35,
                      top: _focusIndicator!.dy - 35,
                      child: IgnorePointer(
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.yellow, width: 2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  if (_showZoomLabel)
                    Center(
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _formatZoom(_currentZoom),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildZoomControls() {
    if (_cameraController == null ||
        _cameraError != null ||
        _isInitializingCamera ||
        _maxZoom <= _minZoom) {
      return const SizedBox.shrink();
    }

    final presets = _zoomPresets();
    // Highlight the closest preset that is at or below the current zoom.
    double? active;
    for (final z in presets) {
      if (_currentZoom + 0.05 >= z) active = z;
    }

    return Positioned(
      bottom: 112,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: presets.map((z) {
              final isActive = z == active;
              final label =
                  isActive ? _formatZoom(_currentZoom) : _formatZoom(z);
              return GestureDetector(
                onTap: () => _setZoom(z),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 44,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: isActive ? Colors.white24 : Colors.transparent,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isActive ? Colors.yellow : Colors.white,
                      fontSize: isActive ? 13 : 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _startOrientationTracking() {
    _accelerometerSubscription =
        accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
            .listen((event) {
      final x = event.x;
      final y = event.y;

      // When x dominates, the phone is physically landscape.
      // x < 0 => left tilt (90), x > 0 => right tilt (-90).
      int? nextAngle;
      if (x.abs() > y.abs() && x.abs() > 6) {
        nextAngle = x < 0 ? 90 : -90;
      }

      if (nextAngle != _tiltRotationAngle && mounted) {
        setState(() {
          _tiltRotationAngle = nextAngle;
        });
      }
    });
  }

  Widget _buildRotationIndicator() {
    final isLeft = _tiltRotationAngle == 90;
    final isRight = _tiltRotationAngle == -90;
    final label = isLeft
        ? 'Rotate: LEFT'
        : isRight
            ? 'Rotate: RIGHT'
            : 'Rotate: DEFAULT';

    return Positioned(
      top: 12,
      right: 12,
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
            Icon(
              isLeft
                  ? Icons.rotate_left
                  : isRight
                      ? Icons.rotate_right
                      : Icons.screen_rotation_alt,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<Directory> _photosDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${appDir.path}/captured_images');
    if (!photosDir.existsSync()) {
      photosDir.createSync(recursive: true);
    }
    return photosDir;
  }

  Future<String> _newPhotoPath(String prefix) async {
    final photosDir = await _photosDir();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '${photosDir.path}/${prefix}_$timestamp.jpg';
  }

  /// Adds a conversion job to the background queue. Jobs run in order so the
  /// photos appear in the same order they were taken.
  void _enqueue(Future<File?> Function() job) {
    setState(() => _pendingCount++);
    _processingQueue = _processingQueue.then((_) async {
      try {
        final file = await job();
        if (file != null) _imageProvider.addImage(file);
      } catch (e) {
        print('DEBUG: Error processing image: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving photo: $e')),
          );
        }
      } finally {
        _pendingCount--;
        if (mounted) setState(() {});
      }
    });
  }

  void _enqueueCapture(String capturedPath, int rotationAngle) {
    _enqueue(() async {
      final savedPath = await _newPhotoPath('IMG');
      try {
        await _convertImage(
          srcPath: capturedPath,
          dstPath: savedPath,
          rotation: rotationAngle,
        );
      } catch (e) {
        // If processing fails, keep an untouched copy of the original
        print('DEBUG: Error processing captured image: $e');
        return File(capturedPath).copy(savedPath);
      }
      // Remove the full-size temporary capture to save storage.
      try {
        await File(capturedPath).delete();
      } catch (_) {}
      return File(savedPath);
    });
  }

  void _enqueueGalleryImage(String srcPath) {
    _enqueue(() async {
      final savedPath = await _newPhotoPath('UPLOADED');
      try {
        await _convertImage(
            srcPath: srcPath, dstPath: savedPath, gallery: true);
        return File(savedPath);
      } catch (e) {
        print('DEBUG: Error resizing gallery image: $e');
        // Return original file if resizing fails
        return File(srcPath);
      }
    });
  }

  int get _maxTakenImages {
    final remaining = widget.maxImages - _imageProvider.uploadedImages.length;
    return remaining < 0 ? 0 : remaining;
  }

  int get _totalCount => _imageProvider.count + _pendingCount;

  Future<void> _uploadImagesFromGallery() async {
    try {
      final picker = ImagePicker();
      final List<XFile> pickedFiles = await picker.pickMultiImage();

      if (pickedFiles.isEmpty) {
        return;
      }

      // Check if adding these images would exceed max
      if (_totalCount + pickedFiles.length > _maxTakenImages) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Can only add ${_maxTakenImages - _totalCount} more images',
              ),
            ),
          );
        }
        return;
      }

      for (final pickedFile in pickedFiles) {
        _enqueueGalleryImage(pickedFile.path);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${pickedFiles.length} image(s) added to preview',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading images: $e')),
        );
      }
    }
  }

  Future<void> _takePicture() async {
    if (_isTakingPhoto ||
        _isLeaving ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _totalCount >= _maxTakenImages) {
      if (_totalCount >= _maxTakenImages && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Maximum $_maxTakenImages pictures can be taken')),
        );
      }
      return;
    }

    setState(() => _isTakingPhoto = true);
    final spinnerStart = DateTime.now();

    try {
      await _initializeControllerFuture;
      // Read the tilt at the moment the shutter is pressed.
      final deviceOrientation = _cameraController!.value.deviceOrientation;
      final fallbackRotation =
          deviceOrientation == DeviceOrientation.landscapeLeft ? 90 : -90;
      final rotationAngle = _tiltRotationAngle ?? fallbackRotation;

      final XFile picture = await _cameraController!.takePicture();
      HapticFeedback.lightImpact();

      // Shutter is released immediately; conversion happens in the background.
      _enqueueCapture(picture.path, rotationAngle);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error taking photo: $e')),
        );
      }
    } finally {
      // Keep the capture spinner visible for at least 0.5s.
      final remaining = const Duration(milliseconds: 500) -
          DateTime.now().difference(spinnerStart);
      if (remaining > Duration.zero) await Future.delayed(remaining);
      if (mounted) setState(() => _isTakingPhoto = false);
    }
  }

  /// Waits for photos still being saved so none are lost, then closes.
  Future<void> _backToProcess() async {
    if (_isLeaving) return;
    setState(() => _isLeaving = true);
    await _processingQueue;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _zoomLabelTimer?.cancel();
    _focusIndicatorTimer?.cancel();
    _unlockOrientations();
    _cameraController?.dispose();
    _imageProvider.removeListener(_handleImageProviderChanged);
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Preview (${_imageProvider.count})',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (_imageProvider.count > 0)
                TextButton.icon(
                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                  label: const Text('Clear All',
                      style: TextStyle(color: Colors.red)),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear all images?'),
                        content: const Text(
                            'This will remove all images from the preview. Continue?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Clear',
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      _imageProvider.clearAll();
                      if (mounted) setState(() {});
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 4 / 3,
            ),
            itemCount: _imageProvider.images.length,
            itemBuilder: (context, index) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => _openImagePreview(index),
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
      bottom: 156,
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

  Future<void> _openImagePreview(int initialIndex) async {
    final images = List<File>.from(_imageProvider.images);
    if (images.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImagePreviewViewer(
          images: images,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewPanelHeight = 360.0;

    return PopScope(
      // Hold the back gesture until queued photos are saved.
      canPop: _pendingCount == 0 && !_isLeaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToProcess();
      },
      child: Scaffold(
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
              padding: const EdgeInsets.all(12),
              child: Center(
                child: GestureDetector(
                  onTap: _cycleFlashMode,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _flashMode == FlashMode.off
                              ? Icons.flash_off
                              : _flashMode == FlashMode.torch
                                  ? Icons.flash_on
                                  : Icons.flash_auto,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _flashMode == FlashMode.off
                              ? 'Flash Off'
                              : _flashMode == FlashMode.torch
                                  ? 'Flash On'
                                  : 'Auto',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_pendingCount > 0) ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        '$_totalCount/$_maxTakenImages',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
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
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
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
                        : _buildCameraPreview(),
              ),
              _buildPreviewToggleHandle(),
              _buildRotationIndicator(),
              _buildZoomControls(),
              _buildPreviewPopup(height: previewPanelHeight),
              // Centered capture button
              Positioned(
                bottom: 18,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: (_isTakingPhoto || _isLeaving) ? null : _takePicture,
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
                          color: _isTakingPhoto
                              ? Colors.grey
                              : Colors.red.shade400,
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

              // Upload button on the left
              Positioned(
                bottom: 24,
                left: 18,
                child: GestureDetector(
                  onTap: _isLeaving ? null : _uploadImagesFromGallery,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.image,
                          color: Colors.white,
                          size: 18,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Upload',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 'Done' button anchored to the right edge
              Positioned(
                bottom: 24,
                right: 18,
                child: GestureDetector(
                  onTap: _backToProcess,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: _isLeaving && _pendingCount > 0
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Saving',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          )
                        : const Text(
                            'Done',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
