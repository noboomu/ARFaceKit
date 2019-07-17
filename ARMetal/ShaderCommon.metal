//
//  ShaderCommon.metal
//  ARMetal
//
//  Created by joshua bauer on 5/3/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

#include <metal_stdlib>
#include "ShaderCommon.h"


half3 lookUpColor( texture3d<half> lutTexture, half3 sourceColor, half intensity )
{
    constexpr sampler s(min_filter::linear, mag_filter::linear, address::clamp_to_edge);
    
    half3 lutColor = lutTexture.sample(s, float3(sourceColor)).rgb;
    return mix(sourceColor, lutColor, intensity);
}

float3 adjustConstrast( float3 sourceColor, float intensity )
{
    float3 saturatedColor = saturate(sourceColor);
    return saturatedColor - intensity * (saturatedColor - 1.0) * saturatedColor * (saturatedColor - 0.5);
}

float3 adjustSaturation( float3 sourceColor, float intensity )
{
    float3 lum = lumaBT709(sourceColor);
    return mix(lum, sourceColor, intensity);
}

float4 brighten(float4 sourceColor, float4 targetColor)
{
    float lumaColor = cubicSCurve(lumaCCIR(sourceColor.rgb));
    return float4(mix( float4(sourceColor), float4(targetColor),  float(lumaColor)));
}

float4 hardLight(float4 sourceColor)
{
    float color = sourceColor.b;
    int i = 0;
    
    for(i = 0; i < 3; i++)
    {
        if(color <= 0.5) {
            color = color * color * 2.0;
        }
        else
        {
            color = 1.0 - ((1.0 - color)*(1.0 - color) * 2.0);
        }
    }
    return float4(float3(color), sourceColor.a);
}

float lumaHighPassFilter(float4 color, float4 mean, float threshold)
{
    float delta = lumaCCIR(color.xyz - mean.xyz);
    float highpass = clamp((delta + threshold) / (2.0 * threshold), 0.0, 1.0);
    highpass = cubicSCurve(highpass);
    highpass = 2.0 * abs(highpass - 0.5);
    
    return highpass;
}

float3 colorAberration( texture2d<float, access::sample> texture, float2 texCoord, float intensity, float offset )
{
    constexpr sampler s(filter::linear);
    
    float4 color = texture.sample(s, texCoord);
    
    float colorAberration = length_squared(texCoord - 0.5) * offset;
    
    float3 shift = float3(16.0 / texture.get_width(), 0.0, -16.0 / texture.get_width()) * colorAberration;
    
    float3 aberrationColor = color.rgb;
    
    aberrationColor.r = texture.sample(s, texCoord + float2( shift.r, 0) ).r;
    
    aberrationColor.b = texture.sample(s, texCoord + float2( shift.b, 0) ).b;
    
    return mix(color.rgb, aberrationColor, intensity);
}

