//
//  RenderDestination.swift
//  ARMetal
//
//  Created by joshua bauer on 3/27/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

import Foundation
import Metal
import MetalKit

class RenderDestination: NSObject, RenderDestinationProvider {

    var renderPassDescriptor : MTLRenderPassDescriptor?
    var colorPixelFormat: MTLPixelFormat = MTLPixelFormat.bgra8Unorm
    var depthStencilPixelFormat: MTLPixelFormat = MTLPixelFormat.depth32Float_stencil8
    var sampleCount: Int = 1
    var viewport : CGRect!
    let device : MTLDevice!
    var depthStencilTexture : MTLTexture!
    var colorTexture : MTLTexture!
    
    init( device: MTLDevice, size : CGSize ) {
        
        
        self.viewport = CGRect(x: 0, y:0, width:size.width * UIScreen.main.scale, height: size.height * UIScreen.main.scale)
   
        self.device = device
        
        super.init()
        
        
    }
    
    var currentDrawable : CAMetalDrawable? {
        return nil
    }
    
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? {
        
  
        setupRenderPassDescriptor()
        
        return self.renderPassDescriptor
        
    }
    
    func setupRenderPassDescriptor() {
        
        if( self.renderPassDescriptor == nil ) {
            self.renderPassDescriptor = MTLRenderPassDescriptor()
        }
        
 

        if( self.sampleCount > 1 ) {
            
        }
        else {
            
            if( colorTexture == nil )
            {
                
                let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: self.colorPixelFormat, width: Int(self.viewport.width), height: Int(self.viewport.height), mipmapped: false)
                
                textureDescriptor.textureType = MTLTextureType.type2D
                textureDescriptor.sampleCount = self.sampleCount
                textureDescriptor.usage = MTLTextureUsage.renderTarget
                textureDescriptor.storageMode = MTLStorageMode.shared
                
                colorTexture = self.device.makeTexture(descriptor: textureDescriptor)
                
            }
            
            
            self.renderPassDescriptor!.colorAttachments[0].texture = colorTexture
            self.renderPassDescriptor!.colorAttachments[0].clearColor = MTLClearColorMake(0.65, 0.65, 0.65, 0.65)
            self.renderPassDescriptor!.colorAttachments[0].loadAction = MTLLoadAction.clear
            self.renderPassDescriptor!.colorAttachments[0].storeAction = MTLStoreAction.store
            
            if( depthStencilTexture == nil )
            {
                let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: self.depthStencilPixelFormat, width: Int(self.viewport.width), height: Int(self.viewport.height), mipmapped: false)
                
                textureDescriptor.textureType = MTLTextureType.type2D
                textureDescriptor.sampleCount = self.sampleCount
                textureDescriptor.usage = MTLTextureUsage(rawValue:MTLTextureUsage.shaderRead.rawValue  | MTLTextureUsage.shaderWrite.rawValue  | MTLTextureUsage.renderTarget.rawValue)
                depthStencilTexture = self.device.makeTexture(descriptor: textureDescriptor)
                
            }
            
            self.renderPassDescriptor!.depthAttachment.texture = depthStencilTexture
            self.renderPassDescriptor!.depthAttachment.loadAction = MTLLoadAction.clear
            self.renderPassDescriptor!.depthAttachment.storeAction = MTLStoreAction.dontCare
            self.renderPassDescriptor!.depthAttachment.clearDepth = 1.0
         
            
            self.renderPassDescriptor!.stencilAttachment.texture = depthStencilTexture
            self.renderPassDescriptor!.stencilAttachment.loadAction = MTLLoadAction.clear
            self.renderPassDescriptor!.stencilAttachment.storeAction = MTLStoreAction.dontCare
            self.renderPassDescriptor!.stencilAttachment.clearStencil = 0
            
         }
        
    }

    

}
