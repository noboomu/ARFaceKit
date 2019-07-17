//
//  Shaders.metal
//  ARMetal
//
//  Created by joshua bauer on 3/7/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

#include <metal_stdlib>
#include <simd/simd.h>

#include <CoreImage/CoreImage.h>

#import "ShaderTypes.h"
#import "ShaderCommon.h"

using namespace metal;

#pragma MARK - Structs

typedef struct {
    float2 position [[attribute(kVertexAttributePosition)]];
    float2 texCoord [[attribute(kVertexAttributeTexcoord)]];
} ImageVertex;


typedef struct {
    float4 position [[position]];
    float2 texCoord ;
} ImageColorInOut;


typedef struct {
    float3 position [[attribute(kVertexAttributePosition)]];
    float2 texCoord [[attribute(kVertexAttributeTexcoord)]];
    half3 normal    [[attribute(kVertexAttributeNormal)]];
} Vertex;


typedef struct {
    float4 position [[position]];
    float4 color;
    half3  eyePosition;
    half3  normal;
} ColorInOut;


typedef struct {
    float3 position  [[ attribute(0) ]];
    float2 texCoord  [[ attribute(1) ]];
} SCNVertexInput;


typedef struct {
    float4 position [[position]];
    float2 texCoord;
} SCNVertexOutput;

typedef struct {
    float4 position  [[attribute(0)]];
} ScreenCoordinateInput;

typedef struct {
    float4 position  [[position]];
    float pointSize [[point_size]];
} ScreenCoordinateOutput;

#pragma MARK - Shaders


// Captured image vertex function
vertex ImageColorInOut capturedImageVertexFunction(ImageVertex in [[stage_in]]) {
    ImageColorInOut out;
    
    // Pass through the image vertex's position
    out.position = float4(in.position, 0.0, 1.0);
    
    // Pass through the texture coordinate
    out.texCoord = in.texCoord;
    
    return out;
}

// Captured image fragment function
fragment float4 capturedImageFragmentFunction(ImageColorInOut in [[stage_in]],
                                            texture2d<float, access::sample> capturedImageTextureY [[ texture(kTextureIndexY) ]],
                                            texture2d<float, access::sample> capturedImageTextureCbCr [[ texture(kTextureIndexCbCr) ]]) {
    
    constexpr sampler s(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);
    
    const float4x4 ycbcrToRGBTransform = float4x4(
        float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
        float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
        float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
        float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
    );
 
    // Sample Y and CbCr textures to get the YCbCr color at the given texture coordinate
    float4 ycbcr = float4(capturedImageTextureY.sample(s, in.texCoord).r,
                          capturedImageTextureCbCr.sample(s, in.texCoord).rg, 1.0);
    
    // Return converted RGB color
    return ycbcrToRGBTransform * ycbcr;
}

// Captured image vertex function
vertex ImageColorInOut cvVertexFunction(ImageVertex in [[stage_in]]) {
    ImageColorInOut out;
    
    // Pass through the image vertex's position
    out.position = float4(in.position, 0.0, 1.0);
    
    // Pass through the texture coordinate
    out.texCoord = in.texCoord;
    
    return out;
}

// Captured image fragment function
fragment float4 cvFragmentFunction(ImageColorInOut in [[stage_in]],
                                            texture2d<float, access::sample> sourceTexture [[ texture(0) ]]) {
    
    constexpr sampler s(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);
    
    
    return float4(sourceTexture.sample(s, in.texCoord).rgb,1.0);
}

//
//
//
//// Anchor geometry vertex function
//vertex ColorInOut anchorGeometryVertexTransform(Vertex in [[stage_in]],
//                                                constant SharedUniforms &sharedUniforms [[ buffer(kBufferIndexSharedUniforms) ]],
//                                                constant InstanceUniforms *instanceUniforms [[ buffer(kBufferIndexInstanceUniforms) ]],
//                                                ushort vid [[vertex_id]],
//                                                ushort iid [[instance_id]]) {
//    ColorInOut out;
//
//    // Make position a float4 to perform 4x4 matrix math on it
//    float4 position = float4(in.position, 1.0);
//
//    float4x4 modelMatrix = instanceUniforms[iid].modelMatrix;
//    float4x4 modelViewMatrix = sharedUniforms.viewMatrix * modelMatrix;
//
//
//    // Calculate the position of our vertex in clip space and output for clipping and rasterization
//    out.position = sharedUniforms.projectionMatrix * modelViewMatrix * position;
//
//    // Color each face a different color
//    ushort colorID = vid / 4 % 6;
//    out.color = colorID == 0 ? float4(0.0, 1.0, 0.0, 1.0) // Right face
//              : colorID == 1 ? float4(1.0, 0.0, 0.0, 1.0) // Left face
//              : colorID == 2 ? float4(0.0, 0.0, 1.0, 1.0) // Top face
//              : colorID == 3 ? float4(1.0, 0.5, 0.0, 1.0) // Bottom face
//              : colorID == 4 ? float4(1.0, 1.0, 0.0, 1.0) // Back face
//              : float4(1.0, 1.0, 1.0, 1.0); // Front face
//
//    // Calculate the positon of our vertex in eye space
//    out.eyePosition = half3((modelViewMatrix * position).xyz);
//
//    // Rotate our normals to world coordinates
//    float4 normal = modelMatrix * float4(in.normal.x, in.normal.y, in.normal.z, 0.0f);
//    out.normal = normalize(half3(normal.xyz));
//
//    return out;
//}
//
//// Anchor geometry fragment function
//fragment float4 anchorGeometryFragmentLighting(ColorInOut in [[stage_in]],
//                                               constant SharedUniforms &uniforms [[ buffer(kBufferIndexSharedUniforms) ]]) {
//
//    float3 normal = float3(in.normal);
//
//    // Calculate the contribution of the directional light as a sum of diffuse and specular terms
//    float3 directionalContribution = float3(0);
//    {
//        // Light falls off based on how closely aligned the surface normal is to the light direction
//        float nDotL = saturate(dot(normal, -uniforms.directionalLightDirection));
//
//        // The diffuse term is then the product of the light color, the surface material
//        // reflectance, and the falloff
//        float3 diffuseTerm = uniforms.directionalLightColor * nDotL;
//
//        // Apply specular lighting...
//
//        // 1) Calculate the halfway vector between the light direction and the direction they eye is looking
//        float3 halfwayVector = normalize(-uniforms.directionalLightDirection - float3(in.eyePosition));
//
//        // 2) Calculate the reflection angle between our reflection vector and the eye's direction
//        float reflectionAngle = saturate(dot(normal, halfwayVector));
//
//        // 3) Calculate the specular intensity by multiplying our reflection angle with our object's
//        //    shininess
//        float specularIntensity = saturate(powr(reflectionAngle, uniforms.materialShininess));
//
//        // 4) Obtain the specular term by multiplying the intensity by our light's color
//        float3 specularTerm = uniforms.directionalLightColor * specularIntensity;
//
//        // Calculate total contribution from this light is the sum of the diffuse and specular values
//        directionalContribution = diffuseTerm + specularTerm;
//    }
//
//    // The ambient contribution, which is an approximation for global, indirect lighting, is
//    // the product of the ambient light intensity multiplied by the material's reflectance
//    float3 ambientContribution = uniforms.ambientLightColor;
//
//    // Now that we have the contributions our light sources in the scene, we sum them together
//    // to get the fragment's lighting value
//    float3 lightContributions = ambientContribution + directionalContribution;
//
//    // We compute the final color by multiplying the sample from our color maps by the fragment's
//    // lighting value
//    float3 color = in.color.rgb * lightContributions;
//
//    // We use the color we just computed and the alpha channel of our
//    // colorMap for this fragment's alpha value
//    return float4(color, in.color.w);
//}
//


constant bool lutEnabled [[ function_constant(kLUTEnabled) ]];
constant bool contrastEnabled [[ function_constant(kContrastEnabled) ]];
constant bool saturationEnabled [[ function_constant(kSaturationEnabled) ]];

vertex ImageColorInOut compositeVertexFunction(
                                         ImageVertex in [[stage_in]],
                                         ushort vid [[ vertex_id ]]
                                         ) {
    ImageColorInOut out;
//    out.position = float4(float2(in.position), 0.0, 1.0);
//    out.texCoord = float2(in.position);
    
    out.position = quadPosition(vid);
    out.texCoord = quadTexCoord(vid);
    
    return out;
}


fragment half4 compositeFragmentFunction (
                                     ImageColorInOut in [[stage_in]],
                                     half4 sourceColor [[color(0)]],
                                     texture2d<half, access::sample>  compositeTexture [[ texture(0) ]]
                                     ) {

    constexpr sampler s(mip_filter::linear,
                        mag_filter::linear,
                        min_filter::linear);
    
    half4 compositeColor =  compositeTexture.sample(s, in.texCoord);
    
    if( compositeColor.a == 0.0h )
    {
         discard_fragment();
    }
    
    return half4(compositeColor);
    
 
    
}

vertex ImageColorInOut colorProcessingVertexFunction(
                                               ImageVertex in [[stage_in]],
                                               ushort vid [[ vertex_id ]]
                                               ) {
    ImageColorInOut out;
    out.position = float4(float2(in.position), 0.0, 1.0);
    out.texCoord = float2(in.position);
    return out;
}


fragment float4 colorProcessingFragmentFunction (
                                                 
                                           ImageColorInOut in [[stage_in]],
                                           float4 sourceColor [[color(0)]],
                                           constant ColorProcessingParameters &parameters [[ buffer(0) ]],
                                           texture3d<half> lutTexture [[ texture(0) ]]
                                                 
                                           ) {
    
    float4 finalColor = sourceColor;
    
    if(parameters.lutIntensity != 0.0 && !is_null_texture(lutTexture)) {
        finalColor.rgb = float3(lookUpColor(lutTexture, half3(sourceColor.rgb), half(parameters.lutIntensity)));
    }
    
    if(parameters.contrastIntensity != 0.0) {
        
        finalColor.rgb = adjustConstrast(finalColor.rgb, parameters.contrastIntensity);
        
    }
    
    if(parameters.saturationIntensity != 1.0) {
        
        finalColor.rgb = adjustSaturation(finalColor.rgb, parameters.saturationIntensity);
        
    }
    
    return finalColor;
    
}


vertex ScreenCoordinateOutput draw2DVertexFunction( ScreenCoordinateInput in [[stage_in]],
                                           ushort vid [[vertex_id]] )
{
    ScreenCoordinateOutput out;

    out.position = in.position;
    out.pointSize = 4.0;
    
    return out;
}

fragment float4 draw2DFragmentFunction(ScreenCoordinateOutput in [[stage_in]])
{
 
    return float4(0.0,1.0,0.0,1.0);
}

vertex SCNVertexOutput overlayQuadVertexFunction( ushort vid [[ vertex_id ]] ) {
    
    SCNVertexOutput out;
    
    out.position = quadPosition(vid);
    out.texCoord = quadTexCoord(vid);
    
    return out;
}

fragment float4 overlayQuadFragmentFunction( SCNVertexOutput in [[stage_in]],
                                                constant float* overlayTransparency [[ buffer(0) ]],
                                                texture2d<float, access::sample>  quadTexture [[ texture(0) ]]
                                               ) {
    
    constexpr sampler s(min_filter::linear, mag_filter::linear);
    float4 color =  quadTexture.sample(s, in.texCoord);
    
    if(color.a == 0.0) {
        discard_fragment();
    }
    
    color *= float(*overlayTransparency);
    
    return color;
    
}

