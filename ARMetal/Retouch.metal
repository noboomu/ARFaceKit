//
//  SkinSmoothing.metal
//  ARMetal
//
//  Created by joshua bauer on 3/16/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

#include <metal_stdlib>
#include <simd/simd.h>
#import "ShaderCommon.h"

using namespace metal;

#include <SceneKit/scn_metal>


typedef struct {
    float3 position;
} Vertex;

typedef struct {
    float2 texCoord;
} TexCoord;

typedef struct {
    int passIndex;
} PassIndexParameter;


typedef struct {
    float3 position  [[ attribute(0) ]];
    float2 texCoord  [[ attribute(1) ]];
} SCNVertexInput;

typedef struct {
    float4 position [[position]];
    float2 texCoord;
} SCNVertexOutput;


typedef struct {
    uint passIndex;
    float skinSmoothingFactor;
    float2 renderSize;
    float2 imageSize;
    float2 inverseResolution;
    float4x4 projectionMatrix;
    float4x4 modelViewProjectionMatrix;
    float4x4 viewMatrix;
    float4x4 modelMatrix;
    
} SmoothingParameters;

typedef struct  {
    float4x4 modelTransform;
    float4x4 modelViewProjectionTransform;
} SCNNodeBuffer;


vertex SCNVertexOutput retouchVertexFunction( SCNVertexInput in [[ stage_in ]],
                                           constant SmoothingParameters& parameters [[buffer(2)]],
                                           ushort vid [[ vertex_id ]])
{
    
    
    SCNVertexOutput out;
    
    float4x4 modelMatrix = parameters.modelMatrix;
    float4x4 modelProjectionMatrix =  parameters.projectionMatrix * modelMatrix;
    
    out.position =  modelProjectionMatrix *  float4(in.position,1.) ;
    out.texCoord = in.texCoord;
    
    return out;
}

fragment float4 retouchFragmentFunction(SCNVertexOutput in [[stage_in]],
                                     texture2d<float, access::sample> cameraTexture [[ texture(0) ]],
                                     texture2d<float, access::sample> faceMask [[ texture(1) ]],
                                     texture2d<float, access::sample> passBuffer1 [[ texture(2) ]],
                                     texture2d<float, access::sample> passBuffer2 [[ texture(3) ]],
                                     texture2d<float, access::sample> passBuffer3 [[ texture(4) ]],
                                     texture2d<float, access::sample> passBuffer4 [[ texture(5) ]],
                            
                                     constant SmoothingParameters& parameters [[buffer(2)]]
                                     )
{
    
    
    constexpr sampler s(coord::normalized,filter::linear, address::clamp_to_edge);
    
    int i, j;
    
    float2 offset = float2(0.0,0.0);
    
    float2 coords = float2(in.position.xy*parameters.inverseResolution.xy-1.) ;
    
    float maxDimension = float(max(parameters.imageSize.x, parameters.imageSize.y));
    
    int smallKernelSize = int(0.0083 * maxDimension);
    
    float2 texCoord  = float2(  (1.0 + coords.x)  ,  1.0 + coords.y  );
    
    if(parameters.passIndex == 0)
    {
        
        float4 mean4;
        float2 duv = float2( 1.0 / parameters.imageSize );
        
        mean4 = float4(cameraTexture.sample( s, texCoord + float2( -duv.x, -duv.y )));
        mean4 += float4(cameraTexture.sample( s, texCoord + float2( duv.x, -duv.y )));
        mean4 += float4(cameraTexture.sample( s, texCoord + float2(-duv.x,  duv.y )));
        mean4 += float4(cameraTexture.sample( s, texCoord + float2( duv.x,  duv.y )));
        
        mean4 *= 0.25;
        
        return mean4;
    }
    
    else if(parameters.passIndex == 1)
    {

        return float4(passBuffer1.sample( s, texCoord ));
    }
    
    else if(parameters.passIndex == 2)
    {
        float smoothFactorInternal = SMOOTHING_FACTOR * 0.06;
        
        float epsilon = smoothFactorInternal * smoothFactorInternal;
        float2 duv = 4.0 / parameters.imageSize;
        float2 uv0 = texCoord - 0.5 * (float(smallKernelSize) - 1.0) * duv;
        float4 correlationIp = float4(0.0);
        float4 meanIp = float4(0.0);
        
        float weight = 1.0 / (float(smallKernelSize) * float(smallKernelSize));
        
        for (j = 0; j < smallKernelSize; j++)
        {
            offset.y = uv0.y + float(j) * duv.y;
            
            for (i = 0; i < smallKernelSize; i++)
            {
                offset.x = uv0.x + float(i) * duv.x;
                
                float4 tex = passBuffer2.sample( s, offset );
                
                meanIp += weight * tex;
                correlationIp += weight * tex * tex;
            }
        }
        
        float4 varianceIp = correlationIp - meanIp * meanIp;
        
        float3 a = varianceIp.xyz / (varianceIp.xyz + epsilon);

        return float4( a, 1.0);
    }
    else if(parameters.passIndex == 3)
    {
        
        float4 meanIp = float4(passBuffer2.sample( s, texCoord ));
        
        float4 a = float4(passBuffer3.sample( s, texCoord ));
        float3 b = meanIp.xyz - a.xyz * meanIp.xyz;
        
        return  float4(b, 1.0);
    }
    
    else if(parameters.passIndex == 4)
    {
        float4 meanA = float4(0.0);
        float2 duv = 4.0 / parameters.imageSize;
        float2 uv0 = texCoord - 0.5 * (float(smallKernelSize) - 1.0) * duv;
        
        for (j = 0; j < smallKernelSize; j++) {
            offset.y = uv0.y + float(j) * duv.y;
            
            for (i = 0; i < smallKernelSize; i++) {
                offset.x = uv0.x + float(i) * duv.x;
                meanA += passBuffer3.sample( s, offset );
            }
        }
        meanA /= float(smallKernelSize) * float(smallKernelSize);
        
        return meanA;
    }
    
    else if(parameters.passIndex == 5)
    {
        float4 meanB = float4(0.0);
        float2 duv = 4.0 / parameters.imageSize;
        float2 uv0 = texCoord - 0.5 * (float(smallKernelSize) - 1.0) * duv;

        for (j = 0; j < smallKernelSize; j++) {
            offset.y = uv0.y + float(j) * duv.y;

            for (i = 0; i < smallKernelSize; i++) {
                offset.x = uv0.x + float(i) * duv.x;

                meanB += passBuffer4.sample( s, offset );
            }
        }
        
        meanB /= float(smallKernelSize) * float(smallKernelSize);

        return float4(meanB);
    }
    
    else if(parameters.passIndex == 6)
    {
    
        float4 face = float4( faceMask.sample( s, in.texCoord ) );
        
        if(face.a < 1.0 || face.r < 0.9)
        {
            discard_fragment();
        }
        
        float4 base = float4(cameraTexture.sample( s, texCoord ));
        
        
        float4 meanA = float4( passBuffer2.sample( s, texCoord ));
        
        if(meanA.a < 1.0  )
        {
            discard_fragment();
        }
        
        float4 meanB = float4( passBuffer3.sample( s, texCoord ));
        
        float4 mean4 = float4( passBuffer1.sample( s, texCoord ));
        
        float4 smoothed = meanA * base + meanB;
        
        float4 difference = base - mean4;
   
        float4 outputColor = smoothed + HIGH_FREQUENCY_CONTRAST * difference;
        
        outputColor = mix(base, outputColor, face.x);
        
        /* TEETH WHITENING */
        /*
        // Up the contrast by multiplying by a factor
        float4 enhancedPix2 = outputPix * teethContrastInternal;
        // Increase the saturation so as to not brighten the lips so much
        float4 saturated = float4(mix(float3(0.5), outputPix.rgb, 1.05), 1.0);
        // Pass through the pixel values through a s-curve
        float lumaPix = scurve(rgb2luma(outputPix.rgb));
        // Use the s-curved values to weight the whites more
        float4 brigtenPix2 = mix(saturated, enhancedPix2, lumaPix);
        // Blend using lips mask
        outputPix = mix(outputPix, brigtenPix2, face.z);
         */
        

        return outputColor;

    }
    
    
    return float4(0.0,0.0,0.0,1.0);
    
}
