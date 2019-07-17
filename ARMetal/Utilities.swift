//
//  Utilities.swift
//  ARMetal
//
//  Created by joshua bauer on 3/9/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

import ARKit
import SceneKit
import UIKit
import ModelIO
import MetalKit
import Metal
import SceneKit.ModelIO


var apiBaseURL: String {
    return Bundle.main.object(forInfoDictionaryKey: "WRLAPIBaseURL") as! String
}

class Utilities
{
    private static var isDirectory: ObjCBool = true
    
    private static var tempDirectoryURL : URL?

    class func createImageFromPDF( url : URL ) -> UIImage {
        
        let document = CGPDFDocument(url as CFURL)!
        let page = document.page(at: 1)!
        let rect = page.getBoxRect(CGPDFBox.mediaBox)
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        
        return renderer.image(actions: { context in
            let cgContext = context.cgContext
            
            cgContext.setFillColor(gray: 0, alpha: 0)
            cgContext.fill(rect)
            
            cgContext.translateBy(x: 0, y: rect.size.height)
            cgContext.scaleBy(x: 1, y: -1)
            cgContext.drawPDFPage(page)
        })
        
    }
    
    class func getTempDirectoryURL() -> URL {
        
        if let url = tempDirectoryURL {
            return url
        }
        
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        
        let masksURL = cacheURL?.appendingPathComponent(  "tmp")
        
        tempDirectoryURL = masksURL
        
        if !FileManager.default.fileExists(atPath: masksURL!.path, isDirectory: &isDirectory) {
            
            do {
                try FileManager.default.createDirectory(at: masksURL!, withIntermediateDirectories: true, attributes: nil)
            } catch  {
                print("Failed to create temp directroy")
            }
            
            
        }
        
         return tempDirectoryURL!
    }
    
    class func fetchMaskInfo( id : Int, completion: ( (MaskInfo?)  -> Void )? ) {
    
        let url = URL(string:"\(apiBaseURL)/v1/content/masks/\(String(id))?userId=95076")
    
        var request = URLRequest(url: url!)
        request.httpMethod = "GET"
        
        let config = URLSessionConfiguration.default
        
        let session = URLSession(configuration: config)
        
        
        let task = session.dataTask(with: request) { (responseData, response, responseError) in
            DispatchQueue.main.async {
                if let error = responseError {
                    
                    print("error response: \(error)")
                    
                    completion!(nil)
                    
                } else if let data = responseData {
                    
                    let decoder = JSONDecoder()
                    do {
                        let maskInfo = try decoder.decode(MaskInfo.self, from: data)
                        completion!(maskInfo)
                    } catch {
                        print("error trying to convert data to JSON")
                        print(error)
                        completion!(nil)
                    }
                }
                else {
                    let error = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey : "Data was not retrieved from request"]) as Error
                    print("error loading data from: \(url!) \(error)")
                    completion!(nil)
                }
            }
        }
        
        task.resume()
    }

   
    class func fetchMaskData( id : Int, completion: ( (MaskInfo?)  -> Void )? ) {
        
        let url = URL(string:"\(apiBaseURL)/v1/content/masks/\(String(id))?userId=95076&context=detail")

        print("download url \(url)")
        
        var request = URLRequest(url: url!)
        request.httpMethod = "GET"
        
        let config = URLSessionConfiguration.default
        
        let session = URLSession(configuration: config)
        
        
        let task = session.dataTask(with: request) { (responseData, response, responseError) in
            DispatchQueue.global(qos: .background).async  {
                if let error = responseError {
                    
                    print("error response: \(error)")
                    
                    completion!(nil)
                    
                } else if let data = responseData {
                    
                    let decoder = JSONDecoder()
                    do {
                        let maskInfo = try decoder.decode(MaskInfo.self, from: data)
                        completion!(maskInfo)
                    } catch {
                        print("error trying to convert data to JSON")
                        print(error)
                        completion!(nil)
                    }
                }
                else {
                    let error = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey : "Data was not retrieved from request"]) as Error
                    print("error loading data from: \(url!) \(error)")
                    completion!(nil)
                }
            }
        }
        
        task.resume()
    }

    
    class func clearCacheDirectory() {
        do {
            
            let tmpDirURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            
            let tmpMasksURL = tmpDirURL!.appendingPathComponent("masks")
            
            print("path tmp directory: \(tmpMasksURL)")
            
            let tmpDirectory = try FileManager.default.contentsOfDirectory(atPath: tmpMasksURL.path )
  
            
            try tmpDirectory.forEach { file in
                let fileUrl = tmpMasksURL.appendingPathComponent(file)
                print("removing: \(fileUrl)")
                try FileManager.default.removeItem(atPath: fileUrl.path)
            }
        } catch {
           print("error clearing cache directory: \(error)")
        }
    }
    
    
    class func mdlTest() {
        
        
        if let url = Bundle.main.url(forResource: "reference.dae", withExtension: "dae", subdirectory: "Models.scnassets") {
            
            let asset = MDLAsset(url:url)
             print("model = \(asset)")
            
            let root = asset.object(at: 0)
            
            if let mesh = root as? MDLMesh {
                
                let submeshes = mesh.submeshes
                
                let buffers = mesh.vertexBuffers
                
                let coordinateData : MDLVertexAttributeData = mesh.vertexAttributeData(forAttributeNamed: "textureCoordinate", as: .float2)!
                
                let bufferPointer = coordinateData.map.bytes
                
                
                let vd = mesh.vertexDescriptor
                
                
                print("vd = \(vd)")
                
                if submeshes != nil && submeshes!.count > 0 {
                    
                    let submesh = submeshes![0] as! MDLSubmesh
                    
                      print("submesh = \(submesh)")
                }
                
            } else {
                print("cannot find mesh")
            }
            
            
        } else {
            print("cannot find model")
        }
        
        if let url = Bundle.main.url(forResource: "reference_alt", withExtension: "scn", subdirectory: "Models.scnassets") {
            
            let node = SCNReferenceNode(url: url)!
            node.load()
            
             let scnScene  = try! SCNScene(url: url, options: nil)
       
            let alternateNode = scnScene.rootNode.childNode(withName: "alternate", recursively: true)

                let asset = MDLAsset(scnScene:scnScene)
                    
                    let root = asset.object(at: 0)
                    
                    if let mesh = root.children[0].children[0] as? MDLMesh {
                        
                        let submeshes = mesh.submeshes
                        
                        let buffers = mesh.vertexBuffers
                        
                        let coordinateData : MDLVertexAttributeData = mesh.vertexAttributeData(forAttributeNamed: "textureCoordinate", as: .float2)!
                        
                        let bufferPointer = coordinateData.map.bytes
                        
                        
                        let vd = mesh.vertexDescriptor
                        
                        
                        print("vd = \(vd)")
                        
                        if submeshes != nil && submeshes!.count > 0 {
                            
                            let submesh = submeshes![0] as! MDLSubmesh
                            
                            print("submesh = \(submesh)")
                        }
                        
                    } else {
                        print("cannot find mesh")
                    }
        }
    }
}
