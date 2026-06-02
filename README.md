<div align="center">
  <img src="logo.png" alt="Relight Logo" width="100" style="border-radius:50%;"/>

  # 🌟 Relight
  
  **A real-time, on-device monocular PBR (Physically Based Rendering) relighting application built with Flutter, TFLite, and custom GLSL fragment shaders.**
  
  [![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
  [![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
  [![TensorFlow Lite](https://img.shields.io/badge/TFLite-FF6F00?style=for-the-badge&logo=tensorflow&logoColor=white)](https://www.tensorflow.org/lite)
  [![GLSL](https://img.shields.io/badge/GLSL-5586A4?style=for-the-badge&logo=opengl&logoColor=white)](https://www.khronos.org/opengl/wiki/Core_Language_(GLSL))
</div>

## 📖 Overview

**Relight** enables users to dynamically adjust the lighting of any single 2D photograph in real-time, completely on-device. By leveraging cutting-edge monocular depth estimation models (**Depth-Anything-V2** & **V3**) and an optimized **GLSL Fragment Shader pipeline**, the application estimates depth, normal maps, and albedo (intrinsic decomposition) to construct a localized 3D scene from a single image.

Experience photorealistic, physically-based lighting interactions running at blazing speeds on mobile hardware (utilizing Vulkan/Impeller).

---

## ✨ Features

- 📱 **100% On-Device Processing**: No cloud dependency. All inferences and rendering happen locally on your smartphone.
- 🧠 **AI Depth Estimation**: Choose between *Depth-Anything-V2* (Balanced & Fast) or *Depth-Anything-V3* (High Precision) models.
- 💡 **Physically Based Rendering (PBR)**: Highly accurate light falloff, distance-based attenuation, and sophisticated normal mapping.
- 🎨 **Intrinsic Decomposition**: Automatically separates Albedo (base color) from baked-in illumination to apply new lights cleanly.
- 📸 **High-Res Export**: Bake out the final composite at full native resolution and save it directly to your device.
- 🏎️ **Hardware Accelerated**: Uses Flutter's new Impeller backend (Vulkan on Android, Metal on iOS) for 60FPS shader rendering.

---

## 📐 Mathematical Foundations

![2D Relight Math](2D_Relight_math.png)

---

## 🛠️ Architecture & Tech Stack

1. **Frontend UI**: Flutter (Dart) - Handles layout, responsive control panels, and the rendering canvas.
2. **AI Inference Layer**: `tflite_flutter` - Runs the monocular depth models on device Neural Processing Units (NPUs) or GPUs.
3. **Graphics Pipeline**: `ui.FragmentProgram` - Compiles `pbr_relight.frag` (GLSL) into an Impeller-compatible runtime shader.
4. **Data Handling**: Native isolates handle intense byte-array manipulations for texture packing and intrinsic decomposition without blocking the UI thread.

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (>= 3.3.0)
- Android Studio / Xcode for device deployment

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/hemanthm1234/Relight.git
   cd Relight
   ```

2. **Fetch Dependencies:**
   ```bash
   flutter pub get
   ```

3. **Provide ML Models:**
   Ensure you have the TFLite models placed in the `assets/models/` directory:
   - `depth_anything_v2.tflite`
   - `depth_anything_v3.tflite`

4. **Run the application:**
   For optimal performance and to enable the Vulkan/Metal backend properly for shaders, run in **Release** mode:
   ```bash
   flutter run --release
   ```

You can also directly find the latest [apk file here](build/app/outputs/flutter-apk/app-release.apk).

---

## 💡 Usage Workflow

1. **Import:** Select a sample image or upload a photograph from your gallery.
2. **Estimate:** Select the Depth model (Depth-Anything-V2/V3). The app will run the Depth-Anything model to generate depth map. Next, albedo and normal maps are generated.
3. **Relight:** Use the interactive canvas to place lights. Adjust color, radius, depth scale, and intensity in the control panel.
4. **Export:** Tap the download icon to save your relit masterpiece.

---

## 👨‍💻 Creator

**Hemanth M**

- GitHub: https://github.com/hemanthm1234