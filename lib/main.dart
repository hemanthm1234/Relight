import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'models/lighting_state.dart';
import 'services/depth_inference_service.dart';
import 'services/image_processing_service.dart';
import 'widgets/control_panel.dart';
import 'widgets/relight_canvas.dart';

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
  
  bool _isLoading = false;
  String _statusMessage = "Loading Local AI Core Engine...";
  
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
      await _inferenceService.initializeEngine();
      
      // Load and compile graphics program runtime shaders
      final program = await ui.FragmentProgram.fromAsset('assets/shaders/pbr_relight.frag');
      _shader = program.fragmentShader();
      
      setState(() {
        _isLoading = false;
        _statusMessage = "Ready for Workspace Generation.";
      });
    } catch (e) {
      setState(() => _statusMessage = "Initialization Failure: $e");
    }
  }

  Future<void> _processAssetPipeline() async {
    setState(() {
      _isLoading = true;
      _statusMessage = "Running Monocular Inference Pipeline Context...";
    });

    try {
      // For standalone execution initialization from scratch, load an internal workspace asset image.
      // (User option: integrate image_picker dependency here to load live gallery context files)
      final ByteData assetRawData = await rootBundle.load('assets/images/sample.jpg');
      final Uint8List imgBytes = assetRawData.buffer.asUint8List();
      
      // Write temporarily to local disk cache structure context for model ingestion formats
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/ingest_cache.jpg');
      await tempFile.writeAsBytes(imgBytes);

      // Execute Depth Estimator Layer locally on Mobile hardware
      final Float32List computedDepthMatrix = await _inferenceService.runLocalInference(tempFile);

      setState(() => _statusMessage = "Executing Structural Intrinsic Separation Processing...");
      final Map<String, Uint8List> texturePack = await _imageService.executeIntrinsicDecomposition(imgBytes, computedDepthMatrix);

      // Transition structured byte lists into accelerated GPU Texture handles concurrently
      final List<ui.Image> GPUHandles = await Future.wait([
        ImageProcessingService.createUiImageFromBytes(texturePack['albedo']!),
        ImageProcessingService.createUiImageFromBytes(texturePack['original']!),
        ImageProcessingService.createUiImageFromBytes(texturePack['depth']!),
      ]);

      setState(() {
        _albedoTex = GPUHandles[0];
        _originalTex = GPUHandles[1];
        _depthTex = GPUHandles[2];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = "Pipeline Exception thrown: $e";
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error executing internal network metrics: $e")));
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
              icon: const Icon(Icons.photo_library),
              onPressed: _processAssetPipeline,
              tooltip: "Process Base Workspace Target",
            )
        ],
      ),
      body: _albedoTex != null && _originalTex != null && _depthTex != null && _shader != null
        ? Column(
            children: [
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
