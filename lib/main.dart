import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
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
      title: 'Relight',
      theme: ThemeData.dark(useMaterial3: true),
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
  Future<void> _loadCachedSampleMaps() async {
    setState(() {
      _isLoading = true;
      _statusMessage = "Loading cached maps from bundle...";
    });
    try {
      final albedoBytes   = (await rootBundle.load('assets/cache/sample_albedo.png')).buffer.asUint8List();
      final originalBytes = (await rootBundle.load('assets/cache/sample_original.png')).buffer.asUint8List();
      final depthBytes    = (await rootBundle.load('assets/cache/sample_depth.png')).buffer.asUint8List();

      final List<ui.Image> handles = await Future.wait([
        ImageProcessingService.createUiImageFromBytes(albedoBytes),
        ImageProcessingService.createUiImageFromBytes(originalBytes),
        ImageProcessingService.createUiImageFromBytes(depthBytes),
      ]);

      setState(() {
        _albedoTex   = handles[0];
        _originalTex = handles[1];
        _depthTex    = handles[2];
        _isLoading   = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading      = false;
        _statusMessage  = "Cache load failed: $e";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Cache error: $e\nEnsure assets/cache/*.png files exist.")),
      );
    }
  }

  // ── PHASE 1 ──────────────────────────────────────────────────────────────
  // Export the three generated maps to /storage/emulated/0/Download/
  // Run once, pull with adb, place in assets/cache/, then flip kUseCachedSample.
  Future<void> _exportSampleMaps(Map<String, Uint8List> texturePack) async {
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
        await _writeMapFiles(extDir.path, texturePack);
      } else {
        await _writeMapFiles(downloadsPath, texturePack);
      }
    } catch (e) {
      debugPrint("[Cache Export] Failed: $e");
    }
  }

  Future<void> _writeMapFiles(String dirPath, Map<String, Uint8List> texturePack) async {
    final albedo   = File('$dirPath/sample_albedo.png');
    final original = File('$dirPath/sample_original.png');
    final depth    = File('$dirPath/sample_depth.png');

    await albedo.writeAsBytes(texturePack['albedo']!);
    await original.writeAsBytes(texturePack['original']!);
    await depth.writeAsBytes(texturePack['depth']!);

    debugPrint('[Cache Export] ✅ sample_albedo.png   -> ${albedo.path}');
    debugPrint('[Cache Export] ✅ sample_original.png -> ${original.path}');
    debugPrint('[Cache Export] ✅ sample_depth.png    -> ${depth.path}');
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

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final selectedModel = await _showModelSelectionSheet();
      if (selectedModel != null) {
        await _executeInferenceOn(File(image.path), selectedModel);
      }
    }
  }

  Future<void> _processAssetPipeline() async {
    // ── PHASE 2: instant path ────────────────────────────────────────────────
    if (kUseCachedSample) {
      await _loadCachedSampleMaps();
      return;
    }

    // ── PHASE 1: full inference + auto-export ────────────────────────────────
    final selectedModel = await _showModelSelectionSheet();
    if (selectedModel == null) return;

    // Load asset image and write to a temp file for the TFLite engine
    final ByteData assetRawData = await rootBundle.load('assets/images/sample.jpg');
    final Uint8List imgBytes = assetRawData.buffer.asUint8List();
    final tempFile = File('${Directory.systemTemp.path}/ingest_cache.jpg');
    await tempFile.writeAsBytes(imgBytes);

    // Pass isSampleImage=true so _executeInferenceOn triggers the export
    await _executeInferenceOn(tempFile, selectedModel, isSampleImage: true);
  }

  Future<void> _executeInferenceOn(
    File imageFile,
    String selectedModelPath, {
    bool isSampleImage = false,
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
      final Map<String, Uint8List> texturePack =
          await _imageService.executeIntrinsicDecomposition(imgBytes, computedDepthMatrix);

      // ── PHASE 1 export ─────────────────────────────────────────────────────
      // Auto-save PNGs to device Downloads when processing the sample image.
      // Flip kUseCachedSample = true after pulling them with adb.
      if (isSampleImage) {
        debugPrint('[Cache Export] ALBEDO size   = ${texturePack['albedo']!.length} bytes');
        debugPrint('[Cache Export] ORIGINAL size = ${texturePack['original']!.length} bytes');
        debugPrint('[Cache Export] DEPTH size    = ${texturePack['depth']!.length} bytes');
        setState(() => _statusMessage = "Exporting cache maps to Downloads...");
        await _exportSampleMaps(texturePack);
      }

      // Transition structured byte lists into accelerated GPU Texture handles
      setState(() => _statusMessage = "Uploading textures to GPU...");
      final List<ui.Image> GPUHandles = await Future.wait([
        ImageProcessingService.createUiImageFromBytes(texturePack['albedo']!),
        ImageProcessingService.createUiImageFromBytes(texturePack['original']!),
        ImageProcessingService.createUiImageFromBytes(texturePack['depth']!),
      ]);

      setState(() {
        _albedoTex   = GPUHandles[0];
        _originalTex = GPUHandles[1];
        _depthTex    = GPUHandles[2];
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
        title: const Text("Relight"),
        actions: [
          if (_albedoTex != null) // Only show when image is loaded
            IconButton(
              icon: Icon(
                state.isLightingEnabled ? Icons.lightbulb : Icons.lightbulb_outline,
                color: state.isLightingEnabled ? Colors.yellow : Colors.grey,
              ),
              onPressed: () => state.toggleLighting(!state.isLightingEnabled),
              tooltip: "Toggle Lighting Edits",
            ),
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
                  albedoTexture: _albedoTex!,
                  originalTexture: _originalTex!,
                  depthTexture: _depthTex!,
                  compiledShader: _shader!,
                ),
              ),

              const ControlPanel(),
            ],
          )
        : Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isLoading) const CircularProgressIndicator() else const Icon(Icons.blur_on, size: 64, color: Colors.blueAccent),
                  const SizedBox(height: 16),
                  Text(_statusMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 24),
                  if (!_isLoading && _albedoTex == null)
                    ElevatedButton.icon(
                      onPressed: _processAssetPipeline,
                      icon: const Icon(Icons.bolt),
                      label: const Text("Initialize Sample Image"),
                    )
                ],
              ),
            ),
          ),
    );
  }
}
