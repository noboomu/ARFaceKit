//
//  Common.metal
//  ARMetal
//
//  Created by joshua bauer on 5/3/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

#ifndef ShaderCommon_h
#define ShaderCommon_h

#pragma once

#import <metal_stdlib>
#import <simd/simd.h>
 
using namespace metal;
using namespace simd;

#pragma MARK - Constants

constant float3 BT709_LUMA = float3(0.2126, 0.7152, 0.0722);

constant float3 CCIR_LUMA = float3(0.299, 0.587, 0.114);

constant float SMOOTHING_FACTOR = 0.5;

constant float TEETH_WHITENING_FACTOR = 0.1;

constant float HIGH_FREQUENCY_CONTRAST = SMOOTHING_FACTOR * 0.4;

constant float TEETH_CONTRAST_LOW = 1.0;

constant float TEETH_CONTRAST_HIGH = 1.5;

constant float teethContrastInternal = TEETH_WHITENING_FACTOR * (TEETH_CONTRAST_HIGH - TEETH_CONTRAST_LOW) + TEETH_CONTRAST_LOW;


#pragma MARK - Functions

inline float scaleValue(float value, float min, float max) {
    return value * ( max - min ) + min;
}


inline float cubicSCurve(float value) {
    return value * value * (3.0 - 2.0 * value);
}

inline float3 cubicSCurve(float3 value) {
    return value * value * (3.0 - 2.0 * value);
}

inline float3 cubicSCurve2(float3 value) {
    return -0.4014452027 * value * value + 1.401445203 * value;
}

inline float4 quadPosition(uint vid)
{
    return float4((vid % 2) * 2.0 - 1.0,(vid / 2) * 2.0 - 1.0,0,1.0);
}

inline float2 quadTexCoord(uint vid)
{
    return float2(vid % 2,1 - vid / 2);
}

inline float3 lumaBT709( float3 color )
{
    return dot(color, BT709_LUMA);
}

inline float lumaCCIR(float3 color) {
    return dot(CCIR_LUMA,color);
}

float4 hardLight(float4 sourceColor);

float4 brighten(float4 sourceColor, float4 targetColor);

half3 lookUpColor( texture3d<half> lutTexture, half3 sourceColor, half intensity );

float3 adjustConstrast( float3 sourceColor, float intensity );

float3 adjustSaturation( float3 sourceColor, float intensity );

float lumaHighPassFilter(float4 color, float4 mean, float threshold);

float3 colorAberration( texture2d<float, access::sample> texture, float2 texCoord, float intensity, float magnitude );


#endif
