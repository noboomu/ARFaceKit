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

class FaceMask: SCNNode, VirtualFaceContent {
    
    var info: MaskInfo?
    
    var worldNode : SCNNode?
    
    var faceNode : SCNNode?

    var needsEyeUpdate: Bool = false
    
    var irisNodes: [Eye:SCNNode]! = [Eye.left: SCNNode(), Eye.right: SCNNode()]
    
    var eyeNodes: [Eye:SCNNode]! = [Eye.left: SCNNode(), Eye.right: SCNNode()]
    
    var eyeKalmanFilters: [Eye:HCKalmanAlgorithm]?
    
    var device : MTLDevice
 
    var subdirectory : String?

    var baseGeometry : SCNGeometry?
    
    var needsCameraTexture: Bool = false
    
    var resetKalamanFilters : Bool = false
    
    var faceGeometry : ARSCNFaceGeometry
    
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
 
    var lutTextures : [LUTType: MTLTexture?] = [:]

    var overlaySKScene : SKScene?

    var usesCameraTexture : Bool = false
    
    lazy var colorParameters: ColorProcessingParameters = {
        
        return defaultColorProcessingParameters()
    }()
    
    
    init(named : String, subdirectory: String? = "Models.scnassets", device : MTLDevice) {
        
        
        self.device = device
        
        self.subdirectory = subdirectory
        
        faceGeometry = ARSCNFaceGeometry(device: device, fillMesh: false)!
        
        
        let sceneNode = loadSceneKitScene(named: named, subdirectory: subdirectory)!
        
        self.lutTextures = loadLookUpTables(node: sceneNode, subdirectory: subdirectory, device: device)

       
        
        worldNode = sceneNode.childNode(withName: "world", recursively: true)
        
        faceNode = sceneNode.childNode(withName: "face", recursively: true)
    
            
       if let faceGeometryNode = faceNode?.childNode(withName: "geometry", recursively: true) {
        
            baseGeometry = loadAlternateTextureCoordinates(geometry: faceGeometry)

            let materials = faceGeometryNode.geometry!.materials
        
            baseGeometry?.materials =  materials

            let firstMaterial = materials.first!
        
        
            let cameraTextureProperty = firstMaterial.value(forKeyPath: "cameraTexture") as? SCNMaterialProperty
        
            let displacementMapProperty = firstMaterial.value(forKeyPath: "displacementMap") as? SCNMaterialProperty

            if cameraTextureProperty != nil {
                
                print("found camera texture custom property")
                
                let placeholderTextureProperty = SCNMaterialProperty(contents: UIColor.clear)
                
                placeholderTextureProperty.mappingChannel = firstMaterial.diffuse.mappingChannel == 0 ? 1 : 0
                
                firstMaterial.setValue(placeholderTextureProperty, forKeyPath: "placeholderTexture")
                
                /*
                Use the opposite channel to store displacemnt
                */
                firstMaterial.setValue(firstMaterial.diffuse.mappingChannel == 0 ? 1 : 0, forKey: "displacementMappingChannel")
                
                var useDisplacement = false
                
                if displacementMapProperty == nil {
                    firstMaterial.setValue(nil, forKeyPath: "displacementMap")
                } else {
                    useDisplacement = true
                }
                
                print("useDisplacement: \(useDisplacement)")

                firstMaterial.setValue(useDisplacement ? 1 : 0, forKey: "useDisplacement")

                firstMaterial.setValue(1, forKey: "useLuma")

                var backgroundAverage : Float = defaultBackgroundAverage
                
                var backgroundInfluence : Float = defaultBackgroundInfluence
                
                if let currentBackgroundAverage = firstMaterial.value(forKeyPath: "backgroundAverage") as? Float {
                    backgroundAverage = currentBackgroundAverage
                }
                
                if let currentBackgroundInfluence = firstMaterial.value(forKeyPath: "backgroundInfluence") as? Float {
                    backgroundInfluence = currentBackgroundInfluence
                }
                
                firstMaterial.setValue(backgroundAverage, forKeyPath: "backgroundAverage")

                firstMaterial.setValue(backgroundInfluence, forKeyPath: "backgroundInfluence")
                
                print("backgroundAverage: \(backgroundAverage)")

                print("backgroundInfluence: \(backgroundInfluence)")

                if firstMaterial.shaderModifiers == nil {
                    firstMaterial.shaderModifiers = [:]
                }
                
                if firstMaterial.shaderModifiers?[SCNShaderModifierEntryPoint.fragment] == nil && !useDisplacement {
                    
                    print("use makeup fragment modifier")
                    
                    if let fragmentModifier = makeupFragmentModifierSource() {
                        firstMaterial.shaderModifiers?[SCNShaderModifierEntryPoint.fragment] = fragmentModifier
                    }
                    
                }
                
                if firstMaterial.shaderModifiers?[SCNShaderModifierEntryPoint.fragment] == nil && useDisplacement {

                    print("use displacement makeup fragment modifier")

                    if let fragmentModifier = displacementFragmentModifierSource() {
                        firstMaterial.shaderModifiers?[SCNShaderModifierEntryPoint.fragment] = fragmentModifier
                    }

                }
                
                if firstMaterial.shaderModifiers?[SCNShaderModifierEntryPoint.geometry] == nil && useDisplacement {
                    
                    print("use displacement geometry modifier")

                    if let geoemetryModifier = displacementGeometryModifierSource() {
                        firstMaterial.shaderModifiers?[SCNShaderModifierEntryPoint.geometry] = geoemetryModifier
                    }
                    
                }
                
                
                self.needsCameraTexture = true
                
            } else {
                self.needsCameraTexture = false
            }
        

            baseGeometry?.materials =  materials
        
        } else {
             baseGeometry = faceGeometry
        }
        
        

        let eyeMaterial = SCNMaterial()
        eyeMaterial.diffuse.contents = UIColor.clear
        eyeMaterial.writesToDepthBuffer = false
        eyeMaterial.readsFromDepthBuffer = true
        
        let eyePlane = SCNPlane(width:0.23, height:0.23)
        
        self.eyeNodes[.left] = SCNNode(geometry: eyePlane)
        
        self.irisNodes[.left]!.renderingOrder = 2
        self.irisNodes[.left]!.opacity = 0.0
        
        self.eyeNodes[.right] = SCNNode(geometry: eyePlane)
        
        self.irisNodes[.right]!.renderingOrder = 2
        self.irisNodes[.right]!.opacity = 0.0
        
        if let eyeLeftNode = faceNode?.childNode(withName: "eyeLeft", recursively: true) {
            
            let eyeMaterial = eyeLeftNode.geometry?.firstMaterial
            self.irisNodes[.left]!.geometry = eyeLeftNode.geometry
            self.irisNodes[.left]!.geometry?.firstMaterial = eyeMaterial
            
            needsEyeUpdate = true
            
        } else {
            self.irisNodes[.left]?.isHidden = true
            self.eyeNodes[.left]?.isHidden = true
        }
        
        if let eyeRightNode = faceNode?.childNode(withName: "eyeRight", recursively: true) {
            
            let eyeMaterial = eyeRightNode.geometry?.firstMaterial
            self.irisNodes[.right]!.geometry = eyeRightNode.geometry
            self.irisNodes[.right]!.geometry?.firstMaterial = eyeMaterial
            
            needsEyeUpdate = true
            
        } else {
            self.irisNodes[.right]?.isHidden = true
            self.eyeNodes[.right]?.isHidden = true
        }
        
//        baseGeometry?.materials.first?.shaderModifiers?[SCNShaderModifierEntryPoint.surface] =  cameraDiffuseSurfaceModifier()
        
        super.init()
        
        self.name = named
        self.geometry = baseGeometry

        if let cameraNode = sceneNode.childNode(withName: "camera", recursively: true) {
            
            if let camera = cameraNode.camera {
                colorParameters.saturationIntensity = Float(camera.saturation)
                colorParameters.contrastIntensity = Float(camera.contrast)
            }
        }
        
        worldNode?.enumerateChildNodes { (node, _) in
            
            
            if node.name == "overlay" && node.childNodes.count > 0 {
                
                node.isHidden = true
                
                let overlayNode = node.childNodes[0]
                
                if let skScene = createOverlaySKSceneFromNode(node: overlayNode, subdirectory: subdirectory) {
                    self.overlaySKScene = skScene
                    
                }
            }
            
            
            // MARK: World Lights and Constraints
            
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
        
        print("done loading specials")
        
    }
     // MARK: State
    
    func setTracking( isTracking: Bool ) {
        
        if isTracking {
            if( opacity == 0.0 )  {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.3
                self.opacity = 1.0
                
                for eye in [Eye.left,Eye.right] {
                    
                    let irisNode = self.irisNodes[eye]
                    
                    if irisNode != nil && irisNode?.isHidden == false   {
                        irisNode?.opacity = 1.0
                    }
                    
                }
                
                
                SCNTransaction.commit()
            }
        }
        else {
            if( opacity == 1.0 )
            {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.3
                self.opacity = 0.0
                
                for eye in [Eye.left,Eye.right] {
                    
                    let irisNode = self.irisNodes[eye]
                    
                    if irisNode != nil && irisNode?.isHidden == false   {
                        irisNode?.opacity = 0.0
                    }
              
                 }
                
                SCNTransaction.commit()
            }
        }
    }
    
    func toggleEyeVisiblility( eye: Eye, node : SCNNode?, isVisible: Bool ) {
        
        if isVisible {
            
            if node != nil && node?.isHidden == false  && node?.opacity == 0.0  {
                node?.opacity = 1.0
                resetKalamanFilters = true
            }
            
        } else {
            
            if node != nil && node?.isHidden == false  && node?.opacity == 1.0  {
                node?.opacity = 0.0
            }
            
        }
        
    }
    
    func setEyeStates( states : [Eye:EyeState] )  {
        
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.3
        
        for eye in [Eye.left,Eye.right] {
            
            let irisNode = self.irisNodes[eye]
            let eyeState = states[eye]!
            
            switch eyeState {
            case .closed, .unknown:
                toggleEyeVisiblility(eye: eye, node: irisNode, isVisible: false)
                
            case .open:
                toggleEyeVisiblility(eye: eye, node: irisNode, isVisible: true)
            }
            
        }
        
        SCNTransaction.commit()
        
    }
    
    // MARK: Updates
    
    func updateFaceAnchor(withFaceAnchor anchor: ARFaceAnchor) {
        
        //let faceGeometry = faceGeometry
      
        faceGeometry.update(from: anchor.geometry)
        
        if blendShapeStates.count > 0 {
            processBlendShapes(blendShapes: anchor.blendShapes)
        }
    }
    
    func updateCameraTexture(withCameraTexture texture: MTLTexture) {
 
        
        guard let material = geometry?.materials.first else { return }
        
        if material.value(forKey: "cameraTexture") != nil {
            let cameraTextureProperty = material.value(forKey: "cameraTexture") as! SCNMaterialProperty

            cameraTextureProperty.contents = texture
        }
    }
    
    
    func updateEyeGeometry( eyeScale: Float, leftEyeCenter: vector_float3, leftEyeGaze: vector_float3, rightEyeCenter: vector_float3, rightEyeGaze: vector_float3, xScale: Float ) {

        let scale =   0.46080 * self.simdPosition.z + 0.303
        
        var leftXY = float2(x:leftEyeCenter.x ,y:leftEyeCenter.y )
        var rightXY = float2(x:rightEyeCenter.x ,y:rightEyeCenter.y )
        
        
        if eyeKalmanFilters == nil {
            eyeKalmanFilters =  [Eye.left: HCKalmanAlgorithm(initialLocation: leftXY ), Eye.right: HCKalmanAlgorithm(initialLocation: rightXY )]
            
        } else {
            
            if(resetKalamanFilters) {
                eyeKalmanFilters![Eye.left]!.resetKalman(newStartLocation: leftXY)
                eyeKalmanFilters![Eye.right]!.resetKalman(newStartLocation: rightXY)
                resetKalamanFilters = false
            } else {
               leftXY = eyeKalmanFilters![Eye.left]!.processState(currentLocation: &leftXY)
               rightXY = eyeKalmanFilters![Eye.right]!.processState(currentLocation: &rightXY)
            }
        }
        
        let leftIrisNode = irisNodes[.left]
        
        if leftIrisNode != nil && leftIrisNode?.isHidden == false {
            
            if  leftIrisNode?.parent == nil {
                self.parent?.addChildNode(leftIrisNode!)
            }
            
            let eyeVector = vector_float3(leftXY.x, leftXY.y, -xScale)
     
            leftIrisNode!.simdPosition = eyeVector
      
            leftIrisNode!.simdLook(at: eyeVector - leftEyeGaze * (xScale * 10.0), up:  self.simdWorldUp, localFront:  -self.simdWorldFront )

            leftIrisNode!.simdScale = vector_float3(scale,scale,scale)
            
        }
        
        let rightIrisNode = irisNodes[.right]

        if rightIrisNode != nil && rightIrisNode?.isHidden == false   {
            
            if rightIrisNode?.parent == nil {
                self.parent?.addChildNode(rightIrisNode!)
            }
            
            let eyeVector = vector_float3(rightXY.x, rightXY.y, -xScale)

            
            rightIrisNode!.simdPosition = eyeVector
            
            rightIrisNode!.simdLook(at: eyeVector - rightEyeGaze * (xScale * 10.0), up: self.simdWorldUp, localFront:  -self.simdWorldFront )

            rightIrisNode!.simdScale = vector_float3(scale,scale,scale)
 
        }
        
    }
    
   
    func processBlendShapes( blendShapes: [ARFaceAnchor.BlendShapeLocation: Any] ) {
        
        for( location  ) in blendShapeStates.keys {
            
            if let value = blendShapes[location] as! Float? {
                blendShapeStates[location] = value
            }
            
        }
        
    }
    
    func mouthOpenness() -> Float {
        
        guard let value = blendShapeStates[ARFaceAnchor.BlendShapeLocation.jawOpen] else {
            return -1.0
        }
        
        return value
        
    }
    
    override func removeFromParentNode() {
        
        super.removeFromParentNode()
        
        for eye in [Eye.left,Eye.right] {
            
            let irisNode = irisNodes[eye]
            
            irisNode?.removeFromParentNode()
            
            let eyeNode = eyeNodes[eye]
            
            eyeNode?.removeFromParentNode()
            
        }
        
    }
    
    deinit {
        
        
       
        
    }
}


