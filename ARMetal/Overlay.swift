//
//  Overlay.swift
//  ARMetal
//
//  Created by joshua bauer on 3/12/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 An `SCNNode` subclass demonstrating a basic use of `ARSCNFaceGeometry`.
 */
import Metal
import ARKit
import SceneKit
import CoreVideo
import MetalKit

class Overlay: SCNNode,VirtualFaceContent {
    
    var info: MaskInfo?
    
    var occlusionNode: SCNNode?
    
    var overlayNode: SCNNode?
    
    var worldNode : SCNNode?
    
    var faceNode : SCNNode?
    
    var needsEyeUpdate : Bool = false

    var overlaySKScene : SKScene?
    
    var device : MTLDevice
    
    var subdirectory : String?

    var lutTextures : [LUTType: MTLTexture?] = [:]
    
    var baseGeometry : SCNGeometry?
    
    var faceGeometry : ARSCNFaceGeometry
    
    lazy var colorParameters: ColorProcessingParameters = {
        
        return defaultColorProcessingParameters()
    }()
    
    lazy var blendShapeStates: [ARFaceAnchor.BlendShapeLocation: Float] = {
        
        var shapeStates: [ARFaceAnchor.BlendShapeLocation: Float] = [:]
        
        for shape in defaultBlendShapes {
            
            shapeStates[shape] = -1.0
            
        }
        
        return shapeStates
        
    }()
    
    lazy var textureLoader  : MTKTextureLoader = {
        return MTKTextureLoader(device:self.device)
    }()
 
    init(named : String, subdirectory: String? = "Models.scnassets", device : MTLDevice) {
        
        self.device = device
        
        
        faceGeometry = ARSCNFaceGeometry(device: device, fillMesh: false)!
        
        
        let sceneNode = loadSceneKitScene(named: named, subdirectory: subdirectory)!
        
        self.lutTextures = loadLookUpTables(node: sceneNode, subdirectory: subdirectory, device: device)

      
        
        overlayNode = sceneNode.childNode(withName: "overlay", recursively: true)
        
        faceNode = sceneNode.childNode(withName: "face", recursively: true)
        
        worldNode = sceneNode.childNode(withName: "world", recursively: true)
        
        if let faceGeometryNode = faceNode?.childNode(withName: "geometry", recursively: true) {
            
            if faceGeometryNode.isHidden {
                
                baseGeometry = faceGeometry
                
                baseGeometry?.firstMaterial!.colorBufferWriteMask = []
                
                occlusionNode = SCNNode(geometry: baseGeometry)
                occlusionNode!.renderingOrder = -1
                
            }
            else if let materials = faceGeometryNode.geometry?.materials {
                baseGeometry = loadAlternateTextureCoordinates(geometry: faceGeometry)
                baseGeometry?.materials =  materials
            }
        
        }
        
        
        super.init()
        
        for shape in defaultBlendShapes {
            
            blendShapeStates[shape] = -1.0
            
        }
        
        if let cameraNode = sceneNode.childNode(withName: "camera", recursively: true) {
            
            if let camera = cameraNode.camera {
                colorParameters.saturationIntensity = Float(camera.saturation)
                colorParameters.contrastIntensity = Float(camera.contrast)
            }
        }
        
        self.name = named
        
        self.subdirectory = subdirectory
        
        let referenceNode = loadReferenceNode()
        
        let occluderReference = referenceNode.childNode(withName: "occluder", recursively: true)!
        
        let occluder = occluderReference.clone()
 
        addChildNode(occluder)
        
        if occlusionNode != nil {
            addChildNode(occlusionNode!)
        }
        else if let geometry = baseGeometry {
            self.geometry = geometry
        }
        if overlayNode != nil {
            addChildNode(overlayNode!)
        }
  
       
        
        worldNode?.enumerateChildNodes { (node, _) in
            
            if node.name == "overlay" && node.childNodes.count > 0 {
                
                node.isHidden = true
                    
                let overlayNode = node.childNodes[0]
                
                if let skScene = createOverlaySKSceneFromNode(node: overlayNode, subdirectory: subdirectory) {
                    self.overlaySKScene = skScene
                }
                
            }
            
            if node.light != nil && node.constraints != nil {
                
                for constraint in node.constraints! {
                    
                    if let lookAt = constraint as? SCNLookAtConstraint {
                        lookAt.target = self
                    }
                }
                
            }
        }
        
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("\(#function) has not been implemented")
    }
    
    func loadSpecialMaterials() {
        
        if faceNode != nil {
            loadSpecialMaterialsForHierarchy(node: faceNode!, subdirectory: subdirectory)
        }
        
        if overlayNode != nil {
            
            loadSpecialMaterialsForHierarchy(node: overlayNode!, subdirectory: subdirectory )
        }
        
    }
    
    func mouthOpenness() -> Float {
        
        guard let value = blendShapeStates[ARFaceAnchor.BlendShapeLocation.jawOpen] else {
            return -1.0
        }
        
        return value
        
    }
    
    // MARK: VirtualFaceContent
    
    /// - Tag: SCNFaceGeometryUpdate
    func updateFaceAnchor(withFaceAnchor anchor: ARFaceAnchor) {
        
        //let faceGeometry = occlusionNode != nil ? occlusionNode!.geometry as!  ARSCNFaceGeometry :  faceGeometry
 
        faceGeometry.update(from: anchor.geometry)
        
        if blendShapeStates.count > 0 {
            processBlendShapes(blendShapes: anchor.blendShapes)
        }
        
    }


    
    func processBlendShapes( blendShapes: [ARFaceAnchor.BlendShapeLocation: Any] ) {
        
        for( location  ) in blendShapeStates.keys {
            
            if let value = blendShapes[location] as! Float? {
                 blendShapeStates[location] = value
            }
            
        }
        
        
    }
}


