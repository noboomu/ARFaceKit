//
//  RenderDestinationProvider.swift
//  ARMetal
//
//  Created by joshua bauer on 3/27/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

import Foundation
import Metal
import MetalKit

protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    var depthStencilPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
}

extension MTKView : RenderDestinationProvider {
}
