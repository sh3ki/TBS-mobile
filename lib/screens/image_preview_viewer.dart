import 'dart:io';

import 'package:flutter/material.dart';

class ImagePreviewViewer extends StatefulWidget {
  final List<File> images;
  final int initialIndex;

  const ImagePreviewViewer({required this.images, this.initialIndex = 0, Key? key}) : super(key: key);

  @override
  State<ImagePreviewViewer> createState() => _ImagePreviewViewerState();
}

class _ImagePreviewViewerState extends State<ImagePreviewViewer> {
  late PageController _mainController;
  late PageController _thumbController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.images.length - 1);
    _mainController = PageController(initialPage: _currentIndex);
    _thumbController = PageController(viewportFraction: 0.24, initialPage: _currentIndex);
    _mainController.addListener(_syncFromMain);
  }

  void _syncFromMain() {
    final page = _mainController.page?.round() ?? _currentIndex;
    if (page != _currentIndex) {
      setState(() => _currentIndex = page);
      _thumbController.animateToPage(page, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _mainController.removeListener(_syncFromMain);
    _mainController.dispose();
    _thumbController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: PageView.builder(
                  controller: _mainController,
                  itemCount: widget.images.length,
                  onPageChanged: (i) {
                    setState(() => _currentIndex = i);
                    _thumbController.animateToPage(i, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                  },
                  itemBuilder: (context, index) {
                    return InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 5.0,
                      child: Center(
                        child: Image.file(
                          widget.images[index],
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          SizedBox(
            height: 100,
            child: PageView.builder(
              controller: _thumbController,
              itemCount: widget.images.length,
              onPageChanged: (i) {
                if (i != _currentIndex) {
                  _mainController.animateToPage(i, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                }
              },
              itemBuilder: (context, index) {
                final isActive = index == _currentIndex;
                return GestureDetector(
                  onTap: () {
                    _mainController.animateToPage(index, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: isActive ? Colors.white : Colors.white24, width: isActive ? 2 : 1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(
                            widget.images[index],
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
