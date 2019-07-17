//
//  OpenCVWrapper.h
//  ARMetal
//
//  Created by joshua bauer on 4/4/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SceneKit/SceneKit.h>
#import <Metal/Metal.h>
 #import <simd/simd.h>

@interface OpenCVWrapper : NSObject


- (void) loadModels;

- (void) setIntrinsics:(simd_float4) cameraInstrinsics;

-(void) resetModels;

-(void) detectEyeLandmarks:(SCNNode *) node
                        leftTexture: (id<MTLTexture>) leftTexture
                         leftOffset:(simd_float2) leftOffset
                         leftBounds:(CGRect) leftBounds
                       rightTexture: (id<MTLTexture>) rightTexture
                        rightOffset:(simd_float2) rightOffset
                        rightBounds:(CGRect) rightBounds;

-(vector_float3) leftEyeCenter;
-(vector_float3) rightEyeCenter;
-(vector_float3) leftEyeGaze;
-(vector_float3) rightEyeGaze;
-(vector_float2) gaze;


@end
