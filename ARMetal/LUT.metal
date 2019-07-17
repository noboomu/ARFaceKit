//
//  lut.metal
//  ARMetal
//
//  Created by joshua bauer on 4/2/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;


kernel void lutKernel( texture2d<float, access::read_write> outputImage  [[texture(0)]],
                      texture2d<float, access::sample> inputLUT  [[texture(1)]],
                      constant float &intensity  [[buffer(0)]],
                      uint2 gid [[thread_position_in_grid]]) {
    
    constexpr sampler s(coord::normalized,address::clamp_to_zero, filter::linear);
    
    float4 textureColor = outputImage.read(gid);
  //  textureColor = clamp(textureColor, float4(0.0), float4(1.0));
    
    float blueColor = textureColor.b * 63.0;
    
    float2 quad1;
    quad1.y = floor(floor(blueColor) / 8.0);
    quad1.x = floor(blueColor) - (quad1.y * 8.0);
    
    float2 quad2;
    quad2.y = floor(ceil(blueColor) / 8.0);
    quad2.x = ceil(blueColor) - (quad2.y * 8.0);
    
    float2 texPos1;
    texPos1.x = (quad1.x * 0.125) + .0001 + (.12134 * textureColor.r);
    texPos1.y = (quad1.y * 0.125) + .0001 + (.12134 * textureColor.g);
    
    float2 texPos2;
    texPos2.x = (quad2.x * 0.125) + .0001 + (.12134 * textureColor.r);
    texPos2.y = (quad2.y * 0.125) + .0001 + (.12134 * textureColor.g);
 
    
    float4 newColor1 = inputLUT.sample(s, texPos1  );
    float4 newColor2 = inputLUT.sample(s, texPos2  );
    
    float4 newColor = mix(newColor1, newColor2, fract(blueColor));
    
    float4  newColor4 = mix(textureColor, float4(newColor.rgb, textureColor.w), intensity);
    
    outputImage.write(newColor4,gid);
}
