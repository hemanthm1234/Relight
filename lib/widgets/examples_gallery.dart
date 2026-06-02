import 'package:flutter/material.dart';

class ExamplesGalleryScreen extends StatefulWidget {
  const ExamplesGalleryScreen({super.key});

  @override
  State<ExamplesGalleryScreen> createState() => _ExamplesGalleryScreenState();
}

class _ExamplesGalleryScreenState extends State<ExamplesGalleryScreen> {
  // Hardcoded paths since they are static assets
  final List<String> _images = [
    'assets/example_relights/example_1.png',
    'assets/example_relights/example_2.png',
    'assets/example_relights/example_3.png',
    'assets/example_relights/example_4.png',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0E), // Match app background
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F13), // Match app bar
        title: const Text(
          'Example Relights',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
        elevation: 0,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        itemCount: _images.length,
        itemBuilder: (context, index) {
          final assetPath = _images[index];
          return _buildGalleryCard(context, assetPath, index);
        },
      ),
    );
  }

  Widget _buildGalleryCard(BuildContext context, String assetPath, int index) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context, 
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => 
                FullScreenGallery(images: _images, initialIndex: index),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          )
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withAlpha(12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'gallery_image_$assetPath',
              child: Image.asset(
                assetPath,
                fit: BoxFit.cover,
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                    stops: [0.6, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 12,
              child: Row(
                children: [
                  const Icon(
                    Icons.image_outlined,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "Example ${index + 1}",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FullScreenGallery extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const FullScreenGallery({
    super.key, 
    required this.images, 
    required this.initialIndex
  });

  @override
  State<FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<FullScreenGallery> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showUI = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleUI() {
    setState(() {
      _showUI = !_showUI;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _showUI ? AppBar(
        backgroundColor: Colors.black.withOpacity(0.4),
        elevation: 0,
        title: Text(
          '${_currentIndex + 1} of ${widget.images.length}', 
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ) : null,
      body: GestureDetector(
        onTap: _toggleUI,
        child: PageView.builder(
          controller: _pageController,
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          itemCount: widget.images.length,
          itemBuilder: (context, index) {
            final assetPath = widget.images[index];
            return InteractiveViewer(
              minScale: 0.8,
              maxScale: 5.0,
              child: Hero(
                tag: 'gallery_image_$assetPath',
                child: Image.asset(
                  assetPath,
                  fit: BoxFit.contain,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
