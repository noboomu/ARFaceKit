//
//  RenderPixelBufferConsumer.swift
//  ARMetal
//
//  Created by joshua bauer on 3/28/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

import Foundation

import Foundation
import CoreVideo
import CoreMedia

protocol RenderPixelBufferConsumer {
    func renderedOutput( didRender: CVPixelBuffer, atTime: CMTime )
    var renderCallbackQueue: DispatchQueue { get }
}


