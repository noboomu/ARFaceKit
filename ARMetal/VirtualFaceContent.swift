import ARKit
import SceneKit
import AVFoundation
import Metal
import MetalKit
import SpriteKit
import CoreGraphics
import Accelerate

enum LUTType {
    case face, camera, overlay, world
}

enum Eye {
    case left,right
}

enum EyeState {
    case open,closed,unknown
}

enum MaskType {
    case face, mask, remote
}

let defaultBackgroundInfluence : Float = 1.2

let defaultBackgroundAverage : Float = 0.5

var referenceNode : SCNReferenceNode?

let defaultBlendShapes : [ARFaceAnchor.BlendShapeLocation] = [ARFaceAnchor.BlendShapeLocation.eyeBlinkLeft,ARFaceAnchor.BlendShapeLocation.eyeBlinkRight,ARFaceAnchor.BlendShapeLocation.jawOpen]

var alternateTextureCoordinates = [CGPoint]()

var alternateTexCoordSource : SCNGeometrySource?

var makeupFragmentModifier : String?

var displacementFragmentModifier : String?

var displacementGeometryModifier : String?

protocol VirtualFaceContent {
    
    func updateFaceAnchor(withFaceAnchor: ARFaceAnchor)
    
    func updateCameraTexture(withCameraTexture: MTLTexture)
    
    func updateEyeGeometry( eyeScale: Float, leftEyeCenter: vector_float3, leftEyeGaze: vector_float3, rightEyeCenter: vector_float3, rightEyeGaze: vector_float3, xScale: Float )
    
 
    func setTracking( isTracking: Bool )
    
    func setEyeStates( states : [Eye:EyeState] )
    
    func mouthOpenness() -> Float
    
    func processBlendShapes( blendShapes: [ARFaceAnchor.BlendShapeLocation: Any] )
    
    func loadSpecialMaterials()
    
    var device : MTLDevice { get }
    
    var info : MaskInfo? { get set }
    
    var overlaySKScene : SKScene? { get }
    
    var worldNode : SCNNode? { get }
    
    var needsEyeUpdate : Bool { get }
    
    var needsCameraTexture : Bool { get }
    

    var textureLoader : MTKTextureLoader { get }

    var blendShapeStates: [ARFaceAnchor.BlendShapeLocation: Float] { get set }
    
    var lutTextures: [LUTType : MTLTexture?] { get }

    var colorParameters: ColorProcessingParameters { get set }

}


typealias VirtualFaceNode = VirtualFaceContent & SCNNode

extension VirtualFaceContent where Self: SCNNode {
    
    func updateCameraTexture(withCameraTexture: MTLTexture) {
        
    }
    
    var needsCameraTexture: Bool {
        return false
    }
    
    func updateEyeGeometry( eyeScale: Float, leftEyeCenter: vector_float3, leftEyeGaze: vector_float3, rightEyeCenter: vector_float3, rightEyeGaze: vector_float3, xScale: Float )
    {
        
    }
    
    func setEyeStates( states : [Eye:EyeState] )  {
        
    }
    
    func lookupTables() -> [LUTType : MTLTexture]? {
        return nil
    }
    
    func setTracking( isTracking: Bool ) {
        
        if isTracking {
            if( opacity == 0.0 )  {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.3
                self.opacity = 1.0
                SCNTransaction.commit()
            }
        }
        else {
            if( opacity == 1.0 )
            {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.3
                self.opacity = 0.0
                SCNTransaction.commit()
            }
        }
    }
}

func defaultColorProcessingParameters() -> ColorProcessingParameters
{
    var parameters = ColorProcessingParameters()
    parameters.contrastIntensity = 0.0
    parameters.saturationIntensity = 1.0
    parameters.lutIntensity = 1.0
    
    return parameters
}

// MARK: Loading Content

func findResourceURL( named resourceName: String, subdirectory: String? ) -> URL? {
    
    var resourceURL : URL?
    
    var normalizedName: String? = resourceName
    
    if subdirectory != nil && resourceName.contains(subdirectory!) {
        
        normalizedName = String(resourceName.split(separator: "/").last!)
        
    }
    
    if let url = Bundle.main.url(forResource: normalizedName, withExtension: nil, subdirectory: subdirectory) {
        resourceURL = url
    } else {
        resourceURL = MaskInfo.getMaskCacheDirectoryURL().appendingPathComponent( subdirectory! + "/" + normalizedName! )
    }
    
    return resourceURL
}

func loadSceneKitScene(named: String, subdirectory: String? = "Models.scnassets" ) -> SCNNode? {
    
    var finalName : String? = named + ".scn"
    
    
    if let sub = subdirectory {
        
            if sub != "Models.scnassets" {
            let scnPath = findSCNFilePath(subdirectory:sub)
            
            if scnPath == nil {
                print("scn path is nil!!!")
            }
            
            if scnPath?.lastPathComponent != nil {
                 finalName = scnPath?.lastPathComponent
            }
        }
    }
    
    print("finalName: \(finalName!)")
    
    if let url = findResourceURL( named: finalName!, subdirectory: subdirectory ) {
        
        
  
        if let node = SCNReferenceNode(url: url) {
            node.load()
            return node
        }
    }
 
    
    return SCNNode()
    
}

private func findSCNFilePath( subdirectory : String ) -> URL? {
    
    let keys = [URLResourceKey.isDirectoryKey, URLResourceKey.localizedNameKey]
    let options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants, .skipsSubdirectoryDescendants, .skipsHiddenFiles]
    let fileManager = FileManager.default

    var url : URL? = MaskInfo.getMaskCacheDirectoryURL().appendingPathComponent( subdirectory   )

    print("file url \(url!) path: \(url!.relativePath)")

    var resourceURL : URL?
    
    if fileManager.fileExists(atPath: url!.relativePath) {
        resourceURL = url
    } else {
        
        url = Bundle.main.bundleURL.appendingPathComponent( subdirectory )
        
         if fileManager.fileExists(atPath: url!.relativePath) {
            resourceURL = url
        }
    }
    
    if resourceURL == nil {
        return nil
    }
    
    let enumerator = fileManager.enumerator(
        at: resourceURL!,
        includingPropertiesForKeys: keys,
        options: options,
        errorHandler: {(url, error) -> Bool in
            return true
    })
    
    if enumerator != nil {
        while let file = enumerator!.nextObject() {
            let pathURL = file as! URL
            let path = pathURL.path
            if path.hasSuffix(".scn"){
                return pathURL
            }
        }
    }
    
    return nil
}



func loadReferenceNode() -> SCNNode {
    if referenceNode == nil {
        
        let url = Bundle.main.url(forResource: "reference", withExtension: "scn", subdirectory: "Models.scnassets")
        let node = SCNReferenceNode(url: url!)!
        node.load()
        referenceNode = node
    }
    
    return referenceNode!
}

func makeupFragmentModifierSource() -> String? {
    
    if makeupFragmentModifier != nil {
        return makeupFragmentModifier!
    }
    
    if let sourcePath = Bundle.main.url(forResource: "makeupFragment", withExtension: "scnmodifier", subdirectory: nil) {
        if let data = try? Data(contentsOf: sourcePath.standardizedFileURL) {
            makeupFragmentModifier = String(decoding: data, as: UTF8.self)
        }
    }

    return makeupFragmentModifier!
    
}

func displacementGeometryModifierSource() -> String? {
    
    if displacementGeometryModifier != nil {
        return displacementGeometryModifier!
    }
    
    if let sourcePath = Bundle.main.url(forResource: "displacementGeometry", withExtension: "scnmodifier", subdirectory: nil) {
        if let data = try? Data(contentsOf: sourcePath.standardizedFileURL) {
            displacementGeometryModifier = String(decoding: data, as: UTF8.self)
        }
    }
    
    return displacementGeometryModifier!
    
}


func displacementFragmentModifierSource() -> String? {
    
    if displacementFragmentModifier != nil {
        return displacementFragmentModifier!
    }
    
    if let sourcePath = Bundle.main.url(forResource: "displacementFragment", withExtension: "scnmodifier", subdirectory: nil) {
        if let data = try? Data(contentsOf: sourcePath.standardizedFileURL) {
            displacementFragmentModifier = String(decoding: data, as: UTF8.self)
        }
    }
    
    return displacementFragmentModifier!
    
}


func loadAlternateTextureCoordinates( geometry : SCNGeometry ) -> SCNGeometry? {
    
    var newSources = [SCNGeometrySource]()
    var newGeometry : SCNGeometry?

    if alternateTextureCoordinates.count == 0 {
        
        if let uvPath = Bundle.main.url(forResource: "alternateCoords", withExtension: "plist", subdirectory: nil) {
            
            guard let allValues =  NSArray(contentsOfFile: uvPath.path) as? [Float] else { return nil }
            
            let pairs = allValues.count/2
            for i in 0..<pairs {
                let offset = i * 2
                let x = allValues[offset]
                let y = allValues[offset+1]
                alternateTextureCoordinates.append(CGPoint(x:CGFloat(x),y:CGFloat(y)))
            }
        }
    }
    
    alternateTexCoordSource = SCNGeometrySource(textureCoordinates:alternateTextureCoordinates)

    let sources = geometry.sources
    
    let elements = geometry.elements
    
    newSources.append(sources[0])
    newSources.append(sources[1])
    newSources.append(sources[2])
    newSources.append(alternateTexCoordSource!)

    newGeometry = SCNGeometry(sources: newSources, elements: elements)
    
    return newGeometry
}

func loadTexture( loader: MTKTextureLoader, path: String ) -> MTLTexture? {
    
    let textureURL : URL? = findResourceURL(named: path, subdirectory: nil )
    
    var texture : MTLTexture?
    
    do {
        try texture = loader.newTexture(URL: textureURL!, options: [MTKTextureLoader.Option.SRGB : false])
    } catch let error {
        print("Failed to load texture, error \(error)")
        texture = nil
    }
    
    return texture
    
}

func loadTexture(  loader: MTKTextureLoader, named resourceName : String, subdirectory: String? = "Models.scnassets" ) -> MTLTexture? {
    
    let textureURL : URL? = findResourceURL(named: resourceName, subdirectory: subdirectory )
    
    var texture : MTLTexture?
    
    do {
        try texture = loader.newTexture(URL: textureURL!, options: [MTKTextureLoader.Option.SRGB : false])
    } catch let error {
        print("Failed to load texture, error \(error)")
        texture = nil
    }
    
    return texture
    
}

func load3DTexture(  named resourceName : String, subdirectory: String? = "Models.scnassets", device: MTLDevice ) -> MTLTexture? {
    
    guard let image = loadImage(named: resourceName, subdirectory: subdirectory)  else {
       // print("could not find texture's image: \(resourceName) in \(subdirectory)")
        return nil
    }
    
    let imageRef = image.cgImage!
    
    let width = imageRef.width
    let height = imageRef.height
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    
    let rawData = calloc(height * width * 4, MemoryLayout<UInt8>.stride)
    
    let bytesPerPixel = 4
    let bytesPerRow = bytesPerPixel * width
    let bitsPerComponent = 8
    
    let context = CGContext(data: rawData,
                            width: width,
                            height: height,
                            bitsPerComponent: bitsPerComponent,
                            bytesPerRow: bytesPerRow,
                            space: colorSpace,
                            bitmapInfo: imageRef.bitmapInfo.rawValue)
    
    context?.draw(imageRef, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    
    let descriptor = MTLTextureDescriptor()
    descriptor.textureType = .type3D
    descriptor.width = Int(height)
    descriptor.height = Int(height)
    descriptor.depth = Int(height)
    descriptor.pixelFormat = .bgra8Unorm
    descriptor.arrayLength = 1
    descriptor.mipmapLevelCount = 1
    
    var buffer = vImage_Buffer(data: rawData!, height: UInt(height), width: UInt(width), rowBytes: bytesPerRow)
    
    let map: [UInt8] = [1,2,0,3]
    
    vImagePermuteChannels_ARGB8888(&buffer, &buffer, map, 0)
    
    let texture = device.makeTexture(descriptor: descriptor)
    
    let region = MTLRegionMake3D(0, 0, 0, Int(height), Int(height),  Int(height))
    
    texture?.replace(region: region,
                     mipmapLevel: 0,
                     slice: 0,
                     withBytes: rawData!,
                     bytesPerRow: Int(height) * 4,
                     bytesPerImage: Int(height) * Int(height) * 4)
    
    free(rawData)
    
    return texture
}


func createAVPlayer( named resourceName : String, subdirectory: String? = "Models.scnassets"  ) ->  AVLoopedlayer? {
    
    let videoURL : URL? = findResourceURL(named: resourceName, subdirectory: subdirectory )
   
    
    let requiredAssetKeys = [
        "playable",
        "duration"
    ]
    
    let asset = AVURLAsset(url: videoURL!, options: nil)
    
    let  playerItem : AVPlayerItem = AVPlayerItem(asset: asset,automaticallyLoadedAssetKeys: requiredAssetKeys)
    
    let player = AVLoopedlayer(playerItem: playerItem)
    
    player.loopPlayback =  true
    
    return player
    
}

func createSKSceneFromImage( named resourceName : String, subdirectory: String? = "Models.scnassets"  ) -> SKScene? {
    
    guard let image = loadImage(named: resourceName, subdirectory: subdirectory ) else {
          return nil
    }
    
    let skTexture = SKTexture(image: image)
    
    let skScene = SKScene(size: UIScreen.main.bounds.size)
  
    skScene.anchorPoint = CGPoint(x:0.5,y:0.5)

    let spriteNode = SKSpriteNode(texture: skTexture)
    
   // spriteNode.anchorPoint = CGPoint(x:0.5,y:0.5)
    
    skScene.addChild(spriteNode)
    

    return skScene
    
}

func loadSpecialMaterialsForHierarchy( node : SCNNode, subdirectory : String? = "Models.scnassets" ) {
    
    var materialNames = Set<String>()
    
    node.enumerateChildNodes { (childNode, _) in
        
        if let material = childNode.geometry?.firstMaterial {
            
            if let name = material.name  {
                
                if name.contains(".plist") && !materialNames.contains(name) {
                    
                    print("loading plist")
                    
                    if let skScene = loadSpriteAnimationScene( named: name, subdirectory: subdirectory ) {
                        
                        materialNames.insert(name)
                        
                        if let animatedNode  = skScene.children[0] as? AnimatedSpriteNode {
                            
                            if let animationRate = material.value(forKeyPath: "rate") as? Double {
                                animatedNode.animateAtRate(rate: TimeInterval( animationRate ) )
                            } else {
                                animatedNode.animateAtRate(rate: TimeInterval( 0.2 ) )
                            }
                            
                        }
                        
                        if material.diffuse.contents as? UIColor ==  UIColor.white {
                            childNode.geometry!.firstMaterial!.diffuse.contents = skScene
                        } else if material.reflective.contents as? UIColor ==  UIColor.white {
                            childNode.geometry!.firstMaterial!.reflective.contents = skScene
                        }
                        
                    }
                    
                    print("plist loaded")
                }
                else if name.contains(".sks") && !materialNames.contains(name) {
                    
                    print("loading sks")
                    
                    if let skScene = loadSKScene( named: name, subdirectory: subdirectory ) {
                        
                        materialNames.insert(name)
                        
                        skScene.isPaused = false
                        
                        if material.diffuse.contents as? UIColor ==  UIColor.white {
                            childNode.geometry!.firstMaterial!.diffuse.contents = skScene
                        } else if material.reflective.contents as? UIColor ==  UIColor.white {
                            childNode.geometry!.firstMaterial!.reflective.contents = skScene
                        }
                    }
                }
                else if name.contains(".mp4") && !materialNames.contains(name) {
                    
                    print("loading mp4")
                    
                    if let player = createAVPlayer(named: name, subdirectory: subdirectory) {
                        
                        materialNames.insert(name)
                        
                        if material.diffuse.contents as? UIColor ==  UIColor.white {
                            childNode.geometry!.firstMaterial!.diffuse.contents = player
                        } else if material.reflective.contents as? UIColor ==  UIColor.white {
                            childNode.geometry!.firstMaterial!.reflective.contents = player
                        }
                    }
                }
            }
        }
        
    }
}


func createOverlaySKSceneFromNode( node : SCNNode, subdirectory: String? = "Models.scnassets" ) -> SKScene? {
    
    var skScene : SKScene?
    
    if let material = node.geometry?.firstMaterial {
        
        if let name = material.name {
            if name.contains(".plist") {
                
                skScene = loadSpriteAnimationScene( named: name, subdirectory: subdirectory! )
                
                if let animatedNode  = skScene?.children[0] as? AnimatedSpriteNode {
                   
                    if let animationRate = material.value(forKeyPath: "rate") as? Double {
                        animatedNode.animateAtRate(rate: TimeInterval( animationRate ) )
                    } else {
                        animatedNode.animateAtRate(rate: TimeInterval( 0.2 ) )
                    }
                    
                }
                
            } else  if name.contains(".sks") {
                skScene = loadSKScene( named: name, subdirectory: subdirectory! )
            }
        }
        
        if let textureName = material.diffuse.contents as? String  {
            
            
            skScene = createSKSceneFromImage( named: textureName, subdirectory: subdirectory )
     
            
        }
        
        
 
        if let spriteNode  = skScene?.children[0] as? SKSpriteNode  {
        
            spriteNode.xScale = CGFloat(node.scale.x)
            spriteNode.yScale = CGFloat(node.scale.y)
        
            spriteNode.position = CGPoint( x:( CGFloat(node.position.x ) * skScene!.size.width) , y: (CGFloat(node.position.y) * skScene!.size.height ))
            
        }
        
        
    }
    
    return skScene
}


func loadSKScene( named resourceName : String, subdirectory : String? = "Models.scnassets"  ) -> SKScene? {
    
    let dataURL: URL? =  findResourceURL(named: resourceName, subdirectory: subdirectory )

    
    guard FileManager.default.fileExists(atPath: dataURL!.standardizedFileURL.relativePath) else {
        print("scene not found")
        return nil
    }
    
 
    var skScene : SKScene?
   
    do {
        let data = try Data(contentsOf: dataURL!.standardizedFileURL)
        //let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        let archiver = NSKeyedUnarchiver(forReadingWith: data)
        archiver.setClass(SKScene.classForKeyedUnarchiver(), forClassName: "SKScene")
        skScene = archiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? SKScene
        archiver.finishDecoding()
    } catch let error {
        print("Failed to load skScene, error \(error)")
        return nil
    }
    

    return skScene
}

func loadSpriteAnimationScene( named resourceName : String, subdirectory : String? = "Models.scnassets"  ) -> SKScene? {
    
   let skScene = SKScene(size: UIScreen.main.bounds.size)

    skScene.anchorPoint = CGPoint(x:0.5,y:0.5)
    
    let spriteAnimationNode =  AnimatedSpriteNode( fromPlist: resourceName, subdirectory: subdirectory)
    
    spriteAnimationNode.position = CGPoint(x: 0.0, y: 0.0 )
    
    skScene.addChild(spriteAnimationNode)
    
    return skScene
}

func loadImage(  named resourceName : String, subdirectory : String? = "Models.scnassets"  ) -> UIImage? {
    
    let imageURL: URL?  =  findResourceURL(named: resourceName, subdirectory: subdirectory )
    
    guard FileManager.default.fileExists(atPath: imageURL!.standardizedFileURL.relativePath) else {
        print("image not found at \(imageURL!.standardizedFileURL.relativePath)")
        return nil
    }
    
    var imageData : Data?
    
    do {
        try imageData = Data.init(contentsOf: imageURL!.standardizedFileURL)
    } catch let error {
        print("Failed to load image, error \(error)")
        return nil
    }
    
    let image = UIImage(data: imageData!)
    
    return image
}


func getDiffuseMaterialName( node: SCNNode ) -> String? {
    
 
    if let materialContents = node.geometry?.firstMaterial?.diffuse.contents {
        
        if let name = materialContents as? String  {
            
            return name
        }
        
    }
 
    return nil
   
    
}

func loadLookUpTables( node : SCNNode , subdirectory : String? = "Models.scnassets", device: MTLDevice  ) -> [LUTType: MTLTexture] {
    
    var tables: [LUTType: MTLTexture] = [:]
    
    var nodesToRemove = [SCNNode]()
    
    for childNode in node.childNodes {
        
        if let name = childNode.name {
            
            var lutNode : SCNNode?
            var lutType : LUTType?
            
            switch name {
                case "world":
                    lutNode = childNode.childNode(withName: "lut", recursively: false)
                    lutType = LUTType.world
                case "overlay":
                    lutNode = childNode.childNode(withName: "lut", recursively: false)
                    lutType = LUTType.overlay
                case "face":
                    lutNode = childNode.childNode(withName: "lut", recursively: false)
                    lutType = LUTType.face
                case "camera":
                    lutNode = childNode.childNode(withName: "lut", recursively: false)
                    lutType = LUTType.camera
                default:
                    break
            }
            
            if lutNode != nil && lutType != nil {
                if let lutName = getDiffuseMaterialName( node: lutNode! ) {
                    tables[lutType!] = load3DTexture(named: lutName, subdirectory: subdirectory, device: device)
                    nodesToRemove.append(lutNode!)
                }
            }
        }
        
        
    }
    
    for lutNode in nodesToRemove {
        
        lutNode.removeFromParentNode();
        
    }
    
    
    return tables
}

func cameraDiffuseSurfaceModifier() -> String {
    return  "// Surface Modifier\n" +
        "float2 coords = float2(in.fragmentPosition.xy*scn_frame.inverseResolution.xy-1.);\n" +
    "_surface.diffuse = u_diffuseTexture.sample( sampler(coord::normalized,filter::linear,address::clamp_to_zero), float2(1.0 + coords.x,1.0 + coords.y));\n" +
  ""//  "_surface.diffuse = _surface.diffuse + float4(0.0,0.1,0.1,0.1);\n"
}
 

