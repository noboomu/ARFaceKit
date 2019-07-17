//
//  Renderer.swift
//  ARMetal
//
//  Created by joshua bauer on 3/7/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

import Foundation
import Metal
import MetalKit
import ARKit
import SceneKit
import SpriteKit
import CoreVideo
import CoreImage
import MetalPerformanceShaders
import CoreGraphics


let kMaxBuffersInFlight: Int = 3

let kSkinSmoothingFactor : Float = 0.6

let kSmoothingPasses: Int = 6

let kFaceIndexCount : Int = 2304 * 3

let smoothingPassSizes : [CGFloat] = [1.0,0.25,0.2,0.2,0.2]

let smoothingPassInstructions : [(Int, Bool)] = [ (1,true), (2,true), (3,true), (4,true), (2, false), (3,false), (0,true) ]

let kAlignedSharedUniformsSize: Int = (MemoryLayout<SharedUniforms>.size & ~0xFF) + 0x100

let kImagePlaneVertexData: [Float] = [
    -1.0, -1.0,  0.0, 1.0,
    1.0, -1.0,  1.0, 1.0,
    -1.0,  1.0,  0.0, 0.0,
    1.0,  1.0,  1.0, 0.0,
]

let kOpenessThreshold : Float = 0.0052

let kLeftEyeIndexRange = 1061...1084

let kLeftEyeTriangles: [Int] = [

    1070, 1068, 1069,
    1071, 1067, 1068,
    1071, 1068, 1070,
    1072, 1066, 1067,
    1072, 1067, 1071,
    1073, 1066, 1072,
    1073, 1065, 1066,
    1074, 1064, 1065,
    1074, 1065, 1073,
    1075, 1063, 1064,
    1075, 1064, 1074,
    1076, 1063, 1075,
    1076, 1062, 1063,
    1077, 1061, 1062,
    1077, 1062, 1076,
    1078, 1084, 1061,
    1078, 1061, 1077,
    1079, 1083, 1084,
    1079, 1084, 1078,
    1080, 1082, 1083,
    1080, 1083, 1079,
    1080, 1081, 1082

]

let kRightEyeBoundsVertices: [Int] = [
    
    1101,
    1108,
    1089,
    1094
]

let kLeftEyeBoundsVertices: [Int] = [
    
    1081,
    1062,
    1069,
    1076
]


let kRightEyeTriangles: [Int] = [
    
    1100, 1101, 1102,
    1100, 1102, 1103,
    1099, 1100, 1103,
    1098, 1099, 1103,
    1098, 1103, 1104,
    1098, 1104, 1105,
    1097, 1098, 1105,
    1097, 1105, 1106,
    1096, 1097, 1106,
    1096, 1106, 1107,
    1095, 1096, 1107,
    1095, 1107, 1108,
    1094, 1095, 1108,
    1094, 1108, 1085,
    1093, 1094, 1085,
    1093, 1085, 1086,
    1092, 1093, 1086,
    1092, 1086, 1087,
    1091, 1092, 1087,
    1091, 1087, 1088,
    1090, 1091, 1088,
    1090, 1088, 1089
    
]


let kEyeOpenReferenceIndices : [Eye: [Int]] = [ Eye.left: [1076,1062], Eye.right: [1094,1108] ]

struct CameraInstrinsics {
    var fx : Float = 0.0
    var fy : Float = 0.0
    var cx : Float = 0.0
    var cy : Float = 0.0
}

class Renderer : NSObject, ARSessionDelegate {
    
    let session: ARSession

    var sceneRenderer: SCNRenderer
    
    var isSwappingMasks : Bool = false
    
    let ciContext: CIContext
    
    var viewport : CGRect = CGRect(x: 0, y: 0, width: 1125, height: 2436)

    var viewportSize: CGSize = CGSize()

    let inFlightSemaphore = DispatchSemaphore(value: kMaxBuffersInFlight)
    
    var renderDestination: RenderDestinationProvider
    
    var pixelBufferConsumer: RenderPixelBufferConsumer?
    
    var outputPixelBufferAttributes : [String : Any]?
    
    var isTracking : Bool = false
    
    var viewportSizeDidChange: Bool = false
    
    var pointOfViewConfigured: Bool = false
    
    var faceGeometry : ARFaceGeometry?
    
    var lastCamera : ARCamera?
    
    var worldAnchor : ARAnchor?
    
    var worldAnchorUUID : UUID?
    
    // MARK: Nodes
    
    let scene: SCNScene
    
    var worldNode : SCNNode?
    
    let cameraNode: SCNNode
    
    let lightNode : SCNNode!
    
    let ambientLightNode : SCNNode!
    
    var lastFaceTransform : matrix_float4x4?
 
    
    // MARK: Metal
    
    let device: MTLDevice
    
    var commandQueue: MTLCommandQueue!
    
    var sharedUniformBuffer: MTLBuffer!
    var anchorUniformBuffer: MTLBuffer!
    var imagePlaneVertexBuffer: MTLBuffer!
    
    var faceVertexBuffer: MTLBuffer!
    var faceTexCoordBuffer: MTLBuffer!
    var faceIndexBuffer: MTLBuffer!
    
    var leftEyeTextureBuffer: MTLBuffer!
    var rightEyeTextureBuffer: MTLBuffer!
    
    var leftEyeBounds: CGRect = CGRect.zero

    var rightEyeBounds: CGRect = CGRect.zero

    var eyeStates : [Eye:EyeState] = [Eye.left: EyeState.unknown, Eye.right: EyeState.unknown]

    var eyeOpeness : [Eye:Float] = [Eye.left: -1.0, Eye.right: -1.0]
    
    var smoothingParametersBuffer: MTLBuffer!
    
    var capturedImagePipelineState: MTLRenderPipelineState!
    var capturedImageDepthState: MTLDepthStencilState!
    
    var cvPipelineState: MTLRenderPipelineState!
    
    var skinSmoothingPipelineState: MTLRenderPipelineState!
    
    var skinSmoothingDepthState: MTLDepthStencilState!
    
    var lutComputePipelineState: MTLComputePipelineState!

    var compositePipelineState: MTLRenderPipelineState!

    var colorProcessingPipelineState: MTLRenderPipelineState!

    var draw2DPipelineState: MTLRenderPipelineState!

    var scenePipelineState: MTLRenderPipelineState!
    
    var capturedImageTextureY: CVMetalTexture?
    var capturedImageTextureCbCr: CVMetalTexture?
    
    var capturedImageRenderTextureBuffer : MTLTexture!
    
    var skinSmoothingTextureBuffers: [MTLTexture]!
    var skinSmoothingDepthBuffer: MTLTexture!

    var textureLoader : MTKTextureLoader!
    
    var faceMaskTexture : MTLTexture!
 
    // Captured image texture cache
    var capturedImageTextureCache: CVMetalTextureCache!
    
    var pixelBufferPool : CVPixelBufferPool?
    
    var outputFormatDescriptor : CMFormatDescription?
    
    var colorSpace : CGColorSpace?

    var geometryVertexDescriptor: MTLVertexDescriptor!

    var uniformBufferIndex: Int = 0
    
    var smoothingBufferIndex: Int = 0

    // Offset within _sharedUniformBuffer to set for the current frame
    var sharedUniformBufferOffset: Int = 0
    
    // Offset within _anchorUniformBuffer to set for the current frame
    var anchorUniformBufferOffset: Int = 0
    
    var smoothingParameterBufferOffset: Int = 0
    
    // Addresses to write shared uniforms to each frame
    var sharedUniformBufferAddress: UnsafeMutableRawPointer!
    
    // Addresses to write anchor uniforms to each frame
    var anchorUniformBufferAddress: UnsafeMutableRawPointer!
    
    var smoothingParametersBufferAddress: UnsafeMutableRawPointer!
    
    var colorProcessingParameters : ColorProcessingParameters!
    
    var cameraInstrinsics: CameraInstrinsics?

    var lastPixelBuffer: CVPixelBuffer?

    var lastTimestamp : TimeInterval?
    
    let openCVWrapper = OpenCVWrapper()
    
    var alternateFaceUVSource : SCNGeometrySource?
    
    var alternateFaceUVSourceCoords : [float2] = [float2]()
    
    var faceContentNode: VirtualFaceNode? {
        willSet(newfaceContentNode) {
            
           isSwappingMasks = true
           self.faceContentNode?.isHidden = true
          

         }
        
        didSet {
            
            DispatchQueue.main.async {
                
               // self.worldNode?.removeFromParentNode()
                oldValue?.removeFromParentNode()
                
            }
            
            self.worldNode?.isHidden = true
            self.faceContentNode?.isHidden = true
          //   self.faceContentNode?.opacity = 0.0
            
           /// self.worldNode = nil
            
 
//            if let anchor = self.worldAnchor  {
//            self.session.remove(anchor: anchor)
//            }
            
            if self.faceContentNode != nil  {
                
               // var nodes = [SCNNode]()
                
//               if let texCoordSource = self.faceContentNode!.geometry?.sources( for: SCNGeometrySource.Semantic.texcoord ) {
//                    
//                    print("found tex coords")
//                    
//                }
               
                
                
                
                if let overlayScene = self.faceContentNode?.overlaySKScene  {
                    self.sceneRenderer.overlaySKScene = overlayScene
                    self.sceneRenderer.overlaySKScene!.scaleMode = .aspectFill
                    
                } else {
                    self.sceneRenderer.overlaySKScene = nil
                }
                
                self.colorProcessingParameters = self.faceContentNode?.colorParameters

                 
                if let worldNode = self.faceContentNode?.worldNode {
                    
                    
                    
//                    if  self.worldAnchor == nil {
//
//                        self.worldAnchor = ARAnchor(transform: matrix_identity_float4x4)
//
//                        self.worldAnchorUUID = self.worldAnchor?.identifier
//
//                        self.session.add(anchor: self.worldAnchor!)
//                    }
                    //self.session.add(anchor: self.worldAnchor!)
                    
                   // nodes.append(self.worldNode!)
                    
                    if self.worldNode != nil {
                        self.scene.rootNode.replaceChildNode(self.worldNode!, with: worldNode)
                    } else {
                        self.scene.rootNode.addChildNode(worldNode)
                    }
                    
                    self.worldNode = worldNode
                    
                    // self.scene.rootNode.addChildNode(self.worldNode!)
                    
                }
                
                //self.faceContentNode?.opacity = 0.0
                
               // nodes.append(self.faceContentNode!)
                
                 self.scene.rootNode.addChildNode(self.faceContentNode!)
//                for node in nodes {
//                    self.scene.rootNode.addChildNode(node)
//
//                }
                
                
//                sceneRenderer.prepare(nodes, completionHandler: { (result) in
//
//                    for node in nodes {
//                        self.scene.rootNode.addChildNode(node)
//
//                    }
//
//                })
             }
            
            self.updateTextures()
            
            self.faceContentNode?.loadSpecialMaterials()
            
           isSwappingMasks = false
            
            self.faceContentNode?.isHidden = false

            
        }
    }

    // MARK: Functionality
    
    init(session: ARSession, metalDevice device: MTLDevice, renderDestination: RenderDestinationProvider, sceneKitScene scene: SCNScene ) {
        
 
        self.session = session
        self.device = device
        self.ciContext = CIContext(mtlDevice:self.device)
        
        self.textureLoader = MTKTextureLoader(device: device)
        self.renderDestination = renderDestination
        self.scene = scene
        
        self.sceneRenderer = SCNRenderer(device: self.device, options: nil)
        self.sceneRenderer.autoenablesDefaultLighting = false
        self.sceneRenderer.isPlaying = true
        self.sceneRenderer.scene = self.scene
     
        let light = SCNLight()
        light.type = .directional
        light.color = UIColor.lightGray
        light.intensity = 1000
        
        self.lightNode = SCNNode()
        
        self.lightNode.light = light
        
        self.lightNode.position = SCNVector3Make(5.0, 5.0, 5.0)
        
        self.scene.rootNode.addChildNode(lightNode)
        
        
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor.white
        ambientLight.intensity = 1000
        
        self.ambientLightNode = SCNNode()
        
        self.ambientLightNode.light = light
        
        self.ambientLightNode.position = SCNVector3Make(0.0, 5.0, 0)
        
        self.scene.rootNode.addChildNode(self.ambientLightNode)

        
        self.cameraNode = SCNNode()

        self.cameraNode.camera = SCNCamera()
        
        self.scene.rootNode.addChildNode(self.cameraNode)
        self.sceneRenderer.pointOfView = self.cameraNode
        
        self.colorProcessingParameters = ColorProcessingParameters()
        
        self.worldAnchor = ARAnchor(transform: matrix_identity_float4x4)
        
        self.worldAnchorUUID = self.worldAnchor!.identifier
        
        self.session.add(anchor: self.worldAnchor!)
        
        if let uvPath = Bundle.main.url(forResource: "daz3duv", withExtension: "plist", subdirectory: nil) {
            
            let allValues =  NSArray(contentsOfFile: uvPath.path) as? [Float]
            
            var newUVCoords = [CGPoint]()
            
            let pairs = allValues!.count/2
            
            for i in 0..<pairs {
                
                let offset = i * 2
                let x = allValues![offset]
                let y = allValues![offset+1]
                
                alternateFaceUVSourceCoords.append(float2(x:x,y:y))
                
                newUVCoords.append(CGPoint(x:CGFloat(x),y:CGFloat(y)))
            }
            
            self.alternateFaceUVSource = SCNGeometrySource(textureCoordinates:newUVCoords)
        }
     
        super.init()
 
        openCVWrapper.loadModels()
        
        loadMetal()
        loadAssets()
        
    
    }
    
    func drawRectResized(size: CGSize) {
        viewportSize = size
        viewport = CGRect(x: 0, y:0, width:size.width  , height: size.height )
        viewportSizeDidChange = true
        configurePointOfView()
 
    }
    
    func configurePointOfView()
    {
        sceneRenderer.pointOfView?.camera?.focalLength = 20.784610748291
        sceneRenderer.pointOfView?.camera?.sensorHeight = 24.0
        sceneRenderer.pointOfView?.camera?.fieldOfView = 60
        
        
        
        var newMatrix = SCNMatrix4Identity
        newMatrix.m11 = 3.223367
        newMatrix.m22 = 1.48860991
        newMatrix.m31 = 0.000830888748
        newMatrix.m32 = -0.00301241875
        newMatrix.m33 = -1.00000191
        newMatrix.m34 = -1.0
        newMatrix.m41 = 0.0
        newMatrix.m42 = 0.0
        newMatrix.m43 = -0.00200000196
        newMatrix.m44 = 0.0
        
       
        
        sceneRenderer.pointOfView?.camera?.projectionTransform = newMatrix
        
        var simdMatrix = matrix_float4x4()
        simdMatrix.columns.0 = float4(1, 0, 0, 0.0)
        simdMatrix.columns.1 = float4(0, 1, 0, 0.0)
        simdMatrix.columns.2 = float4(0, 0, 1, 0.0)
        simdMatrix.columns.3 = float4(0.0, 0.0, 0.0, 1.0)
        
        sceneRenderer.pointOfView?.simdTransform = simdMatrix
        
        sceneRenderer.pointOfView?.camera?.focalLength = 20.784610748291
        sceneRenderer.pointOfView?.camera?.sensorHeight = 24.0
        sceneRenderer.pointOfView?.camera?.fieldOfView = 60
        
        sceneRenderer.pointOfView?.camera?.automaticallyAdjustsZRange = true

 
        
        pointOfViewConfigured = true
    }
    
    
    func positionFromTransform(_ transform: matrix_float4x4) -> SCNVector3 {
        return SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
    
    
    // MARK: - Setup
    
    func loadMetal() {
        
        
        
        
        // Create and load our basic Metal state objects
        
        // Set the default formats needed to render
        renderDestination.depthStencilPixelFormat = .depth32Float_stencil8
        renderDestination.colorPixelFormat = .bgra8Unorm
        renderDestination.sampleCount = 1
        
        // Calculate our uniform buffer sizes. We allocate kMaxBuffersInFlight instances for uniform
        //   storage in a single buffer. This allows us to update uniforms in a ring (i.e. triple
        //   buffer the uniforms) so that the GPU reads from one slot in the ring wil the CPU writes
        //   to another. Anchor uniforms should be specified with a max instance count for instancing.
        //   Also uniform storage must be aligned (to 256 bytes) to meet the requirements to be an
        //   argument in the constant address space of our shading functions.
        let sharedUniformBufferSize = kAlignedSharedUniformsSize * kMaxBuffersInFlight
      //  let anchorUniformBufferSize = kAlignedInstanceUniformsSize * kMaxBuffersInFlight

        // Create and allocate our         let anchorUniformBufferSize = kAlignedInstanceUniformsSize * kMaxBuffersInFlight
       // uniform buffer objects. Indicate shared storage so that both the
        //   CPU can access the buffer
        sharedUniformBuffer = device.makeBuffer(length: sharedUniformBufferSize, options: .storageModeShared)
        sharedUniformBuffer.label = "SharedUniformBuffer"
        
//        anchorUniformBuffer = device.makeBuffer(length: anchorUniformBufferSize, options: .storageModeShared)
//        anchorUniformBuffer.label = "AnchorUniformBuffer"
        
      
        // Create a vertex buffer with our image plane vertex data.
        let imagePlaneVertexDataCount = kImagePlaneVertexData.count * MemoryLayout<Float>.size
        imagePlaneVertexBuffer = device.makeBuffer(bytes: kImagePlaneVertexData, length: imagePlaneVertexDataCount, options: [])
        imagePlaneVertexBuffer.label = "ImagePlaneVertexBuffer"
        
    
        // Load all the shader files with a metal file extension in the project
        let defaultLibrary = device.makeDefaultLibrary()!
        
        let capturedImageVertexFunction = defaultLibrary.makeFunction(name: "capturedImageVertexFunction")!
        let capturedImageFragmentFunction = defaultLibrary.makeFunction(name: "capturedImageFragmentFunction")!
        
        let cvImageVertexFunction = defaultLibrary.makeFunction(name: "cvVertexFunction")!
        let cvImageFragmentFunction = defaultLibrary.makeFunction(name: "cvFragmentFunction")!
        
//        let lutVertexFunction = defaultLibrary.makeFunction(name: "lutVertexFunction")!
//        let lutFragmentFunction = defaultLibrary.makeFunction(name: "lutFragmentFunction")!
        
        let compositeVertexFunction = defaultLibrary.makeFunction(name: "compositeVertexFunction")!
        
        let compositeFragmentFunction = defaultLibrary.makeFunction(name: "compositeFragmentFunction")
        
        let draw2DVertexFunction = defaultLibrary.makeFunction(name: "draw2DVertexFunction")!
        let draw2DFragmentFunction = defaultLibrary.makeFunction(name: "draw2DFragmentFunction")!
        
        let colorProcessingVertexFunction = defaultLibrary.makeFunction(name: "colorProcessingVertexFunction")!
        let colorProcessingFragmentFunction = defaultLibrary.makeFunction(name: "colorProcessingFragmentFunction")!
        
        let  lutKernelFunction = defaultLibrary.makeFunction(name: "lutKernel" )


        // Create a vertex descriptor for our image plane vertex buffer
        let imagePlaneVertexDescriptor = MTLVertexDescriptor()
        
        // Positions.
        imagePlaneVertexDescriptor.attributes[0].format = .float2
        imagePlaneVertexDescriptor.attributes[0].offset = 0
        imagePlaneVertexDescriptor.attributes[0].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Texture coordinates.
        imagePlaneVertexDescriptor.attributes[1].format = .float2
        imagePlaneVertexDescriptor.attributes[1].offset = 8
        imagePlaneVertexDescriptor.attributes[1].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Buffer Layout
        imagePlaneVertexDescriptor.layouts[0].stride = 16
        imagePlaneVertexDescriptor.layouts[0].stepRate = 1
        imagePlaneVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Create a pipeline state for rendering the captured image
        let capturedImagePipelineStateDescriptor = MTLRenderPipelineDescriptor()
        capturedImagePipelineStateDescriptor.label = "CapturedImagePipeline"
        capturedImagePipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        capturedImagePipelineStateDescriptor.vertexFunction = capturedImageVertexFunction
        capturedImagePipelineStateDescriptor.fragmentFunction = capturedImageFragmentFunction
        capturedImagePipelineStateDescriptor.vertexDescriptor = imagePlaneVertexDescriptor
        capturedImagePipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        capturedImagePipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        capturedImagePipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        
        
        do {
            try capturedImagePipelineState = device.makeRenderPipelineState(descriptor: capturedImagePipelineStateDescriptor)
        } catch let error {
            print("Failed to created captured image pipeline state, error \(error)")
        }
        
        let capturedImageDepthStateDescriptor = MTLDepthStencilDescriptor()
        capturedImageDepthStateDescriptor.depthCompareFunction = .always
        capturedImageDepthStateDescriptor.isDepthWriteEnabled = false
        capturedImageDepthState = device.makeDepthStencilState(descriptor: capturedImageDepthStateDescriptor)
        
        // Create captured image texture cache
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        capturedImageTextureCache = textureCache
        
        
        let cvPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        cvPipelineStateDescriptor.label = "CVImagePipeline"
        cvPipelineStateDescriptor.sampleCount = 1
        cvPipelineStateDescriptor.vertexFunction = cvImageVertexFunction
        cvPipelineStateDescriptor.fragmentFunction = cvImageFragmentFunction
        cvPipelineStateDescriptor.vertexDescriptor = imagePlaneVertexDescriptor
        cvPipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            try cvPipelineState = device.makeRenderPipelineState(descriptor: cvPipelineStateDescriptor)
        } catch let error {
            print("Failed to created captured image pipeline state, error \(error)")
        }
        
        
        let draw2DVertexDescriptor = MTLVertexDescriptor()
        
        // Positions.
        draw2DVertexDescriptor.attributes[0].format = .float4
        draw2DVertexDescriptor.attributes[0].offset = 0
        draw2DVertexDescriptor.attributes[0].bufferIndex = 0
        
        
        // Buffer Layout
        draw2DVertexDescriptor.layouts[0].stride = 16
        draw2DVertexDescriptor.layouts[0].stepRate = 1
        draw2DVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Create a pipeline state for rendering the captured image
        let draw2DPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        draw2DPipelineStateDescriptor.label = "2DImagePipeline"
        draw2DPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        draw2DPipelineStateDescriptor.vertexFunction = draw2DVertexFunction
        draw2DPipelineStateDescriptor.fragmentFunction = draw2DFragmentFunction
        draw2DPipelineStateDescriptor.vertexDescriptor = draw2DVertexDescriptor
        draw2DPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat


        do {
            try draw2DPipelineState = device.makeRenderPipelineState(descriptor: draw2DPipelineStateDescriptor)
        } catch let error {
            print("Failed to create 2d image pipeline state, error \(error)")
        }

 
        let colorProcessingPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        colorProcessingPipelineStateDescriptor.label = "ColorProcessingPipelineState"
        colorProcessingPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        colorProcessingPipelineStateDescriptor.vertexFunction = colorProcessingVertexFunction
        colorProcessingPipelineStateDescriptor.fragmentFunction = colorProcessingFragmentFunction
        colorProcessingPipelineStateDescriptor.vertexDescriptor = imagePlaneVertexDescriptor

        colorProcessingPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        colorProcessingPipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = false
        
//            colorProcessingPipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperation.add
//            colorProcessingPipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperation.add
//            colorProcessingPipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactor.one
//            colorProcessingPipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactor.sourceAlpha
//            colorProcessingPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
//            colorProcessingPipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactor.oneMinusSourceAlpha

//        colorProcessingPipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactor.one
//        colorProcessingPipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactor.one
//        colorProcessingPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
//        colorProcessingPipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactor.destinationAlpha
        
        do {
            try colorProcessingPipelineState = device.makeRenderPipelineState(descriptor: colorProcessingPipelineStateDescriptor)
        } catch let error {
            print("Failed to create overlay image pipeline state, error \(error)")
        }
        
        
        // Create a pipeline state for rendering the captured image
        let compositePipelineStateDescriptor = MTLRenderPipelineDescriptor()
        compositePipelineStateDescriptor.label = "CompositeImagePipeline"
        compositePipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        compositePipelineStateDescriptor.vertexFunction = compositeVertexFunction
        compositePipelineStateDescriptor.fragmentFunction = compositeFragmentFunction
        compositePipelineStateDescriptor.vertexDescriptor = imagePlaneVertexDescriptor
        compositePipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
       // compositePipelineStateDescriptor.colorAttachments[1].pixelFormat = renderDestination.colorPixelFormat
        //compositePipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = false

        do {
            try compositePipelineState = device.makeRenderPipelineState(descriptor: compositePipelineStateDescriptor)
        } catch let error {
            print("Failed to created captured image pipeline state, error \(error)")
        }
        
        
  
        let textureUrl = Bundle.main.url(forResource: "SkinSmoothingTexture", withExtension: "png", subdirectory: "Models.scnassets")
        
        do {
            try faceMaskTexture = textureLoader.newTexture(URL: textureUrl!, options: nil)
        } catch let error {
            print("Failed to created captured image pipeline state, error \(error)")
            faceMaskTexture = nil
        }
        
        
        let faceVertexDataCount = 1220 * MemoryLayout<float4>.size
        faceVertexBuffer = device.makeBuffer(length: faceVertexDataCount, options: .storageModeShared)
        faceVertexBuffer.label = "faceVertexBuffer"
        
        let faceTexCoordCount = 1220 *  MemoryLayout<float2>.size
        faceTexCoordBuffer = device.makeBuffer(length: faceTexCoordCount, options: .storageModeShared)
        faceTexCoordBuffer.label = "faceTexCoordBuffer"
        
        let faceIndexCount = kFaceIndexCount *  MemoryLayout<UInt16>.size
        faceIndexBuffer = device.makeBuffer(length: faceIndexCount, options: .storageModeShared)
        faceIndexBuffer.label = "faceIndexBuffer"
        
        leftEyeTextureBuffer = device.makeBuffer(length: 1280 * 720 * 4,  options: .storageModeShared)
        leftEyeTextureBuffer.label = "leftEyeTextureBuffer"

        rightEyeTextureBuffer = device.makeBuffer(length: 1280 * 720 * 4,  options: .storageModeShared)
        rightEyeTextureBuffer.label = "rightEyeTextureBuffer"
     
        geometryVertexDescriptor = MTLVertexDescriptor()

        geometryVertexDescriptor.attributes[0].format = .float3
        geometryVertexDescriptor.attributes[0].offset = 0
        geometryVertexDescriptor.attributes[0].bufferIndex = 0

        geometryVertexDescriptor.attributes[1].format = .float2
        geometryVertexDescriptor.attributes[1].offset = 0
        geometryVertexDescriptor.attributes[1].bufferIndex = 1
        
        geometryVertexDescriptor.layouts[0].stride = 16
        geometryVertexDescriptor.layouts[0].stepRate = 1
        geometryVertexDescriptor.layouts[0].stepFunction = .perVertex

        geometryVertexDescriptor.layouts[1].stride = 8
        geometryVertexDescriptor.layouts[1].stepRate = 1
        geometryVertexDescriptor.layouts[1].stepFunction = .perVertex

        
        let skinSmoothingVertexFunction = defaultLibrary.makeFunction(name: "retouchVertexFunction")!
        let skinSmoothingFragmentFunction = defaultLibrary.makeFunction(name: "retouchFragmentFunction")!
        
        // Create a reusable pipeline state for rendering anchor geometry
        let skinSmoothingPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        skinSmoothingPipelineStateDescriptor.label = "SkinSmoothingPipeline"
        skinSmoothingPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        skinSmoothingPipelineStateDescriptor.vertexDescriptor = geometryVertexDescriptor
        skinSmoothingPipelineStateDescriptor.vertexFunction = skinSmoothingVertexFunction
        skinSmoothingPipelineStateDescriptor.fragmentFunction = skinSmoothingFragmentFunction
        skinSmoothingPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        skinSmoothingPipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = false
//        skinSmoothingPipelineStateDescriptor.depthAttachmentPixelFormat = MTLPixelFormat.depth32Float_stencil8
//        skinSmoothingPipelineStateDescriptor.stencilAttachmentPixelFormat = MTLPixelFormat.depth32Float_stencil8

//        skinSmoothingPipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperation.add
//        skinSmoothingPipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperation.add
//        skinSmoothingPipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactor.one
//        skinSmoothingPipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactor.one
//        skinSmoothingPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactor.zero
//        skinSmoothingPipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactor.zero
        
        do {
            try skinSmoothingPipelineState = device.makeRenderPipelineState(descriptor: skinSmoothingPipelineStateDescriptor)
        } catch let error {
            print("Failed to created anchor geometry pipeline state, error \(error)")
        }
        
         do {
            try lutComputePipelineState = device.makeComputePipelineState(function: lutKernelFunction!)
         } catch let error {
            print("Failed to created lut compute kernel function, error \(error)")
        }
        
//        let skinSmoothingStencilStateDescriptor = MTLStencilDescriptor()
//        skinSmoothingStencilStateDescriptor.writeMask = 0xFF
//        skinSmoothingStencilStateDescriptor.stencilCompareFunction = .always
//       let skinSmoothingDepthStateDescriptor = MTLDepthStencilDescriptor()
////        skinSmoothingDepthStateDescriptor.depthCompareFunction = .always
//        skinSmoothingDepthStateDescriptor.isDepthWriteEnabled = true
////        skinSmoothingDepthStateDescriptor.frontFaceStencil = skinSmoothingStencilStateDescriptor
////        skinSmoothingDepthStateDescriptor.backFaceStencil = skinSmoothingStencilStateDescriptor
////
//         skinSmoothingDepthState = device.makeDepthStencilState(descriptor: skinSmoothingDepthStateDescriptor)
////
        
        updateTextures()
        
       // self.sobelFilter = MPSImageSobel(device:self.device)
      
        
        // Create the command queue
        commandQueue = device.makeCommandQueue()
    }
    
    func loadAssets() {
        // Create and load our assets into Metal objects including meshes and textures
        
        // Create a MetalKit mesh buffer allocator so that ModelIO will load mesh data directly into
        //   Metal buffers accessible by the GPU
       // let metalAllocator = MTKMeshBufferAllocator(device: device)
        
        // Creata a Model IO vertexDescriptor so that we format/layout our model IO mesh vertices to
        //   fit our Metal render pipeline's vertex descriptor layout
//        let vertexDescriptor = MTKModelIOVertexDescriptorFromMetal(geometryVertexDescriptor)
//
//        // Indicate how each Metal vertex descriptor attribute maps to each ModelIO attribute
//        (vertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributePosition
//        (vertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
//        (vertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)] as! MDLVertexAttribute).name   = MDLVertexAttributeNormal
//
//        // Use ModelIO to create a box mesh as our object
//        let mesh = MDLMesh(boxWithExtent: vector3(0.075, 0.075, 0.075), segments: vector3(1, 1, 1), inwardNormals: false, geometryType: .triangles, allocator: metalAllocator)
//
//        // Perform the format/relayout of mesh vertices by setting the new vertex descriptor in our
//        //   Model IO mesh
//        mesh.vertexDescriptor = vertexDescriptor
//
//        // Create a MetalKit mesh (and submeshes) backed by Metal buffers
//        do {
//            try cubeMesh = MTKMesh(mesh: mesh, device: device)
//        } catch let error {
//            print("Error creating MetalKit mesh, error \(error)")
//        }
    }
    
    // MARK: Core Update Loop

    
    func update() {

  
        
        let _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
 
        updateBufferStates()
        
        if !pointOfViewConfigured {
            if let _ = sceneRenderer.pointOfView   {
                configurePointOfView()
            }
        }
        
        var outputPixelBuffer : CVPixelBuffer?
        
        var renderTargetTexture : MTLTexture?
        
        if pixelBufferPool != nil {
            
            var newPixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool!, &newPixelBuffer)
            
            if newPixelBuffer == nil  {
                print("Allocation failure: Could not get pixel buffer from pool (\(self.description))")
                return
            }
            
            outputPixelBuffer = newPixelBuffer
            
            
            if let outputTexture = createTexture(fromPixelBuffer: outputPixelBuffer!, pixelFormat: .bgra8Unorm, planeIndex: 0)
            {
                renderTargetTexture =    CVMetalTextureGetTexture(outputTexture)
            }
            
        }
        
        
         if let commandBuffer = commandQueue.makeCommandBuffer() {
            commandBuffer.label = "MaskCommand"
            
            var textures = [capturedImageTextureY, capturedImageTextureCbCr]
            commandBuffer.addCompletedHandler{ [weak self] commandBuffer in
                if let strongSelf = self {
                    strongSelf.inFlightSemaphore.signal()
                }
                textures.removeAll()
            }
            
            
            

            renderCapturedImage(commandBuffer: commandBuffer)
            
            
            if !isSwappingMasks && capturedImageRenderTextureBuffer != nil && faceContentNode != nil && leftEyeBounds.size.width > 0 && rightEyeBounds.size.width > 0 && faceContentNode!.needsEyeUpdate && self.isTracking {

                let didTrackEyes =  calculateEyeGeometry(commandBuffer: commandBuffer, boundsLeft: rightEyeBounds, boundsRight: leftEyeBounds,  sourceTexture: capturedImageRenderTextureBuffer)
                
                if !didTrackEyes {
                    
                    eyeStates[.left] = EyeState.unknown
                    eyeStates[.right] = EyeState.unknown
                    
                    faceContentNode?.setEyeStates(states: eyeStates)
                    
                } else {
                    
                    
                    faceContentNode?.setEyeStates(states: eyeStates)

                }

            }
            
            if let renderPassDescriptor = renderDestination.currentRenderPassDescriptor {
                
                let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
                
                renderEncoder.label = "BaseRenderEncoder"
                
                drawCapturedImage(renderEncoder: renderEncoder)
                
                renderEncoder.endEncoding()
                
                if lastCamera != nil && faceGeometry != nil && faceContentNode != nil && isTracking  && !isSwappingMasks{
                    renderSkinSmoothing(commandBuffer: commandBuffer, renderPassDescriptor: renderPassDescriptor)
                    renderImageComposite( commandBuffer: commandBuffer, destinationTexture:renderPassDescriptor.colorAttachments[0].texture!, compositeTexture: skinSmoothingTextureBuffers[0]   )

                }
                else {
                    renderImageComposite( commandBuffer: commandBuffer, destinationTexture:renderPassDescriptor.colorAttachments[0].texture!, compositeTexture: capturedImageRenderTextureBuffer   )

                }
                
                
                if isTracking && !isSwappingMasks {
                    renderImageComposite( commandBuffer: commandBuffer,destinationTexture: capturedImageRenderTextureBuffer, compositeTexture: skinSmoothingTextureBuffers[0]   )
                    faceContentNode?.updateCameraTexture(withCameraTexture: capturedImageRenderTextureBuffer )
                }
                
              
                if !isSwappingMasks {
                    let renderScenePassDescriptor = MTLRenderPassDescriptor()

                    renderScenePassDescriptor.colorAttachments[0].texture =  renderPassDescriptor.colorAttachments[0].texture
                    renderScenePassDescriptor.colorAttachments[0].resolveTexture =  renderPassDescriptor.colorAttachments[0].resolveTexture;
                    renderScenePassDescriptor.colorAttachments[0].loadAction = MTLLoadAction.load;
                    renderScenePassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
                    renderScenePassDescriptor.colorAttachments[0].storeAction =  renderPassDescriptor.colorAttachments[0].storeAction;
                    renderScenePassDescriptor.depthAttachment = renderPassDescriptor.depthAttachment;
                    renderScenePassDescriptor.stencilAttachment = renderPassDescriptor.stencilAttachment;
                    

                     sceneRenderer.render(atTime: CACurrentMediaTime(), viewport: viewport, commandBuffer: commandBuffer, passDescriptor: renderScenePassDescriptor)
                    
                    
                    if faceContentNode?.lutTextures[LUTType.world] != nil || ( self.colorProcessingParameters.contrastIntensity != 0.0 && self.colorProcessingParameters.saturationIntensity != 1.0 ) {
                        renderColorProcessing( commandBuffer: commandBuffer, lutTexture: faceContentNode?.lutTextures[LUTType.world]!)
                    }
                    
                }
                
                
//                if let lutTexture = faceContentNode?.lookUpTables()?[LUTType.world] {
//
//                    renderLUT(commandBuffer: commandBuffer, destinationTexture: renderPassDescriptor.colorAttachments[0].texture!, lutTexture: lutTexture, stencilTexture: renderPassDescriptor.depthAttachment.texture!, lutType: LUTType.world)
//
//
//                }
    
                if faceContentNode?.lutTextures[LUTType.world] != nil || ( self.colorProcessingParameters.contrastIntensity != 0.0 && self.colorProcessingParameters.saturationIntensity != 1.0 ) {
                    renderColorProcessing( commandBuffer: commandBuffer, lutTexture: faceContentNode?.lutTextures[LUTType.world]!)
                }
                
                
 
                if renderTargetTexture != nil {
                    renderCVPixelBuffer(commandBuffer: commandBuffer, destinationTexture: renderTargetTexture!, sourceTexture: renderPassDescriptor.colorAttachments[0].texture!)
                    
                    if pixelBufferConsumer != nil {
                        pixelBufferConsumer!.renderCallbackQueue.async {
                            
                            let cmTime : CMTime = CMTimeMakeWithSeconds(self.lastTimestamp!, 1000000)
                            self.pixelBufferConsumer?.renderedOutput(didRender: outputPixelBuffer!, atTime: cmTime)
                        }
                    }
                }

                if let currentDrawable = renderDestination.currentDrawable {
                    commandBuffer.present(currentDrawable)
                }
            }
            
            // Finalize rendering here & push the command buffer to the GPU
            commandBuffer.commit()
        }
    }
    
    // MARK: Render Methods
    
    func calculateEyeGeometry( commandBuffer: MTLCommandBuffer, boundsLeft: CGRect,  boundsRight: CGRect, sourceTexture: MTLTexture )  -> Bool {
        
        commandBuffer.pushDebugGroup("EyeTextures")
        
        var leftTexture : MTLTexture?
        var rightTexture : MTLTexture?
        
        var leftPaddedBounds = CGRect.zero
        var leftSourceBounds = CGRect.zero
        var leftOffset = vector_float2(0.0,0.0)
        var leftSourceOrigin  = MTLOriginMake( 0, 0, 0)

        var rightPaddedBounds = CGRect.zero
        var rightSourceBounds = CGRect.zero
        var rightOffset = vector_float2(0.0,0.0)
        var rightSourceOrigin  = MTLOriginMake( 0, 0, 0)

        let destinationOrigin  = MTLOriginMake( 0, 0, 0)
 
        for i in 0...1 {

            let bounds = i == 0 ? boundsLeft : boundsRight
            
            let paddedBounds = bounds.insetBy(dx: -5.0, dy: -10.0)
            
            if paddedBounds.size.width == 0 || paddedBounds.size.height == 0 {
                 return false
            }
            
            let sourceOrigin  = MTLOriginMake( Int(paddedBounds.origin.x), Int(paddedBounds.origin.y), 0)

            let minimumAlignment = device.minimumLinearTextureAlignment( for: sourceTexture.pixelFormat )

            let adjustedWidth = Float(paddedBounds.size.width / CGFloat(minimumAlignment)).rounded(.up) * Float(minimumAlignment)

            let adjustedHeight = Float(paddedBounds.size.height / CGFloat(minimumAlignment)).rounded(.up) * Float(minimumAlignment)

            let size = MTLSizeMake( Int(adjustedWidth), Int(adjustedHeight), 1)
            
            if( sourceTexture.width < Int(sourceOrigin.x + size.width) || sourceTexture.height < Int(sourceOrigin.y + size.height)  )
            {
                return false
            }

            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: sourceTexture.pixelFormat, width: Int(adjustedWidth), height: Int(adjustedHeight), mipmapped: false)
            
            textureDescriptor.usage = MTLTextureUsage(rawValue:MTLTextureUsage.shaderRead.rawValue  | MTLTextureUsage.shaderWrite.rawValue  | MTLTextureUsage.pixelFormatView.rawValue  | MTLTextureUsage.renderTarget.rawValue)
            
            if i == 0  {
                
                leftSourceOrigin = MTLOrigin(x:sourceOrigin.x, y:sourceOrigin.y, z:sourceOrigin.z)

                leftSourceBounds = CGRect(origin: paddedBounds.origin, size: paddedBounds.size)
                
                let bytesPerRow : Int = 4 * Int(adjustedWidth)
                
                leftTexture =  leftEyeTextureBuffer!.makeTexture(descriptor: textureDescriptor, offset: 0, bytesPerRow: bytesPerRow)!

                leftPaddedBounds =  CGRect( x: 0, y: 0, width: paddedBounds.size.width, height: paddedBounds.size.height )
                
                leftOffset = vector_float2(Float(bounds.origin.x),Float(bounds.origin.y))
                
            } else {
                
                rightSourceOrigin = MTLOrigin(x:sourceOrigin.x, y:sourceOrigin.y, z:sourceOrigin.z)

                rightSourceBounds = CGRect(origin: paddedBounds.origin, size: paddedBounds.size)
                
                let bytesPerRow : Int = 4 * Int(adjustedWidth)

                rightTexture =  rightEyeTextureBuffer!.makeTexture(descriptor: textureDescriptor, offset: 0, bytesPerRow: bytesPerRow)!
                
                rightPaddedBounds =  CGRect( x: 0, y: 0, width: paddedBounds.size.width, height: paddedBounds.size.height )
                
                rightOffset = vector_float2(Float(bounds.origin.x),Float(bounds.origin.y))
            }
           
            
        }
        
        let  blitEncoder = commandBuffer.makeBlitCommandEncoder()!

        blitEncoder.copy( from: sourceTexture  , sourceSlice: 0, sourceLevel: 0, sourceOrigin: leftSourceOrigin, sourceSize: MTLSizeMake( Int(leftSourceBounds.size.width), Int(leftSourceBounds.size.height), 1), to: leftTexture!, destinationSlice: 0, destinationLevel: 0,
                          destinationOrigin:destinationOrigin)
        
        
        blitEncoder.copy( from: sourceTexture  , sourceSlice: 0, sourceLevel: 0, sourceOrigin: rightSourceOrigin, sourceSize:MTLSizeMake( Int(rightSourceBounds.size.width), Int(rightSourceBounds.size.height), 1), to: rightTexture!, destinationSlice: 0, destinationLevel: 0,
                          destinationOrigin:destinationOrigin)
        
        blitEncoder.endEncoding()
        
        commandBuffer.popDebugGroup()

        self.openCVWrapper.detectEyeLandmarks(faceContentNode!, leftTexture: leftTexture, leftOffset: leftOffset , leftBounds: leftPaddedBounds, rightTexture: rightTexture, rightOffset: rightOffset, rightBounds: rightPaddedBounds)
        
        let leftEyeCenter = self.openCVWrapper.leftEyeCenter()
        
        let leftCenter = simd_float3( ((leftEyeCenter.x / Float(viewportSize.width)) - 0.5) * 2.0, (( 1.0 - (leftEyeCenter.y / Float(viewportSize.height)) - 0.5) * 2.0 ) * Float(viewportSize.height / viewportSize.width), -2.0)
 
        
        var rightEyeCenter = self.openCVWrapper.rightEyeCenter()
        
        let rightCenter = simd_float3( ((rightEyeCenter.x / Float(viewportSize.width)) - 0.5) * 2.0, (( 1.0 - (rightEyeCenter.y / Float(viewportSize.height)) - 0.5) * 2.0 ) * Float(viewportSize.height / viewportSize.width), -2.0)
 
        var leftEyeGaze = self.openCVWrapper.leftEyeGaze()
        var rightEyeGaze = self.openCVWrapper.rightEyeGaze()
        
        leftEyeGaze.y = leftEyeGaze.y * -1
        rightEyeGaze.y = rightEyeGaze.y * -1
        
        let scale = self.sceneRenderer.pointOfView?.camera?.projectionTransform.m11

        faceContentNode?.updateEyeGeometry(eyeScale: 1.0, leftEyeCenter: leftCenter, leftEyeGaze: leftEyeGaze, rightEyeCenter: rightCenter, rightEyeGaze: rightEyeGaze, xScale: scale!)
        
       return true
        
    }
    
    func renderLUT( commandBuffer : MTLCommandBuffer, destinationTexture : MTLTexture, lutTexture : MTLTexture, stencilTexture : MTLTexture, lutType: LUTType ) {

        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
        
             computeEncoder.setComputePipelineState(lutComputePipelineState)
            
            var intensity : Float =  Float(0.9)
            
            computeEncoder.setTexture(destinationTexture, index: 0)
            computeEncoder.setTexture(lutTexture, index: 1)
            computeEncoder.setBytes( &intensity, length: MemoryLayout<Float>.size, index: 0)
            
            let threadsPerGrid = MTLSize(width: destinationTexture.width,
                                         height: destinationTexture.height,
                                         depth: 1)
            
            let w = lutComputePipelineState.threadExecutionWidth
            
            let threadsPerThreadgroup = MTLSizeMake(w, lutComputePipelineState.maxTotalThreadsPerThreadgroup / w, 1)

            computeEncoder.dispatchThreads(threadsPerGrid,
                                                  threadsPerThreadgroup: threadsPerThreadgroup)
            
            computeEncoder.endEncoding()
        }
        
    }
    
    func renderColorProcessing( commandBuffer : MTLCommandBuffer,  lutTexture : MTLTexture?  ) {
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        
        renderPassDescriptor.colorAttachments[0].texture = renderDestination.currentRenderPassDescriptor?.colorAttachments[0].texture
        renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadAction.load
        renderPassDescriptor.colorAttachments[0].storeAction =  MTLStoreAction.store
     //   renderPassDescriptor.colorAttachments[0].resolveTexture = renderDestination.currentRenderPassDescriptor?.colorAttachments[0].resolveTexture
        
      
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            
            renderEncoder.pushDebugGroup("ColorProcessing")
            
            renderEncoder.setCullMode(.none)
            
            renderEncoder.setRenderPipelineState(colorProcessingPipelineState)
            
            renderEncoder.setVertexBuffer(imagePlaneVertexBuffer, offset: 0, index: Int(kBufferIndexMeshPositions.rawValue))

            if let lut = lutTexture {
                renderEncoder.setFragmentTexture( lut, index: 0)
            }
            
            var parameters = ColorProcessingParameters()
            parameters.lutIntensity = self.colorProcessingParameters.lutIntensity
            parameters.saturationIntensity = self.colorProcessingParameters.saturationIntensity
            parameters.contrastIntensity = self.colorProcessingParameters.contrastIntensity
            
            renderEncoder.setFragmentBytes(&parameters, length: MemoryLayout<ColorProcessingParameters>.size, index: 0)

            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            renderEncoder.popDebugGroup()
            
            renderEncoder.endEncoding()
            
        }
        
    }
    
    func render2DPoints( commandBuffer : MTLCommandBuffer, points : [simd_float4], destinationTexture : MTLTexture ) {
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        
        renderPassDescriptor.colorAttachments[0].texture = destinationTexture
        renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadAction.load
        renderPassDescriptor.colorAttachments[0].storeAction =  MTLStoreAction.store
        renderPassDescriptor.colorAttachments[0].resolveTexture = renderDestination.currentRenderPassDescriptor?.colorAttachments[0].resolveTexture
 
        let pointsVertexDataCount = points.count * MemoryLayout<simd_float4>.size
        let pointsVertexBuffer = device.makeBuffer(bytes: points, length: pointsVertexDataCount, options: .storageModeShared )
        
        
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            
            renderEncoder.pushDebugGroup("Draw2DImage")
            
            let renderViewport = MTLViewport(originX:0,originY: 0,width: Double( viewport.width ), height: Double( viewport.height ), znear:0.0,zfar:1.0)
            
            renderEncoder.setViewport(renderViewport)
            
            renderEncoder.setRenderPipelineState(draw2DPipelineState)
            
            renderEncoder.setVertexBuffer(pointsVertexBuffer, offset: 0, index: 0)
            
            renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: points.count)
            
            renderEncoder.popDebugGroup()
            
            renderEncoder.endEncoding()
            
        }
        
      
        
        
    }
    
    func renderImageComposite( commandBuffer : MTLCommandBuffer, destinationTexture : MTLTexture, compositeTexture : MTLTexture ) {
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        
        renderPassDescriptor.colorAttachments[0].texture = destinationTexture
        renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadAction.load
        renderPassDescriptor.colorAttachments[0].storeAction =  MTLStoreAction.store
        renderPassDescriptor.colorAttachments[0].resolveTexture = renderDestination.currentRenderPassDescriptor?.colorAttachments[0].resolveTexture
        
//        renderPassDescriptor.colorAttachments[1].texture = compositeTexture
//        renderPassDescriptor.colorAttachments[1].loadAction = MTLLoadAction.load
//        renderPassDescriptor.colorAttachments[1].storeAction =  MTLStoreAction.dontCare
//        renderPassDescriptor.colorAttachments[1].resolveTexture = renderDestination.currentRenderPassDescriptor?.colorAttachments[0].resolveTexture
//
        
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            
            renderEncoder.pushDebugGroup("DrawCompositeImage")
            
            let renderViewport = MTLViewport(originX:0,originY: 0,width: Double( viewport.width ), height: Double( viewport.height ), znear:0.0,zfar:1.0)
            
            renderEncoder.setViewport(renderViewport)
            
            renderEncoder.setRenderPipelineState(compositePipelineState)
            
            renderEncoder.setVertexBuffer(imagePlaneVertexBuffer, offset: 0, index: Int(kBufferIndexMeshPositions.rawValue))
            
            renderEncoder.setFragmentTexture(compositeTexture, index: 0)
            
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            renderEncoder.popDebugGroup()
            
            renderEncoder.endEncoding()
            
        }
        
        
    }
    
    func renderCVPixelBuffer( commandBuffer : MTLCommandBuffer, destinationTexture : MTLTexture, sourceTexture : MTLTexture ) {
        
//        let origin : MTLOrigin = MTLOriginMake(0, 0, 0)
//        let size = MTLSizeMake(Int(1280), Int(720), 1)
        let clearColor = MTLClearColorMake(0.0,0.0,0.0, 0.0)
//
        let cvImagePassDescriptor = MTLRenderPassDescriptor()
        
        
        cvImagePassDescriptor.colorAttachments[0].texture = destinationTexture
        cvImagePassDescriptor.colorAttachments[0].loadAction = MTLLoadAction.dontCare
        cvImagePassDescriptor.colorAttachments[0].clearColor = clearColor
        cvImagePassDescriptor.colorAttachments[0].storeAction =  MTLStoreAction.store
        
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: cvImagePassDescriptor) {
            
            renderEncoder.pushDebugGroup("DrawCVImage")
            
            // Set render command encoder state
            renderEncoder.setCullMode(.none)
            
            let renderViewport = MTLViewport(originX:0,originY: 0,width: 1280,height: 720,znear:0.0,zfar:1.0)
            
            renderEncoder.setViewport(renderViewport)
            
            renderEncoder.setRenderPipelineState(cvPipelineState)
            
            // Set mesh's vertex buffers
            renderEncoder.setVertexBuffer(imagePlaneVertexBuffer, offset: 0, index: Int(kBufferIndexMeshPositions.rawValue))
            
            // Set any textures read/sampled from our render pipeline
            renderEncoder.setFragmentTexture(sourceTexture, index: 0)
 
            // Draw each submesh of our mesh
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            renderEncoder.popDebugGroup()
            
            
            renderEncoder.endEncoding()
            
        }
    }
    
    func renderSkinSmoothing( commandBuffer : MTLCommandBuffer, renderPassDescriptor : MTLRenderPassDescriptor )
    {
      
        commandBuffer.pushDebugGroup("SkinSmoothing")
        
        //let origin : MTLOrigin = MTLOriginMake(0, 0, 0)
        //let size = MTLSizeMake(Int(viewport.size.width), Int(viewport.size.height), 1)
        let clearColor = MTLClearColorMake(0.0,0.0,0.0, 0.0)
        
        
        faceVertexBuffer.contents().copyBytes(from: faceGeometry!.vertices, count: 1220 * MemoryLayout<vector_float3>.size)
        
        faceTexCoordBuffer.contents().copyBytes(from: faceGeometry!.textureCoordinates, count: 1220 * MemoryLayout<vector_float2>.size)
        
        faceIndexBuffer.contents().copyBytes(from: faceGeometry!.triangleIndices, count: kFaceIndexCount * 2 )
 
        let textures = [capturedImageRenderTextureBuffer,
                        faceMaskTexture,
                        skinSmoothingTextureBuffers[1],
                        skinSmoothingTextureBuffers[2],
                        skinSmoothingTextureBuffers[3],
                        skinSmoothingTextureBuffers[4]]

       // var passIndex : UInt32 = 0
     
        for ( passIndex, (bufferIndex,clearBuffer)) in smoothingPassInstructions.enumerated() {
            
            let renderSmoothingPassDescriptor = MTLRenderPassDescriptor()
            
            renderSmoothingPassDescriptor.colorAttachments[0].texture =  skinSmoothingTextureBuffers[bufferIndex]
            
            renderSmoothingPassDescriptor.colorAttachments[0].loadAction = clearBuffer ? MTLLoadAction.clear : MTLLoadAction.load
            renderSmoothingPassDescriptor.colorAttachments[0].clearColor = clearColor
            renderSmoothingPassDescriptor.colorAttachments[0].storeAction =  MTLStoreAction.store
          
//            renderSmoothingPassDescriptor.depthAttachment.texture = renderPassDescriptor.depthAttachment.texture
//            renderSmoothingPassDescriptor.depthAttachment.storeAction = MTLStoreAction.dontCare
//            renderSmoothingPassDescriptor.depthAttachment.loadAction =   MTLLoadAction.dontCare
//            renderSmoothingPassDescriptor.stencilAttachment.texture = renderPassDescriptor.stencilAttachment.texture
//            renderSmoothingPassDescriptor.stencilAttachment.storeAction = MTLStoreAction.dontCare
//            renderSmoothingPassDescriptor.stencilAttachment.loadAction =   MTLLoadAction.dontCare
//
//            if(passIndex == 6)
//            {
//
////            renderSmoothingPassDescriptor.depthAttachment.clearDepth = 1.0
//            renderSmoothingPassDescriptor.depthAttachment.storeAction = MTLStoreAction.store
//            renderSmoothingPassDescriptor.depthAttachment.loadAction =   MTLLoadAction.load
////            renderSmoothingPassDescriptor.stencilAttachment.clearStencil = 1
////            renderSmoothingPassDescriptor.stencilAttachment.texture = skinSmoothingDepthBuffer
////           renderSmoothingPassDescriptor.stencilAttachment.storeAction = MTLStoreAction.store
//            }
 
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderSmoothingPassDescriptor)!
            
            renderEncoder.pushDebugGroup("Pass \(passIndex)")
            
            var passParameters = createSmoothingPassParameters(passIndex:UInt32(passIndex),sizeIndex:bufferIndex)

//            renderEncoder.setDepthStencilState(skinSmoothingDepthState)
            renderEncoder.setViewport(passParameters.viewport)
            renderEncoder.setRenderPipelineState(skinSmoothingPipelineState)
            renderEncoder.setVertexBytes(&passParameters.parameters, length: MemoryLayout<SmoothingParameters>.size, index: 2)
            renderEncoder.setFragmentBytes(&passParameters.parameters, length: MemoryLayout<SmoothingParameters>.size, index: 2)
            renderEncoder.setVertexBuffer(faceVertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(faceTexCoordBuffer, offset: 0, index: 1)
            renderEncoder.setFragmentTextures(textures,  range: 0..<6 )
            renderEncoder.drawIndexedPrimitives(type: MTLPrimitiveType.triangle, indexCount: kFaceIndexCount, indexType: MTLIndexType.uint16, indexBuffer: faceIndexBuffer, indexBufferOffset: 0, instanceCount: 1)
            
           // renderEncoder.setStencilReferenceValue(0)
           
            renderEncoder.popDebugGroup()
            
            renderEncoder.endEncoding()
        }
 
 
//      let  blitEncoder = commandBuffer.makeBlitCommandEncoder()!
//
//        blitEncoder.copy( from: skinSmoothingTextureBuffers[0]  , sourceSlice: 0, sourceLevel: 0, sourceOrigin: origin, sourceSize:size, to: capturedImageRenderTextureBuffer, destinationSlice: 0, destinationLevel: 0,
//                          destinationOrigin:origin)
//
//        blitEncoder.endEncoding()
 
        
        commandBuffer.popDebugGroup()

    }
    
    func renderCapturedImage(commandBuffer : MTLCommandBuffer) {
        guard let textureY = capturedImageTextureY, let textureCbCr = capturedImageTextureCbCr else {
            return
        }
        
        let capturedImagePassDescriptor = MTLRenderPassDescriptor()
        
        capturedImagePassDescriptor.colorAttachments[0].texture = capturedImageRenderTextureBuffer
        capturedImagePassDescriptor.colorAttachments[0].loadAction = MTLLoadAction.dontCare;
        capturedImagePassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
        capturedImagePassDescriptor.colorAttachments[0].storeAction =  MTLStoreAction.store
        capturedImagePassDescriptor.colorAttachments[0].resolveTexture = renderDestination.currentRenderPassDescriptor?.colorAttachments[0].resolveTexture
        capturedImagePassDescriptor.stencilAttachment =  renderDestination.currentRenderPassDescriptor?.stencilAttachment
        capturedImagePassDescriptor.depthAttachment =  renderDestination.currentRenderPassDescriptor?.depthAttachment
        
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: capturedImagePassDescriptor) {
            
            renderEncoder.pushDebugGroup("RenderCapturedImage")
            
            // Set render command encoder state
            renderEncoder.setCullMode(.none)
            renderEncoder.setRenderPipelineState(capturedImagePipelineState)
            renderEncoder.setDepthStencilState(capturedImageDepthState)
            
            // Set mesh's vertex buffers
            renderEncoder.setVertexBuffer(imagePlaneVertexBuffer, offset: 0, index: Int(kBufferIndexMeshPositions.rawValue))
            
            // Set any textures read/sampled from our render pipeline
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureY), index: Int(kTextureIndexY.rawValue))
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureCbCr), index: Int(kTextureIndexCbCr.rawValue))
            
            // Draw each submesh of our mesh
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            renderEncoder.popDebugGroup()
            
            
            renderEncoder.endEncoding()
            
        }
        
    }
    
    func drawCapturedImage(renderEncoder: MTLRenderCommandEncoder) {
        guard let textureY = capturedImageTextureY, let textureCbCr = capturedImageTextureCbCr else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("DrawCapturedImage")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.none)
        renderEncoder.setRenderPipelineState(capturedImagePipelineState)
        renderEncoder.setDepthStencilState(capturedImageDepthState)
        
        // Set mesh's vertex buffers
        renderEncoder.setVertexBuffer(imagePlaneVertexBuffer, offset: 0, index: Int(kBufferIndexMeshPositions.rawValue))
        
        // Set any textures read/sampled from our render pipeline
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureY), index: Int(kTextureIndexY.rawValue))
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureCbCr), index: Int(kTextureIndexCbCr.rawValue))
        
        // Draw each submesh of our mesh
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        renderEncoder.popDebugGroup()
    }
    
    func createSmoothingPassParameters( passIndex: UInt32, sizeIndex: Int) -> (viewport : MTLViewport, parameters: SmoothingParameters) {
        
        let width : Double = Double(self.viewport.width * smoothingPassSizes[sizeIndex]).rounded(.up)
        
        let height : Double = Double(self.viewport.height * smoothingPassSizes[sizeIndex]).rounded(.up)

        let renderViewport = MTLViewport(originX:0,originY: 0,width: width,height: height,znear:0.0,zfar:1.0)
        
        var parameters = SmoothingParameters()
        parameters.skinSmoothingFactor = kSkinSmoothingFactor
        parameters.viewMatrix = self.lastCamera!.viewMatrix(for: .portrait)
        parameters.modelMatrix = faceContentNode!.simdTransform
        parameters.passIndex = passIndex
        parameters.imageSize = vector2( Float(renderViewport.width), Float(renderViewport.height) )
        parameters.renderSize = vector2( Float(renderViewport.width), Float(renderViewport.height) )
        parameters.projectionMatrix = self.lastCamera!.projectionMatrix(for: .portrait, viewportSize: CGSize(width:renderViewport.width,height:renderViewport.height), zNear: 0.001, zFar: 1000)
        parameters.inverseResolution = simd_recip( vector_float2( Float(renderViewport.width), Float(renderViewport.height) ) )
        
      //  print("renderViewport \(renderViewport) for passIndex \(passIndex)")
        return (renderViewport, parameters)
    }
    
    
    // MARK: - Updates
    
    func updateFaceAnchor( anchor: ARFaceAnchor ) {
        
        
        
    }
    
    
    func updateARFrame( currentFrame: ARFrame ) {
        

        lastPixelBuffer = currentFrame.capturedImage
        
        lastTimestamp = currentFrame.timestamp
        
        updateSharedUniforms(frame: currentFrame)
        updateAnchors(frame: currentFrame)
        updateCapturedImageTextures(frame: currentFrame)
        
        if( self.pixelBufferPool == nil )
        {
            setupPixelBufferPool(frame: currentFrame)
        }
        
        updateLights(frame: currentFrame)
        
        if viewportSizeDidChange {
            viewportSizeDidChange = false
            updateTextures()
            updateImagePlane(frame: currentFrame)
        }
        
   
        
       // self.overlayNode.simdPosition = self.cameraNode.presentation.simdWorldFront * 0.825
        
    }
    
    func updateBufferStates() {
        // Update the location(s) to which we'll write to in our dynamically changing Metal buffers for
        //   the current frame (i.e. update our slot in the ring buffer used for the current frame)
        
        uniformBufferIndex = (uniformBufferIndex + 1) % kMaxBuffersInFlight
        
        sharedUniformBufferOffset = kAlignedSharedUniformsSize * uniformBufferIndex
        
        sharedUniformBufferAddress = sharedUniformBuffer.contents().advanced(by: sharedUniformBufferOffset)
        
    }
    
 
    func updateSharedUniforms(frame: ARFrame) {
        // Update the shared uniforms of the frame
        
        if self.lastCamera == nil {
            
            let projectionMatrix = frame.camera.projectionMatrix(for: .portrait, viewportSize: CGSize(width:self.viewport.width,height:self.viewport.height), zNear: 0.001, zFar: 1000)
            
            let  newMatrix = SCNMatrix4(projectionMatrix)
            
            sceneRenderer.pointOfView?.camera?.projectionTransform = newMatrix
            
        }
        
        self.lastCamera = frame.camera
        
     
        
        let uniforms = sharedUniformBufferAddress.assumingMemoryBound(to: SharedUniforms.self)
        
        uniforms.pointee.viewMatrix = frame.camera.viewMatrix(for: .portrait)
        uniforms.pointee.projectionMatrix = frame.camera.projectionMatrix(for: .portrait, viewportSize: viewportSize, zNear: 0.001, zFar: 1000)

        // Set up lighting for the scene using the ambient intensity if provided
        var ambientIntensity: Float = 1.0
        
        if let lightEstimate = frame.lightEstimate {
            ambientIntensity = Float(lightEstimate.ambientIntensity) / 1000.0
        }
        
        let ambientLightColor: vector_float3 = vector3(0.5, 0.5, 0.5)
        uniforms.pointee.ambientLightColor = ambientLightColor * ambientIntensity
        
        var directionalLightDirection : vector_float3 = vector3(0.0, 0.0, -1.0)
        directionalLightDirection = simd_normalize(directionalLightDirection)
        uniforms.pointee.directionalLightDirection = directionalLightDirection
        
        let directionalLightColor: vector_float3 = vector3(0.6, 0.6, 0.6)
        uniforms.pointee.directionalLightColor = directionalLightColor * ambientIntensity
        
        uniforms.pointee.materialShininess = 30
  
        
    }
    
    func updateLights( frame: ARFrame ) {
        
        
        let lightEstimate = frame.lightEstimate!
        
       if let directionalLightEstimate = lightEstimate as? ARDirectionalLightEstimate {
        
            if var data = self.lightNode.light?.sphericalHarmonicsCoefficients {
                
                let coeffecients = directionalLightEstimate.sphericalHarmonicsCoefficients
                
                data.replaceSubrange(data.indices, with: coeffecients)
                
            }
        
            self.lightNode.light?.intensity = directionalLightEstimate.primaryLightIntensity
        
            self.lightNode.light?.temperature = lightEstimate.ambientColorTemperature
        
 
            self.ambientLightNode.light?.intensity =  directionalLightEstimate.primaryLightIntensity ;
            self.ambientLightNode.light?.temperature =  lightEstimate.ambientColorTemperature
        
            let primaryLightDirection : vector_float3 = normalize(directionalLightEstimate.primaryLightDirection)
        
            let lightVector = SCNVector3Make(primaryLightDirection.x, primaryLightDirection.y, primaryLightDirection.z)

            self.lightNode.eulerAngles =  lightVector
        
        }
        
       let intensity = lightEstimate.ambientIntensity / 1000.0;
       self.scene.lightingEnvironment.intensity = intensity
        
      

    }
    
    func updateAnchors(frame: ARFrame) {

 /**
 The camera intrinsics.
 @discussion The matrix has the following contents:
 fx 0   px
 0  fy  py
 0  0   1
 fx and fy are the focal length in pixels.
 px and py are the coordinates of the principal point in pixels.
 The origin is at the center of the upper-left pixel.
 */
        if isSwappingMasks {
            return
        }

        for index in 0..<frame.anchors.count {
            
            let anchor = frame.anchors[index]

 
            guard let faceAnchor = anchor as? ARFaceAnchor else {
                
                if worldNode != nil && worldAnchorUUID != nil && worldAnchorUUID! == anchor.identifier {
                    var coordinateSpaceTransform = matrix_identity_float4x4
                    coordinateSpaceTransform.columns.2.z = -1.0
                    
                    let modelMatrix = simd_mul(frame.camera.viewMatrix(for: .portrait),anchor.transform);
                    worldNode?.simdTransform = modelMatrix
                   // worldNode?.simdTransform =  simd_mul(frame.camera.viewMatrix(for: .portrait),anchor.transform);
                }
                continue;
            }
            
            if !faceAnchor.isTracked  {
                
                self.isTracking = false
                
                faceContentNode?.setTracking(isTracking: false)
                
                continue;
            }
            
            if cameraInstrinsics == nil {
                
                let intrinsics : matrix_float3x3 = frame.camera.intrinsics
                
                cameraInstrinsics = CameraInstrinsics()
                cameraInstrinsics!.fx = intrinsics[0][0]
                cameraInstrinsics!.fy = intrinsics[1][1]
                cameraInstrinsics!.cx = intrinsics[2][0]
                cameraInstrinsics!.cy = intrinsics[2][1]
                
                openCVWrapper.setIntrinsics( simd_float4(cameraInstrinsics!.fx,cameraInstrinsics!.fy,cameraInstrinsics!.cx,cameraInstrinsics!.cy) )

            }
            
 
          //let upVector =   simd_float3( frame.camera.transform[2][1], frame.camera.transform[2][2], frame.camera.transform[2][3] )

          //  print("upVector: \(upVector)")
            
            self.isTracking = true

            faceContentNode?.setTracking(isTracking: true)

//            if let opacity = faceContentNode?.opacity {
//
//                self.isTracking = true
//
//                if( opacity == 0.0 )
//                {
//                    SCNTransaction.begin()
//                    SCNTransaction.animationDuration = 0.3
//                    faceContentNode?.opacity = 1.0
//                    SCNTransaction.commit()
//                }
//
//            }
            
            
            faceContentNode?.updateFaceAnchor(withFaceAnchor: faceAnchor)
            
            faceContentNode?.simdTransform = simd_mul(frame.camera.viewMatrix(for: .portrait),faceAnchor.transform);
            
           //  worldNode?.simdTransform = simd_mul(frame.camera.viewMatrix(for: .portrait),faceAnchor.transform);
            
            faceGeometry = faceAnchor.geometry
            
            
//            var geometryPtr : SCNGeometry = faceContentNode!.geometry!
//
//            var sources = geometryPtr.sources
//
//            var texSource = geometryPtr.sources(for: SCNGeometrySource.Semantic.texcoord)[0]
//
//            let dataLength = texSource.data.count
//
//            let testPointer = UnsafeRawBufferPointer(start: faceGeometry!.textureCoordinates, count: faceGeometry!.textureCoordinates.count * MemoryLayout<float2>.size )
//
//            var uvPointer = UnsafeRawBufferPointer(start: alternateFaceUVSourceCoords, count: faceGeometry!.textureCoordinates.count * MemoryLayout<float2>.size )
//
//            let mutablePointer = UnsafeMutableRawBufferPointer(mutating: testPointer)
//
//            mutablePointer.copyBytes(from: uvPointer)
            
//            var bufferPointer = UnsafeMutableRawBufferPointer(start: &faceGeometry!.textureCoordinates, count: faceGeometry!.textureCoordinates.count * MemoryLayout<float2>.size )
//
//            var uvPointer = UnsafeRawBufferPointer(start: alternateFaceUVSourceCoords!, count: faceGeometry!.textureCoordinates.count * MemoryLayout<float2>.size )
//
           // bufferPointer.
           
            
            lastFaceTransform = faceAnchor.transform
            
            if faceContentNode!.needsEyeUpdate {
                
                updateEyeGeometry()
                
                
                if leftEyeBounds.size.width > 0 && rightEyeBounds.size.width > 0 {
                    
                    var openVertices : [float3] = kEyeOpenReferenceIndices[Eye.left]!.map({ (value) -> float3 in
                        
                        return faceGeometry!.vertices[value]
                        
                    })
                    
                    eyeOpeness[Eye.left] = distance(openVertices[0], openVertices[1])
                    
              
                    
                    if eyeOpeness[Eye.left]! < kOpenessThreshold {
                        eyeStates[Eye.left] = EyeState.closed
                        
                    } else {
                        eyeStates[Eye.left] = EyeState.open
                    }
                    
                    openVertices = kEyeOpenReferenceIndices[Eye.right]!.map({ (value) -> float3 in
                        
                        return faceGeometry!.vertices[value]
                        
                    })
                    
                    eyeOpeness[Eye.right] = distance(openVertices[0], openVertices[1])
                    
                    if eyeOpeness[Eye.right]! < kOpenessThreshold {
                        eyeStates[Eye.right] = EyeState.closed
                        
                    } else {
                        eyeStates[Eye.right] = EyeState.open
                    }
                    
                    
                    
                } else {
                    eyeStates[.left] = EyeState.unknown
                    eyeStates[.right] = EyeState.unknown
                }
                
            }
            
        //    maskNode.boundingBox
          //   cameraNode.position = cameraPos;
        }
    }
    
   
    
    func updateBoundingRect( modelViewMatrix: matrix_float4x4, projectionMatrix: matrix_float4x4, bounds : CGRect, vertexId : Int ) -> CGRect {
        
            let eyeVertex =  faceGeometry!.vertices[vertexId]

            let vertex = simd_float4(eyeVertex.x, eyeVertex.y, eyeVertex.z ,1.0)
        
            let fragmentPosition =  projectionMatrix * modelViewMatrix * vertex
        
            let screenPosition = simd_float2( fragmentPosition.x / fragmentPosition.w, fragmentPosition.y / fragmentPosition.w )
        
            let ndc = simd_float2( ((screenPosition.x + 1.0) / 2.0) * Float(viewportSize.width), (( 1.0 - screenPosition.y ) / 2.0) * Float(viewportSize.height) )

            var currentOrigin = bounds.origin;

            var currentExtent : CGPoint

            if( bounds.size.width == 0 )
            {
                currentExtent = CGPoint( x: bounds.size.width, y:  bounds.size.height );
            }
            else
            {
                currentExtent = CGPoint( x: bounds.origin.x + bounds.size.width, y: bounds.origin.y + bounds.size.height );
            }

            if( ndc.x < Float(currentOrigin.x) )
            {
                currentOrigin.x = CGFloat(ndc.x)
            }

            if( ndc.y < Float(currentOrigin.y) )
            {
                currentOrigin.y = CGFloat(ndc.y)
            }

            if( ndc.x > Float(currentExtent.x) )
            {
                currentExtent.x = CGFloat(ndc.x)
            }

            if( ndc.y > Float(currentExtent.y) )
            {
                currentExtent.y = CGFloat(ndc.y)
            }

            let dX = sqrt((currentExtent.x - currentOrigin.x) * (currentExtent.x - currentOrigin.x))
            let dY = sqrt((currentExtent.y - currentOrigin.y) * (currentExtent.y - currentOrigin.y))

            return CGRect( origin: currentOrigin, size: CGSize(width: CGFloat(dX), height: CGFloat(dY)) )
        
    }
    
    
    func updateEyeGeometry()  {
        
       
        if faceGeometry != nil && lastFaceTransform != nil {
            
            let viewMatrix = lastCamera?.viewMatrix(for: .portrait)
            
            let projectionMatrix = self.lastCamera!.projectionMatrix(for: .portrait, viewportSize: viewportSize, zNear: 0.001, zFar: 1000)
            
            let modelViewMatrix = simd_mul( viewMatrix!, lastFaceTransform! )
   
            let initialRect = CGRect(x: CGFloat.greatestFiniteMagnitude, y: CGFloat.greatestFiniteMagnitude, width: 0.0, height: 0.0 )
            
            self.leftEyeBounds = kLeftEyeBoundsVertices.reduce( initialRect, { (rect, vid)  in
                return updateBoundingRect( modelViewMatrix: modelViewMatrix, projectionMatrix: projectionMatrix, bounds: rect, vertexId: vid)
            })
            
            self.rightEyeBounds = kRightEyeBoundsVertices.reduce( initialRect,  { (rect,vid) in
                return updateBoundingRect( modelViewMatrix: modelViewMatrix, projectionMatrix: projectionMatrix, bounds: rect, vertexId: vid)
             })
            
            
//            if leftEyeBounds.size.width > 0 && rightEyeBounds.size.width > 0 {
//
//                var openVertices : [float3] = kEyeOpenReferenceIndices[Eye.left]!.map({ (value) -> float3 in
//
//                    return faceGeometry!.vertices[value]
//
//                })
//
//                eyeOpeness[Eye.left] = distance(openVertices[0], openVertices[1])
//
//                var didChange = false
//
//                if eyeOpeness[Eye.left]! < kOpenessThreshold {
//                    eyeStates[Eye.left] = EyeState.closed
//
//                } else {
//                    eyeStates[Eye.left] = EyeState.open
//                }
//
//                openVertices = kEyeOpenReferenceIndices[Eye.right]!.map({ (value) -> float3 in
//
//                    return faceGeometry!.vertices[value]
//
//                })
//
//                eyeOpeness[Eye.right] = distance(openVertices[0], openVertices[1])
//
//                if eyeOpeness[Eye.right]! < kOpenessThreshold {
//                    eyeStates[Eye.right] = EyeState.closed
//
//                } else {
//                    eyeStates[Eye.right] = EyeState.open
//                }
//
//
//
//            } else {
//                eyeStates[.left] = EyeState.unknown
//                eyeStates[.right] = EyeState.unknown
//            }
            
        }
    }

    func updateTextures()
    {
        
        var textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: renderDestination.colorPixelFormat, width: Int(viewport.width), height: Int(viewport.height), mipmapped: renderDestination.sampleCount > 0)
        
        textureDescriptor.usage = MTLTextureUsage(rawValue:MTLTextureUsage.shaderRead.rawValue  | MTLTextureUsage.shaderWrite.rawValue  | MTLTextureUsage.renderTarget.rawValue)
        
        capturedImageRenderTextureBuffer =  device.makeTexture(descriptor: textureDescriptor)!
        
        capturedImageRenderTextureBuffer.label = "capturedImageRenderTextureBuffer"
        
        skinSmoothingTextureBuffers = [MTLTexture]()
        
        
        for size : CGFloat in smoothingPassSizes {
            
            textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: renderDestination.colorPixelFormat, width: Int( Double(viewport.width * size).rounded(.up)), height: Int(Double(viewport.height * size).rounded(.up)), mipmapped: renderDestination.sampleCount > 0)
            
            textureDescriptor.usage = MTLTextureUsage(rawValue:MTLTextureUsage.shaderRead.rawValue | MTLTextureUsage.shaderWrite.rawValue | MTLTextureUsage.renderTarget.rawValue)
            
            if let smoothingPassBuffer =  device.makeTexture(descriptor: textureDescriptor) {
                skinSmoothingTextureBuffers.append(smoothingPassBuffer)
            }
            
        }
        
        textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MTLPixelFormat.depth32Float_stencil8, width: Int(viewport.width), height: Int(viewport.height), mipmapped: renderDestination.sampleCount > 0)
        
        textureDescriptor.usage = MTLTextureUsage(rawValue:MTLTextureUsage.shaderRead.rawValue | MTLTextureUsage.shaderWrite.rawValue | MTLTextureUsage.renderTarget.rawValue)

        skinSmoothingDepthBuffer = device.makeTexture(descriptor: textureDescriptor)
    }
    
    func updateCapturedImageTextures(frame: ARFrame) {
        // Create two textures (Y and CbCr) from the provided frame's captured image
        let pixelBuffer = frame.capturedImage
        
        if (CVPixelBufferGetPlaneCount(pixelBuffer) < 2) {
            return
        }
        
      
        
        capturedImageTextureY = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.r8Unorm, planeIndex:0)
        capturedImageTextureCbCr = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.rg8Unorm, planeIndex:1)
    }
    
    
    func updateImagePlane(frame: ARFrame) {
        // Update the texture coordinates of our image plane to aspect fill the viewport
        
      //  capturedImageRenderTextureBuffers = nil
     
        let displayToCameraTransform = frame.displayTransform(for: .portrait, viewportSize: viewportSize).inverted()

        let vertexData = imagePlaneVertexBuffer.contents().assumingMemoryBound(to: Float.self)
        for index in 0...3 {
            let textureCoordIndex = 4 * index + 2
            let textureCoord = CGPoint(x: CGFloat(kImagePlaneVertexData[textureCoordIndex]), y: CGFloat(kImagePlaneVertexData[textureCoordIndex + 1]))
            let transformedCoord = textureCoord.applying(displayToCameraTransform)
            vertexData[textureCoordIndex] = Float(transformedCoord.x)
            vertexData[textureCoordIndex + 1] = Float(transformedCoord.y)
        }
    }
    
   
    
//    func drawAnchorGeometry(renderEncoder: MTLRenderCommandEncoder) {
//        guard anchorInstanceCount > 0 else {
//            return
//        }
//
//        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
//        renderEncoder.pushDebugGroup("DrawAnchors")
//
//        // Set render command encoder state
//        renderEncoder.setCullMode(.back)
//        renderEncoder.setRenderPipelineState(skinSmoothingPipelineState)
//        renderEncoder.setDepthStencilState(skinSmoothingDepthState)
//
//        // Set any buffers fed into our render pipeline
//        renderEncoder.setVertexBuffer(anchorUniformBuffer, offset: anchorUniformBufferOffset, index: Int(kBufferIndexInstanceUniforms.rawValue))
//        renderEncoder.setVertexBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
//        renderEncoder.setFragmentBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
//
//        // Set mesh's vertex buffers
//        for bufferIndex in 0..<cubeMesh.vertexBuffers.count {
//            let vertexBuffer = cubeMesh.vertexBuffers[bufferIndex]
//            renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index:bufferIndex)
//        }
//
//        // Draw each submesh of our mesh
//        for submesh in cubeMesh.submeshes {
//            renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset, instanceCount: anchorInstanceCount)
//        }
//
//        renderEncoder.popDebugGroup()
//    }
    
    
//    func setupSkinSmoothing()
//    {
//
//        var faceMask : MTLTexture?
//
//        let url = Bundle.main.url(forResource: "skinSmoothingTexture", withExtension: "png", subdirectory: "Models.scnassets")
//
//        do {
//            try faceMask = textureLoader.newTexture(URL: url!, options: nil)
//        } catch let error {
//            print("Failed to created captured image pipeline state, error \(error)")
//            faceMask = nil
//        }
//
//        let program = SCNProgram()
//        program.fragmentFunctionName = "skinSmoothingFragment"
//        program.vertexFunctionName = "skinSmoothingVertex"
//        program.delegate = self
//
//
//        let parameters = smoothingParametersBufferAddress.assumingMemoryBound(to: SmoothingParameters.self)
//        parameters.pointee.imageSize = vector2( Float(self.viewport.size.width), Float(self.viewport.size.height) )
//        parameters.pointee.renderSize = vector2( Float(self.viewport.size.width), Float(self.viewport.size.height) )
//        parameters.pointee.passIndex = 0
//        parameters.pointee.skinSmoothingFactor = 0.7
//
//
//    }
    
    // MARK: - PixelBuffers
    
    func createTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
    

        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, capturedImageTextureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)
        
        if status != kCVReturnSuccess {
            texture = nil
        }
        
        return texture
    }
    
    func setupPixelBufferPool(frame: ARFrame) {
        
        let pixelBuffer = frame.capturedImage;
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
      
        
       //  let formatType = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
            //let formatDescription = CVPixelFormatDescriptionCreateWithPixelFormatType(kCFAllocatorDefault, formatType)
        
        let pixelBufferAttributes : [String : Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                                      kCVPixelBufferWidthKey as String: width,
                                                      kCVPixelBufferHeightKey as String: height,
                                                      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                                                      kCVPixelBufferOpenGLESCompatibilityKey as String: true,
                                                      kCVPixelBufferIOSurfaceOpenGLESFBOCompatibilityKey as String: true,
                                                      kCVPixelBufferIOSurfaceCoreAnimationCompatibilityKey as String: true,
                                                      
                                                      kCVPixelBufferMetalCompatibilityKey as String: true]
        
        var inputFormatDescription : CMFormatDescription?
        
        CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, frame.capturedImage, &inputFormatDescription)
        
        colorSpace = CGColorSpaceCreateDeviceRGB()
        
        if let inputFormatDescriptionExtension = CMFormatDescriptionGetExtensions(inputFormatDescription!) as Dictionary? {
            let colorPrimaries = inputFormatDescriptionExtension[kCVImageBufferColorPrimariesKey]
            
            if let colorPrimaries = colorPrimaries {
                var colorSpaceProperties: [CFString: Any] = [kCVImageBufferColorPrimariesKey: colorPrimaries]
                
                if let yCbCrMatrix = inputFormatDescriptionExtension[kCVImageBufferYCbCrMatrixKey] {
                    colorSpaceProperties[kCVImageBufferYCbCrMatrixKey] = yCbCrMatrix
                }
                
                if let transferFunction = inputFormatDescriptionExtension[kCVImageBufferTransferFunctionKey] {
                    colorSpaceProperties[kCVImageBufferTransferFunctionKey] = transferFunction
                }
                
                //   pixelBufferAttributes[kCVBufferPropagatedAttachmentsKey as String] = colorSpaceProperties
            }
            
            if let cvColorSpace = inputFormatDescriptionExtension[kCVImageBufferCGColorSpaceKey] {
                colorSpace = cvColorSpace as! CGColorSpace
            } else if (colorPrimaries as? String) == (kCVImageBufferColorPrimaries_P3_D65 as String) {
                colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
            }
        }
        
        
        
        
        let poolOptions : [CFString : Any] = [kCVPixelBufferPoolMinimumBufferCountKey: 3]
        
        pixelBufferPool = nil
        
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolOptions as CFDictionary, pixelBufferAttributes as CFDictionary, &pixelBufferPool)
        
        guard let pixelBufferPool = pixelBufferPool else {
            assertionFailure("Allocation failure: Could not allocate pixel buffer pool")
            return
        }
        
        let poolAuxOptions : [CFString : Any] = [kCVPixelBufferPoolAllocationThresholdKey: 3]
        
        var testBuffer : CVPixelBuffer?
        
        CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pixelBufferPool, poolAuxOptions as CFDictionary, &testBuffer)
        
        preallocateBuffers(pool: pixelBufferPool, attributes: poolAuxOptions as CFDictionary)
        
        
        
        outputFormatDescriptor = nil
        
        if let testBuffer = testBuffer {
            CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, testBuffer, &outputFormatDescriptor)
      
        }
        
        
        self.outputPixelBufferAttributes = pixelBufferAttributes
        
        //pixelBufferPool = CVPixelBufferPool(
        
    }
    
    
    func preallocateBuffers( pool : CVPixelBufferPool, attributes : CFDictionary ) {
        
        var pixelBuffers =  [CVPixelBuffer]()
        
        while( true ) {
            
            var buffer : CVPixelBuffer? = nil
            
            let err : OSStatus = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, attributes, &buffer)
            
            if( err == kCVReturnWouldExceedAllocationThreshold ) {
                break
            }
            
            pixelBuffers.append(buffer!)
        }
        
        pixelBuffers.removeAll()
        
    }

    
    deinit {
        if(capturedImageTextureCache != nil) {
            CVMetalTextureCacheFlush(capturedImageTextureCache, 0);
        }
    }
}
