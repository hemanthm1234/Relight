#version 460 core
#include <flutter/runtime_effect.glsl>

uniform sampler2D u_AlbedoTex;
uniform sampler2D u_OriginalTex; 
uniform sampler2D u_DepthTex;

// Uniforms
uniform float u_ViewMode; // 0: Lit, 1: Original, 2: Albedo, 3: Depth, 4: Normal
uniform vec2 u_Resolution;

// Image fit uniforms — the rect within u_Resolution where the image is drawn
uniform vec2 u_DrawOffset; // top-left corner of the fitted image rect
uniform vec2 u_DrawSize;   // width/height of the fitted image rect
uniform vec2 u_ImageSize;  // original image dimensions (for reference)

uniform float u_Roughness;
uniform float u_Metallic;
uniform vec3 u_AmbientLight;
uniform float u_ShadowSoftness;
uniform float u_ActiveLights;
uniform float u_Scale;

// Fixed 4 lights max to ensure deterministic uniform float indices
uniform vec3 u_LightPos_0; uniform vec3 u_LightColor_0; uniform float u_LightIntensity_0;
uniform vec3 u_LightPos_1; uniform vec3 u_LightColor_1; uniform float u_LightIntensity_1;
uniform vec3 u_LightPos_2; uniform vec3 u_LightColor_2; uniform float u_LightIntensity_2;
uniform vec3 u_LightPos_3; uniform vec3 u_LightColor_3; uniform float u_LightIntensity_3;

out vec4 fragColor;

float getLuminance(vec3 color) {
    return dot(color, vec3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
}

// Get the local pixel coordinate relative to the fitted image
vec2 getLocalCoord() {
    return FlutterFragCoord().xy - u_DrawOffset;
}

// Compute UV from fragment position, mapping from the draw rect to [0,1]
vec2 computeUV() {
    return getLocalCoord() / u_DrawSize;
}

// Check if fragment is inside the image draw rect
bool isInsideDrawRect() {
    vec2 uv = computeUV();
    return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

// Function to process a single light source
// Light positions are in screen-space pixels, same coordinate system as gl_FragCoord
vec3 computeLight(int index, vec3 l_pos, vec3 l_color, float l_intensity, vec3 surfacePos, vec3 n, vec3 v, vec3 albedo) {
    if (index >= int(u_ActiveLights)) return vec3(0.0);
    
    vec3 l = normalize(l_pos - surfacePos);
    vec3 h = normalize(l + v);

    float V_shadow = 1.0;
    int maxSteps = 32;
    vec3 rayStep = (l * 6.0 * u_Scale);
    vec3 currentRayPos = surfacePos + rayStep;
    float shadowAccum = 0.0;

    for (int i = 0; i < maxSteps; i++) {
        // Convert ray position to UV for depth sampling
        vec2 sampleUV = (currentRayPos.xy) / u_DrawSize;
        if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) break;
        
        float geomDepth = texture(u_DepthTex, sampleUV).r * 1200.0 * u_Scale;
        
        if (currentRayPos.z < geomDepth - (1.5 * u_Scale)) {
            float depthDifference = (geomDepth - (1.5 * u_Scale)) - currentRayPos.z;
            shadowAccum += vec3(1.0).r * (1.0 - smoothstep(0.0, u_ShadowSoftness * 10.0 * u_Scale, depthDifference));
        }
        currentRayPos += rayStep;
    }
    V_shadow = clamp(1.0 - (shadowAccum / float(maxSteps)) * 3.0, 0.0, 1.0);

    float NdotL = max(dot(n, l), 0.0);
    float NdotV = max(dot(n, v), 0.00001);
    float NdotH = max(dot(n, h), 0.0);
    float HdotV = max(dot(h, v), 0.0);

    float alpha = u_Roughness * u_Roughness;
    float alphaSq = alpha * alpha;
    float denom = (NdotH * NdotH * (alphaSq - 1.0) + 1.0);
    float D = alphaSq / (3.1415926535 * denom * denom);

    vec3 F0 = mix(vec3(0.04), albedo, u_Metallic);
    vec3 F = F0 + (1.0 - F0) * pow(clamp(1.0 - HdotV, 0.0, 1.0), 5.0);

    float k = ((u_Roughness + 1.0) * (u_Roughness + 1.0)) / 8.0;
    float G1V = NdotV / (NdotV * (1.0 - k) + k);
    float G1L = NdotL / (NdotL * (1.0 - k) + k);
    float G = G1V * G1L;

    vec3 kD = (vec3(1.0) - F) * (1.0 - u_Metallic);
    vec3 diffuseComponent = kD * (albedo / 3.1415926535);
    vec3 specularComponent = (D * G * F) / (4.0 * NdotL * NdotV + 0.001);

    float dist = length(l_pos - surfacePos);
    vec3 incomingRadiance = (l_color * l_intensity * V_shadow) / (dist * dist + 1.0);
    
    return (diffuseComponent + specularComponent) * incomingRadiance * NdotL;
}

void main() {
    // If outside the image draw rect, render black
    if (!isInsideDrawRect()) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    vec2 uv = computeUV();
    int mode = int(u_ViewMode);
    
    // Mode 1: Original image
    if (mode == 1) {
        fragColor = vec4(texture(u_OriginalTex, uv).rgb, 1.0);
        return;
    }

    vec3 albedo = texture(u_AlbedoTex, uv).rgb;
    float depth = texture(u_DepthTex, uv).r;

    // Mode 2: Albedo
    if (mode == 2) {
        fragColor = vec4(albedo, 1.0);
        return;
    }
    // Mode 3: Depth
    if (mode == 3) {
        fragColor = vec4(vec3(depth), 1.0);
        return;
    }

    // Compute normals from depth (needed for modes 0 and 4)
    vec2 texelSize = 1.0 / u_DrawSize;
    
    // Compute unified heights for 3x3 Sobel
    // Unified height: H = D * 2.0 + G * u_Roughness * 0.5

    float w_d = 1.0;
    float w_g = 0.5;

    float h00 = texture(u_DepthTex, uv + vec2(-texelSize.x, texelSize.y)).r * w_d + getLuminance(texture(u_OriginalTex, uv + vec2(-texelSize.x, texelSize.y)).rgb) * u_Roughness * w_g;
    float h01 = texture(u_DepthTex, uv + vec2(0.0, texelSize.y)).r * w_d + getLuminance(texture(u_OriginalTex, uv + vec2(0.0, texelSize.y)).rgb) * u_Roughness * w_g;
    float h02 = texture(u_DepthTex, uv + vec2(texelSize.x, texelSize.y)).r * w_d + getLuminance(texture(u_OriginalTex, uv + vec2(texelSize.x, texelSize.y)).rgb) * u_Roughness * w_g;

    float h10 = texture(u_DepthTex, uv + vec2(-texelSize.x, 0.0)).r * w_d + getLuminance(texture(u_OriginalTex, uv + vec2(-texelSize.x, 0.0)).rgb) * u_Roughness * w_g;
    float h12 = texture(u_DepthTex, uv + vec2(texelSize.x, 0.0)).r * w_d + getLuminance(texture(u_OriginalTex, uv + vec2(texelSize.x, 0.0)).rgb) * u_Roughness * w_g;

    float h20 = texture(u_DepthTex, uv + vec2(-texelSize.x, -texelSize.y)).r * w_d + getLuminance(texture(u_OriginalTex, uv + vec2(-texelSize.x, -texelSize.y)).rgb) * u_Roughness * w_g;
    float h21 = texture(u_DepthTex, uv + vec2(0.0, -texelSize.y)).r * w_d + getLuminance(texture(u_OriginalTex, uv + vec2(0.0, -texelSize.y)).rgb) * u_Roughness * w_g;
    float h22 = texture(u_DepthTex, uv + vec2(texelSize.x, -texelSize.y)).r * w_d + getLuminance(texture(u_OriginalTex, uv + vec2(texelSize.x, -texelSize.y)).rgb) * u_Roughness * w_g;

    // Full 3x3 Sobel filter
    float dx = (-h00 + h02) + (-2.0*h10 + 2.0*h12) + (-h20 + h22);
    float dy = (-h00 - 2.0*h01 - h02) + (h20 + 2.0*h21 + h22);

    // Apply dynamic bump strength exactly as in Python
    float bumpStrength = 0.1;
    float dynamicStrength = bumpStrength * max(u_DrawSize.x, u_DrawSize.y);
    
    dx *= dynamicStrength;
    dy *= dynamicStrength;

    vec3 n = normalize(vec3(-dx, dy, 1.0));

    // Mode 4: Normal map visualization
    if (mode == 4) {
        fragColor = vec4(n * 0.5 + 0.5, 1.0);
        return;
    }

    // Mode 0: Lit — PBR relighting
    // If no lights are active, fall back to showing the original image
    if (u_ActiveLights < 1.0) {
        fragColor = vec4(texture(u_OriginalTex, uv).rgb, 1.0);
        return;
    }

    // Use localized coordinates so it perfectly matches the light positions mapped in Dart
    vec2 localXY = getLocalCoord();
    vec3 surfacePos = vec3(localXY, depth * 1200.0 * u_Scale);

    // Camera now centers directly over the localized image space
    vec3 camPos = vec3(u_DrawSize.x / 2.0, u_DrawSize.y / 2.0, 2400.0 * u_Scale);
    vec3 v = normalize(camPos - surfacePos);

    vec3 originalColor = texture(u_OriginalTex, uv).rgb;

    // 1. Isolate the Ambient Baseline (Do NOT multiply this by PI)
    vec3 ambientLighting = u_AmbientLight * originalColor;

    // 2. Accumulate Artificial Point Lights
    vec3 pointLighting = vec3(0.0);
    pointLighting += computeLight(0, u_LightPos_0, u_LightColor_0, u_LightIntensity_0, surfacePos, n, v, originalColor);
    pointLighting += computeLight(1, u_LightPos_1, u_LightColor_1, u_LightIntensity_1, surfacePos, n, v, originalColor);
    pointLighting += computeLight(2, u_LightPos_2, u_LightColor_2, u_LightIntensity_2, surfacePos, n, v, originalColor);
    pointLighting += computeLight(3, u_LightPos_3, u_LightColor_3, u_LightIntensity_3, surfacePos, n, v, originalColor);

    // 3. Apply the PI boost ONLY to the point lights to balance the BRDF diffuse integral
    pointLighting *= 3.1415926535;

    // 4. Combine for final radiance
    vec3 accumulatedLighting = ambientLighting + pointLighting;

    // 5. ACES Tonemapping
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    vec3 toneMappedColor = clamp((accumulatedLighting * (a * accumulatedLighting + b)) / (accumulatedLighting * (c * accumulatedLighting + d) + e), 0.0, 1.0);

    fragColor = vec4(pow(toneMappedColor, vec3(1.0 / 2.2)), 1.0);
}
