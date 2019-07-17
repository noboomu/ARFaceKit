//
//  ViewController.swift
//  ARMetal
//
//  Created by joshua bauer on 3/7/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

import UIKit
import Metal
import MetalKit
import ARKit

 
class MetalViewController: UIViewController, MTKViewDelegate, ARSessionDelegate {
   
    var session: ARSession!
    var renderer: Renderer!
    var device: MTLDevice!
    var scene: SCNScene!
    var currentFaceNodeName: String?
    var isRecording: Bool = false
    var assetWriter : RenderedVideoWriter?
    var maskIndex = 0
    
    var maskRecords = [MaskInfo]()
    
    var currentFaceNode: VirtualFaceNode?
    
    var masks = [ "geo2":MaskType.face,
                  "Bowie2":MaskType.face]
    
    var maskNames = [
        "geo2",
        "Bowie2"]
    
    //  var renderDestination : RenderDestination!
    @IBOutlet weak var mtkView: MTKView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        session = ARSession()
        session.delegate = self
        
        scene = SCNScene()
        
        
        Utilities.clearCacheDirectory()
        
        
        // fetchMaskData
     
        
        Utilities.fetchMaskData( id: 37 ) { (info) in
            
            print("data \(info!)")
            
            var infoRef = info!
            
            MaskInfo.synchronizeMaskContent(info: infoRef, completionHandler: { (url) in
                
                infoRef.localBasePath = url?.path
                
                do {
                    
                    let tmpDirectory = try FileManager.default.contentsOfDirectory(atPath: url!.path)
                    
                    try tmpDirectory.forEach { file in
                        let fileUrl = url!.appendingPathComponent(file)
                        print("is sub file \(file)")
                    } } catch {
                        print("error clearing cache directory: \(error)")
                }
                DispatchQueue.main.async {
                    self.maskRecords.append(infoRef)
                    self.maskNames.append(infoRef.name)
                    self.masks[infoRef.name] = MaskType.remote
                    
                    print("data \(infoRef)")
                    
                    print("records:\n \(self.maskRecords)")
                    
                    print("maskNames:\n \(self.maskNames)")
                    
                }
                
            })
            
        }
        
        Utilities.fetchMaskData( id: 38 ) { (info) in
            
            print("data \(info!)")
            
            var infoRef = info!
            
            MaskInfo.synchronizeMaskContent(info: infoRef, completionHandler: { (url) in
                
                infoRef.localBasePath = url?.path
                
                do {
                    
                    let tmpDirectory = try FileManager.default.contentsOfDirectory(atPath: url!.path)
                    
                    try tmpDirectory.forEach { file in
                        let fileUrl = url!.appendingPathComponent(file)
                        print("is sub file \(file)")
                    } } catch {
                        print("error clearing cache directory: \(error)")
                }
                DispatchQueue.main.async {
                    self.maskRecords.append(infoRef)
                    self.maskNames.append(infoRef.name)
                    self.masks[infoRef.name] = MaskType.remote
                    
                    print("data \(infoRef)")
                    
                    print("records:\n \(self.maskRecords)")
                    
                    print("maskNames:\n \(self.maskNames)")
                    
                }
                
            })
            
        }
        
        
//        Utilities.fetchMaskData( id: 37 ) { (info) in
//
//            print("mask data \(info!.id)  \(info!.name)")
//
//            MaskInfo.synchronizeMaskContent(info: info!, completionHandler: { (url) in
//
//                info!.localBasePath = url?.path
//
//                do {
//
//                    let tmpDirectory = try FileManager.default.contentsOfDirectory(atPath: url!.path)
//
//                    try tmpDirectory.forEach { file in
//                        let fileUrl = url!.appendingPathComponent(file)
//                        print("is sub file \(file)")
//                    } } catch {
//                        print("error clearing cache directory: \(error)")
//                }
//                DispatchQueue.main.sync {
//                    self.maskRecords.append(info!)
//                    self.maskNames.append(info!.name)
//                    self.masks[info!.name] = MaskType.remote
//
//                    print("data \(info!)")
//
//                    print("records:\n \(self.maskRecords)")
//
//                    print("maskNames:\n \(self.maskNames)")
//
//                }
//
//            })
//
//        }
        
//        Utilities.fetchMaskData( id: 315 ) { (info) in
//
//            print("data \(info!)")
//
//            var infoRef = info!
//
//            MaskInfo.synchronizeMaskContent(info: infoRef, completionHandler: { (url) in
//
//                infoRef.localBasePath = url?.path
//
//                DispatchQueue.main.async {
//                    self.maskRecords.append(infoRef)
//
//                    print("data \(infoRef)")
//                }
//
//            })
//
//        }
//
//        Utilities.fetchMaskData( id: 312 ) { (info) in
//
//            print("data \(info!)")
//
//            var infoRef = info!
//
//            MaskInfo.synchronizeMaskContent(info: infoRef, completionHandler: { (url) in
//
//                infoRef.localBasePath = url?.path
//
//                DispatchQueue.main.async {
//                self.maskRecords.append(infoRef)
//
//                print("data \(infoRef)")
//                }
//
//            })
//
//        }
//
//        Utilities.fetchMaskData( id: 318 ) { (info) in
//
//            print("data \(info!)")
//
//            var infoRef = info!
//
//            MaskInfo.synchronizeMaskContent(info: infoRef, completionHandler: { (url) in
//
//                infoRef.localBasePath = url?.path
//
//                DispatchQueue.main.async {
//                    self.maskRecords.append(infoRef)
//
//                    print("data \(infoRef)")
//                }
//
//            })
//
//        }
        
 
        
        
        // Set the view to use the default device
        if let mtkView = self.mtkView  {
            mtkView.device = MTLCreateSystemDefaultDevice()
            mtkView.backgroundColor = UIColor.clear
            mtkView.delegate = self
            
            
          
            
            guard mtkView.device != nil else {
                print("Metal is not supported on this device")
                return
            }
            
            self.device = mtkView.device!

          //  let faceNode = Overlay(named: "Aviator",subdirectory: "Aviator.scnassets", device: self.device)
            
            let faceNode = FaceMask(named: "geo2",subdirectory: "geo2.scnassets", device: self.device)
//            let faceNode = FaceMask(named: "Daz",subdirectory: "Models.scnassets", device: self.device)

            currentFaceNodeName = faceNode.name
            
            currentFaceNode = faceNode
            // Configure the renderer to draw to the view
            renderer = Renderer(session: session, metalDevice: mtkView.device!, renderDestination: mtkView, sceneKitScene: scene)
            
 
            renderer.drawRectResized(size: view.bounds.size)
            
            renderer.faceContentNode = faceNode

        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(MetalViewController.handleTap(gestureRecognize:)))
        view.addGestureRecognizer(tapGesture)
    }
    
    func resetTracking() {
        
        guard ARFaceTrackingConfiguration.isSupported else { return }
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        configuration.providesAudioData = true
        configuration.worldAlignment = .gravity
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    func createFaceGeometry() {
        // This relies on the earlier check of `ARFaceTrackingConfiguration.isSupported`.
        
        
        
        //        nodeForContentType = [
        //            .faceGeometry: Mask(geometry: maskGeometry),
        //            .overlayModel: GlassesOverlay(geometry: glassesGeometry),
        //            .blendShapeModel: RobotHead()
        //        ]
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        resetTracking();
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    
    
    @IBAction func buttonPressed(_ sender: Any) {
        
        
        self.maskIndex = self.maskIndex + 1
        
        var mask : VirtualFaceNode?

        
//        if self.maskRecords.count > 0 {
//
//            var info = self.maskRecords[self.maskIndex % self.maskRecords.count]
//
//            let name = info.name
//
//            let folderName = info.assetFolderName
//
//        //    print("assetFolderName: \(folderName)")
//
//            let subdirectory = name + "/" + folderName
//
//            switch info.type! {
//                case MaskInfo.MaskType.face:
//                    mask = FaceMask( named: name, subdirectory: subdirectory, device: self.device)
//                case MaskInfo.MaskType.mask:
//                    mask = Overlay( named: name, subdirectory: subdirectory, device: self.device)
//                case MaskInfo.MaskType.filter,MaskInfo.MaskType.scene:
//                    return
//            }
//
//        } else {
        
            let name = maskNames[self.maskIndex % masks.count]
            
            let entry = masks[name]
            
 
            switch entry! {
                
            case MaskType.face:
                mask = FaceMask( named: name, subdirectory: name + ".scnassets", device: self.device)
            case MaskType.remote:
                 mask = Overlay( named: name, subdirectory: name + "/" + name + ".scnassets", device: self.device)
            case MaskType.mask:
                 mask = Overlay( named: name, subdirectory: name + ".scnassets", device: self.device)
            }
            
        //}
        
         renderer.faceContentNode = mask

        
    }
    
    
    @IBAction func recordPressed(_ sender: UIButton) {
        
        //        session.pause()
        
        if( isRecording  )
        {
          isRecording = false
         
          renderer.pixelBufferConsumer = nil
            
            sender.setTitle("REC" , for: UIControlState.normal)

          assetWriter?.stopRecording()
            
            mtkView.preferredFramesPerSecond = 60
 
        }
        else
        {
           isRecording = true
            mtkView.preferredFramesPerSecond = 30

            sender.setTitle("STOP" , for: UIControlState.normal)

            if let attributes = renderer.outputPixelBufferAttributes {
                
                assetWriter = RenderedVideoWriter(pixelBufferAttributes: attributes)
                assetWriter?.startRecording()
                renderer.pixelBufferConsumer = assetWriter
                
            }
            
        }
        
        //resetTracking()
        
    }
    
    @IBAction func savePressed(_ sender: UIButton) {
        
        //        session.pause()
        
  
        let fileManager = FileManager.default
        
        if let documentDirectory = fileManager.urls(for:.documentDirectory, in: .userDomainMask).first {
            
            let date = Date()
            let interval = date.timeIntervalSince1970
            let name =  "\(interval).scn"
            let sceneURL = documentDirectory.appendingPathComponent( name )
            renderer.scene.write(to: sceneURL, options: nil, delegate: nil, progressHandler: nil)
        }
        
        
        //resetTracking()
        
    }
    
    @objc
    func handleTap(gestureRecognize: UITapGestureRecognizer) {
        // Create anchor using the camera's current position
        if let currentFrame = session.currentFrame {
            
            // Create a transform with a translation of 0.2 meters in front of the camera
            var translation = matrix_identity_float4x4
            translation.columns.3.z = -0.2
            let transform = simd_mul(currentFrame.camera.transform, translation)
            
            // Add a new anchor to the session
            let anchor = ARAnchor(transform: transform)
            session.add(anchor: anchor)
        }
    }
    
   
    // MARK: - MTKViewDelegate
    
    // Called whenever view changes orientation or layout is changed
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer.drawRectResized(size: size)
    }
    
    // Called whenever the view needs to render
    func draw(in view: MTKView) {
         
            renderer.update()
         
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
    
    // updateARFrame
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
        renderer.updateARFrame(currentFrame: frame)
        
    }
 
    
    

}

