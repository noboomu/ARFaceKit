//
//  eyes.metal
//  FacioTest
//
//  Created by joshua bauer on 12/28/16.
//  Copyright © 2016 Wurrly. All rights reserved.
//

#include <metal_stdlib>
#include <metal_graphics>
#include <metal_texture>
#include <metal_matrix>
#include <metal_common>

using namespace metal;

#include <SceneKit/scn_metal>

typedef struct {
    float2 position  [[ attribute(0) ]];
    float2 texCoord  [[ attribute(1) ]];
} SCNVertexInput;

typedef struct
{
    ushort vid;
    float4 position [[position]];
    float2 texcoord;
    
} SCNVertexOutput;

vertex SCNVertexOutput eyesVertex(
                                device SCNVertexInput* vertices [[ buffer(0) ]],
                                ushort vid [[ vertex_id ]]
                                ) {
    ColorVaryings out;
    
    device SCNVertexInput& v = vertices[vid];
    
    float2 pos = v.position;
    
    out.position = float4(pos.x , pos.y ,0.0,   1.0);
    out.vid = vid;
    
    out.texcoord = v.texcoord;
    
    
    return out;
}


fragment float4 eyesFragment (
                              SCNVertexOutput in [[stage_in]],
                              texture2d<float, access::sample> eyeTexture [[texture(0)]]
                              ) {
    
    constexpr sampler sampler2d(coord::normalized, filter::nearest, mip_filter::nearest, address::clamp_to_edge);
    
    float4 color = eyeTexture.sample(sampler2d,float2( in.texcoord.x   ,  in.texcoord.y    ) );
    
    return color;
}
