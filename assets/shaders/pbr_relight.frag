#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform sampler2D u_AlbedoTex;
uniform sampler2D u_OriginalTex; 
uniform sampler2D u_DepthTex;

uniform float u_ViewMode; 
uniform vec2 u_Resolution;
uniform vec2 u_DrawOffset; 
uniform vec2 u_DrawSize;   
uniform vec2 u_ImageSize;

// Surface & Lighting
uniform float u_Roughness;
uniform float u_Metallic;
uniform vec3 u_AmbientLight;
uniform float u_ShadowSoftness;
uniform float u_ActiveLights;

// Photorealism Tuning Parameters
uniform float u_MicroDetailStrength; // Controls luminance-driven micro-normal perturbation
uniform float u_AlbedoBlend;         // Controls De-Lighting Strength

// Camera & Projection Uniforms
uniform float u_FOV;
uniform float u_ZminRatio;
uniform float u_ZmaxRatio;

// Light Structs
uniform vec3 u_LightPos_0; uniform vec3 u_LightColor_0; uniform float u_LightIntensity_0; uniform float u_LightDecay_0;
uniform vec3 u_LightPos_1; uniform vec3 u_LightColor_1; uniform float u_LightIntensity_1; uniform float u_LightDecay_1;
uniform vec3 u_LightPos_2; uniform vec3 u_LightColor_2; uniform float u_LightIntensity_2; uniform float u_LightDecay_2;
uniform vec3 u_LightPos_3; uniform vec3 u_LightColor_3; uniform float u_LightIntensity_3; uniform float u_LightDecay_3;

out vec4 fragColor;

// Utilities
float getLuminance(vec3 color) {
    return dot(color, vec3(0.2989, 0.5870, 0.1140));
}

vec2 getLocalCoord() { return FlutterFragCoord().xy - u_DrawOffset; }
vec2 computeUV() { return getLocalCoord() / u_DrawSize; }
bool isInsideDrawRect() {
    vec2 uv = computeUV();
    return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

vec2 snapUV(vec2 uv) {
    return (floor(uv * u_ImageSize) + 0.5) / u_ImageSize;
}

float unpackDepth(vec2 uv) {
    // Depth texture uses 16-bit packing: R = coarse, G = fine
    // No gamma correction — depth is synthetic data, not a photograph
    vec3 color = texture(u_DepthTex, snapUV(uv)).rgb;
    return color.r + (color.g / 255.0);
}

// ---------------------------------------------------------
// 3D PROJECTION & UNPROJECTION ARCHITECTURE
// ---------------------------------------------------------

// Calculates Zc (Distance from focal point to image plane)
float getZc() {
    float maxDim = max(u_DrawSize.x, u_DrawSize.y);
    return maxDim / (2.0 * tan(u_FOV / 2.0));
}

// FIX #1: Removed luminance-driven micro-bumps from the Z-depth calculation.
// The depth map alone defines the macro geometry. Luminance micro-detail is
// now handled exclusively in getNormal() via TBN perturbation, controlled by
// u_MicroDetailStrength. This prevents dark image regions (hair, shadows,
// polka dots) from being interpreted as physical craters.
float getZ(vec2 uv) {
    float d = unpackDepth(uv);
    float zc = getZc();
    float zMin = u_ZminRatio * zc;
    float zMax = u_ZmaxRatio * zc;
    return zMin + d * (zMax - zMin);
}

// Unprojects a 2D screen UV into a physical 3D World Coordinate
vec3 getPosition(vec2 uv) {
    float Z = getZ(uv);
    float zc = getZc();
    vec2 imgCoord = (uv - 0.5) * u_DrawSize;
    float X = imgCoord.x * (1.0 + Z / zc);
    float Y = imgCoord.y * (1.0 + Z / zc);
    return vec3(X, Y, Z);
}

// Helper: sample luminance at an offset for micro-normal perturbation
float getLumOffset(vec2 uv, vec2 offset) {
    vec3 rawOrig = pow(texture(u_OriginalTex, snapUV(uv + offset)).rgb, vec3(1.0 / 2.2));
    return getLuminance(rawOrig);
}

// FIX #1 (continued): Computes Normal via Sobel cross product on the depth-only
// macro geometry, then optionally perturbs it with luminance micro-detail
// in proper TBN (Tangent-Bitangent-Normal) space, gated by u_MicroDetailStrength.
vec3 getNormal(vec2 uv) {
    // MACRO BASELINE WIDENING: Step 3 pixels instead of 1 for the Sobel cross-product.
    // This bridges over residual micro-jitter from 16-bit float rounding,
    // acting as a built-in anti-aliaser for the normal vectors.
    vec2 texSize = 3.0 / u_ImageSize;
    
    vec3 pTL = getPosition(uv + vec2(-texSize.x, -texSize.y));
    vec3 pTC = getPosition(uv + vec2( 0.0,        -texSize.y));
    vec3 pTR = getPosition(uv + vec2( texSize.x, -texSize.y));
    
    vec3 pML = getPosition(uv + vec2(-texSize.x,  0.0));
    vec3 pMR = getPosition(uv + vec2( texSize.x,  0.0));
    
    vec3 pBL = getPosition(uv + vec2(-texSize.x,  texSize.y));
    vec3 pBC = getPosition(uv + vec2( 0.0,         texSize.y));
    vec3 pBR = getPosition(uv + vec2( texSize.x,  texSize.y));
    
    // Sobel tangent vectors from the macro depth geometry
    vec3 dPdu = (pTR + 2.0 * pMR + pBR) - (pTL + 2.0 * pML + pBL);
    vec3 dPdv = (pBL + 2.0 * pBC + pBR) - (pTL + 2.0 * pTC + pTR);
    
    vec3 macroNormal = normalize(cross(dPdu, dPdv));
    if (macroNormal.z > 0.0) macroNormal = -macroNormal;
    
    // If micro-detail is effectively off, skip the expensive TBN math
    if (u_MicroDetailStrength <= 0.01) return macroNormal;

    // Build a TBN matrix from the macro surface tangents
    vec3 T = normalize(dPdu);
    T = normalize(T - dot(T, macroNormal) * macroNormal); // Gram-Schmidt orthogonalize
    vec3 B = normalize(dPdv);
    B = normalize(B - dot(B, macroNormal) * macroNormal - dot(B, T) * T);
    mat3 TBN = mat3(T, B, macroNormal);
    
    // Sobel filter over image luminance for micro-detail slopes
    float lTL = getLumOffset(uv, vec2(-texSize.x, -texSize.y));
    float lTC = getLumOffset(uv, vec2( 0.0,        -texSize.y));
    float lTR = getLumOffset(uv, vec2( texSize.x, -texSize.y));
    float lML = getLumOffset(uv, vec2(-texSize.x,  0.0));
    float lMR = getLumOffset(uv, vec2( texSize.x,  0.0));
    float lBL = getLumOffset(uv, vec2(-texSize.x,  texSize.y));
    float lBC = getLumOffset(uv, vec2( 0.0,         texSize.y));
    float lBR = getLumOffset(uv, vec2( texSize.x,  texSize.y));
    
    float dLdu = (lTR + 2.0 * lMR + lBR) - (lTL + 2.0 * lML + lBL);
    float dLdv = (lBL + 2.0 * lBC + lBR) - (lTL + 2.0 * lTC + lTR);
    
    // Perturb the normal in tangent space, scaled by user-controlled strength
    vec3 detailNormal = normalize(vec3(-dLdu * u_MicroDetailStrength, -dLdv * u_MicroDetailStrength, 1.0));
    return normalize(TBN * detailNormal);
}

// ---------------------------------------------------------
// TRUE 3D SHADOW RAYMARCHING
// ---------------------------------------------------------
float calculateShadow(vec3 surfacePos, vec3 l_pos, vec3 n) {
    vec3 l = normalize(l_pos - surfacePos);
    
    // Normal-based backface culling: if the surface faces away from the light, it's in shadow.
    // This replaces the old hard Z-slice which created an invisible flat wall.
    if (dot(n, l) <= 0.0) return 0.0;
    float shadowAccum = 0.0;
    int maxSteps = 32;
    
    // --- FIX 1: THE SHADOW BIAS ---
    // Push the starting position out along the Normal vector slightly.
    // This prevents the ray from instantly colliding with its own microscopic surface geometry.
    float bias = 5.0; 
    vec3 currentRayPos = surfacePos + (n * bias) + (l * bias); 
    
    vec3 rayStep = l * (length(l_pos - currentRayPos) / float(maxSteps));
    float zc = getZc();

    for(int i = 0; i < maxSteps; i++) {
        float projFactor = 1.0 + currentRayPos.z / zc;
        if (projFactor <= 0.0) break; 
        
        vec2 imgCoord = currentRayPos.xy / projFactor;
        vec2 sampleUV = (imgCoord / u_DrawSize) + 0.5;
        
        if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) break;
        
        float geomZ = getZ(sampleUV);
        
        // --- FIX 1: CORRECTED OCCLUSION MATH ---
        // If currentRayPos.z is larger than geomZ, the ray is BEHIND the surface.
        float distToOccluder = currentRayPos.z - geomZ;
        
        if (distToOccluder > bias) {
            // Hard Hit: Ray is physically behind an object
            shadowAccum += 1.0;
        } else if (distToOccluder > -u_ShadowSoftness * 50.0) {
            // Penumbra: Ray passed very closely in front of an object, generating a soft shadow edge
            shadowAccum += smoothstep(-u_ShadowSoftness * 50.0, bias, distToOccluder);
        }
        currentRayPos += rayStep;
    }
    return clamp(1.0 - (shadowAccum / float(maxSteps)) * 4.0, 0.0, 1.0);
}

// ---------------------------------------------------------
// PBR MASTER EQUATION EVALUATION
// ---------------------------------------------------------
vec3 computeLight(int index, vec3 l_pos, vec3 l_color, float l_intensity, float l_decay, vec3 surfacePos, vec3 n, vec3 v, vec3 albedo, float metallic, float roughness) {
    if (index >= int(u_ActiveLights)) return vec3(0.0);
    
    vec3 l = normalize(l_pos - surfacePos);
    
    // Normal-based backface culling: gracefully roll light to zero based on surface curvature
    // instead of an arbitrary depth threshold that creates hard horizontal lines
    float NdotL = max(dot(n, l), 0.0);
    if (NdotL <= 0.001) return vec3(0.0);
    
    vec3 h = normalize(l + v);
    
    // Pass the normal to the shadow function for biasing
    float V_shadow = calculateShadow(surfacePos, l_pos, n);
    
    // NdotL already computed above for early exit
    float NdotV = max(dot(n, v), 0.0001);
    float NdotH = max(dot(n, h), 0.0);
    float VdotH = max(dot(v, h), 0.0);
    
    // --- NEW: USER CONTROLLED ATTENUATION DECAY ---
    float dist = length(l_pos - surfacePos);
    // l_decay replaces the hardcoded square law. 
    // 2.0 = Realistic Inverse Square. 1.0 = Linear (Reaches far). 0.5 = Massive Reach.
    float attenuation = 1.0 / (pow(dist, l_decay) + 1.0);
    
    // --- FIX 1: ALBEDO BLEACHING (Color Wash) ---
    // The stronger the light hits, the more the object's base color is pushed to white.
    // This allows the pure Light Color to dominate the diffuse multiplication.
    float washPower = clamp(attenuation * l_intensity * 0.00002, 0.0, 0.85); // Capped at 85% to retain slight native texture
    vec3 effectiveAlbedo = mix(albedo, vec3(1.0), washPower * (1.0 - metallic));

    // 1. Fresnel
    // Boosted baseline F0 for non-metals from 0.04 to 0.08 to catch more pure light color
    vec3 F0 = mix(vec3(0.30), effectiveAlbedo, metallic);
    vec3 F = F0 + (1.0 - F0) * pow(clamp(1.0 - VdotH, 0.0, 1.0), 5.0);
    
    // 2. Normal Distribution
    float alpha = max(roughness * roughness, 0.01); // Prevent pure 0.0 roughness explosions
    float alpha2 = alpha * alpha;
    float denomD = (NdotH * NdotH * (alpha2 - 1.0) + 1.0);
    float D = alpha2 / (3.1415926535 * denomD * denomD);
    
    // 3. Geometry
    float k = ((roughness + 1.0) * (roughness + 1.0)) / 8.0;
    float gl = NdotL / (NdotL * (1.0 - k) + k);
    float gv = NdotV / (NdotV * (1.0 - k) + k);
    float G = gl * gv;
    
    vec3 kd = (vec3(1.0) - F) * (1.0 - metallic);
    vec3 diffuse = kd * (effectiveAlbedo / 3.1415926535) * NdotL;
    
    // --- FIX 2: SPECULAR BOOST ---
    // Mathematically clamp the raw specular intensity so it doesn't break the physics limits
    // Multiply the final specular output by 2.5 to form a brilliant colored glaze
    vec3 specular = (D * G * F) / (4.0 * NdotV + 0.0001);
    specular = min(specular * 2.5, vec3(10.0)); // Prevent infinite spikes
    
    vec3 radiance = l_color * l_intensity * attenuation;
    
    return V_shadow * radiance * (diffuse + specular);
}

void main() {
    if (!isInsideDrawRect()) { fragColor = vec4(0.0, 0.0, 0.0, 1.0); return; }

    vec2 uv = computeUV();
    int mode = int(u_ViewMode);
    
    if (mode == 1) { fragColor = vec4(texture(u_OriginalTex, uv).rgb, 1.0); return; }

    vec3 albedo = texture(u_AlbedoTex, uv).rgb;
    float rawD = unpackDepth(uv);

    if (mode == 2) { fragColor = vec4(albedo, 1.0); return; }
    if (mode == 3) { fragColor = vec4(vec3(rawD), 1.0); return; }

    vec3 n = getNormal(uv);

    if (mode == 4) {
        vec3 visNormal = vec3(n.x, n.y, -n.z); 
        fragColor = vec4(visNormal * 0.5 + 0.5, 1.0);
        return;
    }

    if (u_ActiveLights < 1.0) { fragColor = vec4(texture(u_OriginalTex, uv).rgb, 1.0); return; }

    vec3 surfacePos = getPosition(uv);
    vec3 camPos = vec3(0.0, 0.0, -getZc());
    vec3 v = normalize(camPos - surfacePos);
    
    // Convert both textures to linear space
    vec3 originalColor = pow(texture(u_OriginalTex, uv).rgb, vec3(2.2)); 
    vec3 computedAlbedo = pow(albedo, vec3(2.2)); 

    // --- FIX: ALBEDO RESTORATION BLEND ---
    // Blends the photographic reality of the original image with the flattened intrinsic albedo.
    // 0.0 = Pure Photo (Perfect Texture, Heavy baked shadows)
    // 1.0 = Pure Albedo (No baked shadows, Plastic/Splotchy texture)
    vec3 baseAlbedo = mix(originalColor, computedAlbedo, u_AlbedoBlend);

    // We must apply the ambient light to the blended ALBEDO
    vec3 ambientLighting = u_AmbientLight * baseAlbedo;
    
    vec3 pointLighting = vec3(0.0);
    float zc = getZc();
    float zMin = u_ZminRatio * zc;
    float zMax = u_ZmaxRatio * zc;

    vec3 lPos0 = u_LightPos_0; lPos0.z = zMin + lPos0.z * (zMax - zMin);
    vec3 lPos1 = u_LightPos_1; lPos1.z = zMin + lPos1.z * (zMax - zMin);
    vec3 lPos2 = u_LightPos_2; lPos2.z = zMin + lPos2.z * (zMax - zMin);
    vec3 lPos3 = u_LightPos_3; lPos3.z = zMin + lPos3.z * (zMax - zMin);
    
    // Manually edited this to pass originalColor instead of baseAlbedo.
    pointLighting += computeLight(0, lPos0, u_LightColor_0, u_LightIntensity_0, u_LightDecay_0, surfacePos, n, v, originalColor, u_Metallic, u_Roughness);
    pointLighting += computeLight(1, lPos1, u_LightColor_1, u_LightIntensity_1, u_LightDecay_1, surfacePos, n, v, originalColor, u_Metallic, u_Roughness);
    pointLighting += computeLight(2, lPos2, u_LightColor_2, u_LightIntensity_2, u_LightDecay_2, surfacePos, n, v, originalColor, u_Metallic, u_Roughness);
    pointLighting += computeLight(3, lPos3, u_LightColor_3, u_LightIntensity_3, u_LightDecay_3, surfacePos, n, v, originalColor, u_Metallic, u_Roughness);

    vec3 C_linear = ambientLighting + pointLighting;

    // --- FIX 2: MAX-CHANNEL TONEMAPPING (Color Preservation) ---
    // Instead of using luminance (which crushes saturated colors to white),
    // we apply the ACES curve to the absolute brightest color channel.
    float maxC = max(max(C_linear.r, C_linear.g), C_linear.b);
    
    float a = 2.51; float b = 0.03; float c = 2.43; float d = 0.59; float e = 0.14;
    float mappedMax = clamp((maxC * (a * maxC + b)) / (maxC * (c * maxC + d) + e), 0.0, 1.0);
    
    // Scale all channels proportionally to the mapped max channel
    vec3 toneMappedColor = C_linear * (mappedMax / max(maxC, 0.0001));

    // Final Gamma Correction (1.0 / 2.2)
    fragColor = vec4(pow(toneMappedColor, vec3(0.4545)), 1.0);
}