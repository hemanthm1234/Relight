// ============================================================================
// File: lib/main.dart
// Purpose: Main entry point and orchestration layer of the 3D Relighting app.
// 
// Responsibility:
// - Boots the Flutter application, restricts orientation, and hooks up the global `LightingState` notifier.
// - Builds the workspace interface (`RelighterWorkspace`), which coordinates asset pipelines for pre-baked caches (kUseCachedSample) or real-time ML-driven inference.
// - Integrates the model selection interface for choosing depth estimators (Depth-Anything-V2/V3) and exports compiled texture maps for workspace caches.
// - Coordinates high-resolution image baking, coordinate scaling, and secure export/download dialogs via the local file system.
// ============================================================================

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'models/lighting_state.dart';
import 'services/depth_inference_service.dart';
import 'services/image_processing_service.dart';
import 'widgets/control_panel.dart';
import 'widgets/relight_canvas.dart';
import 'widgets/map_selector.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DEVELOPER TOGGLE
// Set to TRUE once you have pulled the exported PNGs from the device and placed
// them in assets/cache/  (sample_albedo.png, sample_original.png, sample_depth.png)
// The sample image button will then skip the full inference pipeline entirely.
// ─────────────────────────────────────────────────────────────────────────────
const bool kUseCachedSample = true;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Constrain display system orientations exclusively
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(
    ChangeNotifierProvider(
      create: (_) => LightingState(),
      child: const PBRRelighterApp(),
    ),
  );
}

class PBRRelighterApp extends StatelessWidget {
  const PBRRelighterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '🌟 Relight',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C0C0E), // Premium dark background
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F0F13), // Title bar background
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: Colors.white,
          ),
          iconTheme: IconThemeData(color: Colors.white70),
        ),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const RelighterWorkspace(),
    );
  }
}

class RelighterWorkspace extends StatefulWidget {
  const RelighterWorkspace({super.key});

  @override
  State<RelighterWorkspace> createState() => _RelighterWorkspaceState();
}

class _RelighterWorkspaceState extends State<RelighterWorkspace> {
  final DepthInferenceService _inferenceService = DepthInferenceService();
  final ImageProcessingService _imageService = ImageProcessingService();
  final ImagePicker _picker = ImagePicker();
  final GlobalKey _canvasKey = GlobalKey();
  
  bool _isLoading = false;
  String _statusMessage = "Initializing Graphics Shaders...";
  
  ui.FragmentShader? _shader;
  ui.Image? _albedoTex;
  ui.Image? _originalTex;
  ui.Image? _depthTex;

  @override
  void initState() {
    super.initState();
    _bootAppEngines();
  }

  Future<void> _bootAppEngines() async {
    setState(() => _isLoading = true);
    try {
      // Load and compile graphics program runtime shaders
      final program = await ui.FragmentProgram.fromAsset('assets/shaders/pbr_relight.frag');
      _shader = program.fragmentShader();

      setState(() {
        _isLoading = false;
        if (kUseCachedSample) {
          _statusMessage = "Ready to imagine a new world!!";
        } else {
          _statusMessage = "Ready. Select sample or upload an image.";
        }
      });
    } catch (e) {
      setState(() => _statusMessage = "Initialization Failure: $e");
    }
  }

  // ── PHASE 2 ──────────────────────────────────────────────────────────────
  // Load the pre-baked maps from bundle assets (instant, no inference).
  Future<void> _loadCachedSampleMaps(String imageName) async {
    final String baseName = imageName.split('.').first;
    setState(() {
      _isLoading = true;
      _statusMessage = "Loading cached maps for $imageName...";
    });
    try {
      final albedoBytes   = (await rootBundle.load('assets/cache/${baseName}_albedo.png')).buffer.asUint8List();
      final originalBytes = (await rootBundle.load('assets/cache/${baseName}_original.png')).buffer.asUint8List();
      final depthBytes    = (await rootBundle.load('assets/cache/${baseName}_depth.png')).buffer.asUint8List();

      final List<ui.Image> handles = await Future.wait([
        ImageProcessingService.bytesToUiImage(albedoBytes),
        ImageProcessingService.bytesToUiImage(originalBytes),
        ImageProcessingService.bytesToUiImage(depthBytes),
      ]);

      setState(() {
        _albedoTex?.dispose();
        _originalTex?.dispose();
        _depthTex?.dispose();
        
        _albedoTex   = handles[0];
        _originalTex = handles[1];
        _depthTex    = handles[2];
        _isLoading   = false;
      });
    } catch (e) {
      debugPrint("Cache load failed: $e. Falling back to dynamic pipeline.");
      setState(() => _isLoading = false);
      // Run dynamic pipeline instead
      final selectedModel = await _showModelSelectionSheet();
      if (selectedModel != null) {
        await _runDynamicPipelineForAsset(imageName, selectedModel);
      }
    }
  }

  Future<void> _runDynamicPipelineForAsset(String imageName, String selectedModel) async {
    setState(() {
      _isLoading = true;
      _statusMessage = "Preparing $imageName...";
    });
    try {
      final ByteData assetRawData = await rootBundle.load('assets/images/$imageName');
      final Uint8List imgBytes = assetRawData.buffer.asUint8List();
      final tempFile = File('${Directory.systemTemp.path}/ingest_cache_$imageName');
      await tempFile.writeAsBytes(imgBytes);

      await _executeInferenceOn(tempFile, selectedModel, isSampleImage: true, sampleImageName: imageName);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = "Preparing asset failed: $e";
      });
    }
  }

  // ── PHASE 1 ──────────────────────────────────────────────────────────────
  // Export the three generated maps to /storage/emulated/0/Download/
  // Run once, pull with adb, place in assets/cache/, then flip kUseCachedSample.
  Future<void> _exportSampleMaps(String imageName, Map<String, dynamic> texturePack) async {
    try {
      // Works on Android ≤9 via WRITE_EXTERNAL_STORAGE permission.
      // On Android 10+ the public Downloads folder is still accessible
      // without needing MediaStore for simple file writes in debug/release mode.
      const String downloadsPath = '/storage/emulated/0/Download';
      final dir = Directory(downloadsPath);
      if (!await dir.exists()) {
        // Fallback: use app-specific external files dir (always accessible)
        final extDir = await getExternalStorageDirectory();
        if (extDir == null) throw Exception("Cannot resolve external storage.");
        await _writeMapFiles(extDir.path, imageName, texturePack);
      } else {
        await _writeMapFiles(downloadsPath, imageName, texturePack);
      }
    } catch (e) {
      debugPrint("[Cache Export] Failed: $e");
    }
  }

  Future<void> _writeMapFiles(String dirPath, String imageName, Map<String, dynamic> texturePack) async {
    final String baseName = imageName.split('.').first;
    final albedo   = File('$dirPath/${baseName}_albedo.png');
    final original = File('$dirPath/${baseName}_original.png');
    final depth    = File('$dirPath/${baseName}_depth.png');

    int w = texturePack['width'];
    int h = texturePack['height'];

    final albedoImg = img.Image.fromBytes(width: w, height: h, bytes: texturePack['albedo']!.buffer, numChannels: 4);
    final origImg = img.Image.fromBytes(width: w, height: h, bytes: texturePack['original']!.buffer, numChannels: 4);
    final depthImg = img.Image.fromBytes(width: w, height: h, bytes: texturePack['depth']!.buffer, numChannels: 4);

    await albedo.writeAsBytes(img.encodePng(albedoImg));
    await original.writeAsBytes(img.encodePng(origImg));
    await depth.writeAsBytes(img.encodePng(depthImg));

    debugPrint('[Cache Export] ✅ ${baseName}_albedo.png   -> ${albedo.path}');
    debugPrint('[Cache Export] ✅ ${baseName}_original.png -> ${original.path}');
    debugPrint('[Cache Export] ✅ ${baseName}_depth.png    -> ${depth.path}');
    debugPrint('[Cache Export] Run: adb pull ${albedo.path}');
    debugPrint('[Cache Export] Run: adb pull ${original.path}');
    debugPrint('[Cache Export] Run: adb pull ${depth.path}');
    debugPrint('[Cache Export] Then move them to assets/cache/ and set kUseCachedSample = true');
  }

  Future<String?> _showModelSelectionSheet() async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF161622),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28.0),
              topRight: Radius.circular(28.0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 20.0,
                offset: Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Select Depth Model",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Choose a monocular depth estimation model",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _buildModelOptionCard(
                    context: context,
                    title: "Depth-Anything-V2",
                    subtitle: "Optimized, fast & balanced performance",
                    icon: Icons.speed_outlined,
                    badgeText: "Balanced",
                    badgeColor: Colors.blueAccent,
                    modelPath: "assets/models/depth_anything_v2.tflite",
                  ),
                  const SizedBox(height: 16),
                  _buildModelOptionCard(
                    context: context,
                    title: "Depth-Anything-V3",
                    subtitle: "Enhanced accuracy & crisp edge definition",
                    icon: Icons.workspace_premium_outlined,
                    badgeText: "Precision",
                    badgeColor: Colors.purpleAccent,
                    modelPath: "assets/models/depth_anything_v3.tflite",
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildModelOptionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required String badgeText,
    required Color badgeColor,
    required String modelPath,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withAlpha(20),
          width: 1.0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.pop(context, modelPath),
            splashColor: badgeColor.withAlpha(40),
            highlightColor: badgeColor.withAlpha(20),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 5,
                  child: Container(
                    color: badgeColor,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20.0, 20.0, 16.0, 20.0),
                  child: Row(
                    children: [
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: badgeColor.withAlpha(30),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          color: badgeColor,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withAlpha(40),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: badgeColor.withAlpha(80),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    badgeText,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: badgeColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white54,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right,
                        color: Colors.white30,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _downloadRelitImage() async {
    if (_originalTex == null || _albedoTex == null || _depthTex == null || _shader == null) return;

    setState(() {
      _isLoading = true;
      _statusMessage = "Baking high-res relit image...";
    });

    try {
      final state = Provider.of<LightingState>(context, listen: false);
      final double imgW = _originalTex!.width.toDouble();
      final double imgH = _originalTex!.height.toDouble();

      // Retrieve the exact onscreen draw constraints to compute perfect scaling
      final RenderBox? box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) throw Exception("Cannot resolve screen dimensions.");
      final Size canvasSize = box.size;

      final double imageAspect = imgW / imgH;
      final double canvasAspect = canvasSize.width / canvasSize.height;

      double drawW, drawH, offsetX, offsetY;
      if (canvasAspect > imageAspect) {
        drawH = canvasSize.height;
        drawW = drawH * imageAspect;
        offsetX = (canvasSize.width - drawW) / 2.0;
        offsetY = 0.0;
      } else {
        drawW = canvasSize.width;
        drawH = drawW / imageAspect;
        offsetX = 0.0;
        offsetY = (canvasSize.height - drawH) / 2.0;
      }

      final Rect screenDrawRect = Rect.fromLTWH(offsetX, offsetY, drawW, drawH);
      final double scale = imgW / screenDrawRect.width;

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      canvas.scale(scale, scale);
      canvas.translate(-screenDrawRect.left, -screenDrawRect.top);

      final painter = PBRShaderPainter(
        shader: _shader!,
        albedo: _albedoTex!,
        original: _originalTex!,
        depth: _depthTex!,
        state: state,
        drawRect: screenDrawRect,
        showIndicators: false,
      );

      painter.paint(canvas, canvasSize);

      final ui.Picture picture = recorder.endRecording();
      final ui.Image renderedImage = await picture.toImage(imgW.toInt(), imgH.toInt());

      final ByteData? pngBytes = await renderedImage.toByteData(format: ui.ImageByteFormat.png);
      if (pngBytes == null) throw Exception("Failed to encode PNG.");

      final Uint8List bytes = pngBytes.buffer.asUint8List();

      setState(() {
        _isLoading = false;
        _statusMessage = "Ready to Imagine a new world!!";
      });

      // Ask user for save location and pass the bytes so the OS writes it securely
      final String? savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save High-Res Relit Image',
        fileName: 'relit_${DateTime.now().millisecondsSinceEpoch}.png',
        type: FileType.image,
        bytes: bytes, // Required on Android
      );

      if (savePath == null) return; // User canceled dialog

      setState(() {
        _isLoading = false;
        _statusMessage = "Ready to Imagine a new world!!";
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Success: Saved high-res relit image to $savePath"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = "Save failed: $e";
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error saving image: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final selectedModel = await _showModelSelectionSheet();
      if (selectedModel != null) {
        await _executeInferenceOn(File(image.path), selectedModel);
      }
    }
  }

  Future<void> _processAssetPipeline(String imageName) async {
    // ── PHASE 2: instant path ────────────────────────────────────────────────
    if (kUseCachedSample) {
      await _loadCachedSampleMaps(imageName);
      return;
    }

    // ── PHASE 1: full inference + auto-export ────────────────────────────────
    final selectedModel = await _showModelSelectionSheet();
    if (selectedModel == null) return;

    await _runDynamicPipelineForAsset(imageName, selectedModel);
  }

  Future<void> _executeInferenceOn(
    File imageFile,
    String selectedModelPath, {
    bool isSampleImage = false,
    String sampleImageName = "sample.jpg",
  }) async {
    setState(() {
      _isLoading = true;
      _statusMessage = "Loading Depth Model Engine...";
    });

    try {
      final imgBytes = await imageFile.readAsBytes();

      // Ensure depth engine is initialized with the selected model
      await _inferenceService.initializeEngine(selectedModelPath);

      setState(() => _statusMessage = "Estimating Depth Map...");

      // Execute Depth Estimator Layer locally on Mobile hardware
      final Float32List computedDepthMatrix = await _inferenceService.runLocalInference(imageFile);

      setState(() => _statusMessage = "Estimating Albedo and Normal Maps...");
      final Map<String, dynamic> texturePack =
          await _imageService.executeIntrinsicDecomposition(imgBytes, computedDepthMatrix);

      // ── PHASE 1 export ─────────────────────────────────────────────────────
      // Auto-save PNGs to device Downloads when processing the sample image.
      // Flip kUseCachedSample = true after pulling them with adb.
      if (isSampleImage) {
        debugPrint('[Cache Export] ALBEDO size   = ${texturePack['albedo']!.length} bytes');
        debugPrint('[Cache Export] ORIGINAL size = ${texturePack['original']!.length} bytes');
        debugPrint('[Cache Export] DEPTH size    = ${texturePack['depth']!.length} bytes');
        setState(() => _statusMessage = "Exporting cache maps to Downloads...");
        await _exportSampleMaps(sampleImageName, texturePack);
      }

      // Transition structured byte lists into accelerated GPU Texture handles
      setState(() => _statusMessage = "Uploading textures to GPU...");
      int w = texturePack['width'];
      int h = texturePack['height'];
      final List<ui.Image> gpuHandles = await Future.wait([
        ImageProcessingService.createUiImageFromPixels(texturePack['albedo']!, w, h),
        ImageProcessingService.createUiImageFromPixels(texturePack['original']!, w, h),
        ImageProcessingService.createUiImageFromPixels(texturePack['depth']!, w, h),
      ]);

      setState(() {
        _albedoTex?.dispose();
        _originalTex?.dispose();
        _depthTex?.dispose();

        _albedoTex   = gpuHandles[0];
        _originalTex = gpuHandles[1];
        _depthTex    = gpuHandles[2];
        _isLoading   = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading     = false;
        _statusMessage = "Pipeline Exception thrown: $e";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  @override
  void dispose() {
    _inferenceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LightingState>();
    
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            setState(() {
              _albedoTex?.dispose();
              _originalTex?.dispose();
              _depthTex?.dispose();
              _albedoTex = null;
              _originalTex = null;
              _depthTex = null;
            });
          },
          child: const Text(
            "🌟 Relight",
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
        ),
        actions: [
          if (_albedoTex != null) ...[
            IconButton(
              icon: Icon(
                state.isLightingEnabled ? Icons.lightbulb : Icons.lightbulb_outline,
                color: state.isLightingEnabled ? Colors.yellow : Colors.grey,
              ),
              onPressed: () => state.toggleLighting(!state.isLightingEnabled),
              tooltip: "Toggle Lighting Edits",
            ),
            IconButton(
              icon: const Icon(Icons.download, color: Colors.blueAccent),
              onPressed: _downloadRelitImage,
              tooltip: "Download Relit Image",
            ),
          ],
          if (_shader != null && !_isLoading)
            IconButton(
              icon: const Icon(Icons.add_photo_alternate),
              onPressed: _pickImage,
              tooltip: "Select Workspace Target from Gallery",
            )
        ],
      ),
      body: _albedoTex != null && _originalTex != null && _depthTex != null && _shader != null
        ? Column(
            children: [
              const GlobalMapSelector(),
              Expanded(
                child: RelightCanvas(
                  key: _canvasKey,
                  albedoTexture: _albedoTex!,
                  originalTexture: _originalTex!,
                  depthTexture: _depthTex!,
                  compiledShader: _shader!,
                ),
              ),
              const ControlPanel(),
            ],
          )
        : _isLoading
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              )
            : _buildLandingPage(),
    );
  }

  Widget _buildLandingPage() {
    final List<String> sampleImages = ["1.jpg", "2.jpg", "3.jpg", "4.jpg", "5.jpg"];

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 16.0),
              child: Column(
                children: [
                  Center(
                    child: Icon(
                      Icons.blur_on,
                      size: 64,
                      color: Colors.blueAccent,
                    ),
                  ),

                  const SizedBox(height: 12),

                  const Center(
                    child: Text(
                      "🌟 Relight",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  const Center(
                    child: Text(
                      "Ready to Imagine a new world!!",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white60,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.85,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final String imgName = sampleImages[index];
                  final String label = "Sample Scene ${index + 1}";
                  return _buildSampleCard(imgName, label);
                },
                childCount: sampleImages.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                children: [
                  const Text(
                    "OR",
                    style: TextStyle(color: Colors.white24, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _pickImage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withAlpha(12),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.white.withAlpha(20)),
                      ),
                    ),
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                    label: const Text("Upload from Gallery", style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSampleCard(String imgName, String label) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(12)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _processAssetPipeline(imgName),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/images/$imgName',
                        fit: BoxFit.cover,
                      ),
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                              stops: [0.6, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(
                        Icons.play_circle_outline,
                        color: Colors.blueAccent,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
