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

// Fixed 4 lights max to ensure deterministic uniform float indices
uniform vec3 u_LightPos_0; uniform vec3 u_LightColor_0; uniform float u_LightIntensity_0;
uniform vec3 u_LightPos_1; uniform vec3 u_LightColor_1; uniform float u_LightIntensity_1;
uniform vec3 u_LightPos_2; uniform vec3 u_LightColor_2; uniform float u_LightIntensity_2;
uniform vec3 u_LightPos_3; uniform vec3 u_LightColor_3; uniform float u_LightIntensity_3;

out vec4 fragColor;

float getLuminance(vec3 color) {
    return dot(color, vec3(0.299, 0.587, 0.114));
}

// Compute UV from fragment position, mapping from the draw rect to [0,1]
vec2 computeUV() {
    return (gl_FragCoord.xy - u_DrawOffset) / u_DrawSize;
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
    vec3 rayStep = (l * 6.0);
    vec3 currentRayPos = surfacePos + rayStep;
    float shadowAccum = 0.0;

    for (int i = 0; i < maxSteps; i++) {
        // Convert ray position to UV for depth sampling
        vec2 sampleUV = (currentRayPos.xy - u_DrawOffset) / u_DrawSize;
        if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) break;
        
        float geomDepth = texture(u_DepthTex, sampleUV).r * 400.0;
        
        if (currentRayPos.z < geomDepth - 1.5) {
            float depthDifference = (geomDepth - 1.5) - currentRayPos.z;
            shadowAccum += vec3(1.0).r * (1.0 - smoothstep(0.0, u_ShadowSoftness * 10.0, depthDifference));
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
    
    float dL = texture(u_DepthTex, uv + vec2(-texelSize.x, 0.0)).r;
    float dR = texture(u_DepthTex, uv + vec2(texelSize.x, 0.0)).r;
    float dT = texture(u_DepthTex, uv + vec2(0.0, texelSize.y)).r;
    float dB = texture(u_DepthTex, uv + vec2(0.0, -texelSize.y)).r;
    float d_dx = (dR - dL) * 2.0;
    float d_dy = (dT - dB) * 2.0;

    float gL = getLuminance(texture(u_OriginalTex, uv + vec2(-texelSize.x, 0.0)).rgb);
    float gR = getLuminance(texture(u_OriginalTex, uv + vec2(texelSize.x, 0.0)).rgb);
    float gT = getLuminance(texture(u_OriginalTex, uv + vec2(0.0, texelSize.y)).rgb);
    float gB = getLuminance(texture(u_OriginalTex, uv + vec2(0.0, -texelSize.y)).rgb);
    float g_dx = (gR - gL) * 1.5;
    float g_dy = (gT - gB) * 1.5;

    float blended_dx = d_dx + (g_dx * u_Roughness); 
    float blended_dy = d_dy + (g_dy * u_Roughness);
    vec3 n = normalize(vec3(-blended_dx, -blended_dy, 1.0));

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

    vec3 surfacePos = vec3(gl_FragCoord.xy, depth * 400.0);
    // Camera position at center of the draw rect, looking from above
    vec3 camPos = vec3(u_DrawOffset.x + u_DrawSize.x / 2.0, u_DrawOffset.y + u_DrawSize.y / 2.0, 800.0);
    vec3 v = normalize(camPos - surfacePos);

    vec3 accumulatedLighting = u_AmbientLight * albedo;

    accumulatedLighting += computeLight(0, u_LightPos_0, u_LightColor_0, u_LightIntensity_0, surfacePos, n, v, albedo);
    accumulatedLighting += computeLight(1, u_LightPos_1, u_LightColor_1, u_LightIntensity_1, surfacePos, n, v, albedo);
    accumulatedLighting += computeLight(2, u_LightPos_2, u_LightColor_2, u_LightIntensity_2, surfacePos, n, v, albedo);
    accumulatedLighting += computeLight(3, u_LightPos_3, u_LightColor_3, u_LightIntensity_3, surfacePos, n, v, albedo);

    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    vec3 toneMappedColor = clamp((accumulatedLighting * (a * accumulatedLighting + b)) / (accumulatedLighting * (c * accumulatedLighting + d) + e), 0.0, 1.0);

    fragColor = vec4(pow(toneMappedColor, vec3(1.0 / 2.2)), 1.0);
}
