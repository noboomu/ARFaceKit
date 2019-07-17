//
//  ShaderTypes.h
//  ARMetal
//
//  Created by joshua bauer on 3/7/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

//
//  Header containing types and enum constants shared between Metal shaders and C/ObjC source
//
#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>


// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API buffer set calls
typedef enum BufferIndices {
    kBufferIndexMeshPositions    = 0,
    kBufferIndexMeshGenerics     = 1,
    kBufferIndexInstanceUniforms = 2,
    kBufferIndexSharedUniforms   = 3
} BufferIndices;

typedef enum CompositeColorIndices {
    kCompositeColorIndexSource    = 0,
    kCompositeColorIndexComposite     = 1
} CompositeColorIndices;

typedef enum PostprocessParameterIndices {
    kLUTEnabled    = 0,
    kContrastEnabled     = 1,
    kSaturationEnabled     = 2
} PostprocessParameterIndices;

// Attribute index values shared between shader and C code to ensure Metal shader vertex
//   attribute indices match the Metal API vertex descriptor attribute indices
typedef enum VertexAttributes {
    kVertexAttributePosition  = 0,
    kVertexAttributeTexcoord  = 1,
    kVertexAttributeNormal    = 2
} VertexAttributes;

// Texture index values shared between shader and C code to ensure Metal shader texture indices
//   match indices of Metal API texture set calls
typedef enum TextureIndices {
    kTextureIndexColor    = 0,
    kTextureIndexY        = 1,
    kTextureIndexCbCr     = 2
} TextureIndices;

typedef struct {
    vector_float4 position;
    vector_float2 texCoord;
    vector_float2 screenTexCoord;
} VertexOutput;

typedef struct {
    float contrastIntensity;
    float saturationIntensity;
    float lutIntensity;
} ColorProcessingParameters;

// Structure shared between shader and C code to ensure the layout of shared uniform data accessed in
//    Metal shaders matches the layout of uniform data set in C code
typedef struct {
    // Camera Uniforms
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 viewMatrix;
    
    // Lighting Properties
    vector_float3 ambientLightColor;
    vector_float3 directionalLightDirection;
    vector_float3 directionalLightColor;
    float materialShininess;
} SharedUniforms;

typedef struct {
    unsigned int passIndex;
    float skinSmoothingFactor;
    vector_float2 renderSize;
    vector_float2 imageSize;
    vector_float2 inverseResolution;
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 modelViewProjectionMatrix;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 modelMatrix;
    
}  SmoothingParameters;

// Structure shared between shader and C code to ensure the layout of instance uniform data accessed in
//    Metal shaders matches the layout of uniform data set in C code
typedef struct {
    matrix_float4x4 modelMatrix;
} InstanceUniforms;



#endif /* ShaderTypes_h */
