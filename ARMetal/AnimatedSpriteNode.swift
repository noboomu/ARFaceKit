//
//  SpriteAtlas.swift
//  ARMetal
//
//  Created by joshua bauer on 5/2/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

import Foundation
import SpriteKit
import CoreImage

class AnimatedSpriteNode : SKSpriteNode  {

    var frames: [SKTexture]? = [SKTexture]()
    
    init() {
        super.init(texture: nil, color: SKColor.clear, size: CGSize.zero)
    }
    
    override init(texture: SKTexture?, color: SKColor, size: CGSize)
    {
        super.init(texture: texture, color: color, size: size)
    }
    
    struct Sprite {
        
        var isFullyOpaque : Bool = false
        var textureRotated : Bool = false
        var name : String?
        var spriteOffset : CGPoint = CGPoint(x: 0, y: 0)
        var spriteSourceSize : CGSize = CGSize(width: 0, height: 0)
        var textureRect : CGRect = CGRect(x:0,y:0,width:0,height:0)
        var texture : SKTexture?
        
        init(with dictionary: [String: Any]?, parentTexture : SKTexture, parentSize : CGSize ) {
            
            guard let dictionary = dictionary else { return }
            
            name = dictionary["name"] as? String
            
            isFullyOpaque = dictionary["isFullyOpaque"] as! Bool
            
            textureRotated = dictionary["textureRotated"] as! Bool
            
            if let offsetValueString = dictionary["spriteOffset"] as? String {
                let values = parseValues(string: offsetValueString)
                spriteOffset = CGPoint( x: values[0], y: values[1] )
            }
            
            if let spriteSourceSizeString = dictionary["spriteSourceSize"] as? String {
                let values = parseValues(string: spriteSourceSizeString)
                spriteSourceSize = CGSize( width: values[0], height: values[1] )
            }
            
            if let textureRectString = dictionary["textureRect"] as? String {
                
                let parts = textureRectString[String.Index(encodedOffset:1)..<String.Index(encodedOffset:textureRectString.count-1)].split(separator: ",")
                
                let originString = String(parts[0] + "," + parts[1])
                
                let originValues = parseValues(string:originString)
                
                let sizeString = String(parts[2] + "," + parts[3])
                
                let sizeValues = parseValues( string: sizeString )
                
                textureRect = CGRect( x: originValues[0] , y: originValues[1] , width: sizeValues[0], height: sizeValues[1])
            }
            
            let unitTextureRect = CGRect( x: textureRect.origin.x / parentSize.width , y: textureRect.origin.y / parentSize.height, width: textureRect.size.width / parentSize.width, height: textureRect.size.height / parentSize.height  )
            
            texture  = SKTexture(rect: unitTextureRect, in: parentTexture)
        }
        
    }
    
    private class func loadImage( named resourceName : String, subdirectory : String? = "Models.scnassets" ) -> UIImage? {
        
        var imageURL: URL?
        
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "", subdirectory: subdirectory) {
            imageURL = url
        } else {
            let directoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            imageURL = directoryURL?.appendingPathComponent( subdirectory! + "/" + resourceName )
        }
        
        guard FileManager.default.fileExists(atPath: imageURL!.standardizedFileURL.relativePath) else {
            print("image not found")
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
    
    private class func parseValues( string : String ) -> [Int] {
        
        let values = string[String.Index(encodedOffset:1)..<String.Index(encodedOffset:string.count-1)].split(separator: ",").map { (value) -> Int in
            return Int(value)!
        }
        
        return values
    }
    
 
    init( fromPlist resourceName: String, subdirectory: String? = "Models.scnassets" )  {
        
        var dataURL: URL?
        
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "", subdirectory: subdirectory) {
            dataURL = url
        } else {
            let directoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            dataURL = directoryURL?.appendingPathComponent(subdirectory! + "/" + resourceName)
        }
        
        guard FileManager.default.fileExists(atPath: dataURL!.standardizedFileURL.relativePath) else {
            print("atlas not found")
            super.init(texture: nil, color: SKColor.clear, size: CGSize.zero)
            return
        }
        
        let dictionary: [String: Any]?
        
        do {
            let data = try Data(contentsOf: dataURL!.standardizedFileURL)
            let result = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
            dictionary = result
        } catch let error {
            print("Failed to load spriteAtlas, error \(error)")
           super.init(texture: nil, color: SKColor.clear, size: CGSize.zero)
            return
        }
        
        var spriteMap : [String: Sprite] = [String: Sprite] ()
 
        let images = dictionary!["images"] as? [[String: Any]]
        
        for imageSource in images! {
            
            let path = imageSource["path"] as! String
            
            guard let sourceImage = AnimatedSpriteNode.loadImage(named: path, subdirectory: subdirectory) else {
                super.init(texture: nil, color: SKColor.clear, size: CGSize.zero)
                return
            }
            
            
            let sizeValues = AnimatedSpriteNode.parseValues(string: imageSource["size"] as! String)
            
            let size = CGSize(width: sizeValues[0], height: sizeValues[1])
            
            let skTexture = SKTexture(image: sourceImage)
            
            let subImages = imageSource["subimages"] as? [[String: Any]]
            
            for subImage in subImages! {
                
                let sprite = Sprite(with: subImage, parentTexture: skTexture, parentSize: size)
                
                spriteMap[sprite.name!] = sprite
                
            }
        }
        
        let sortedKeys = spriteMap.keys.sorted()
        
        var frames = [SKTexture]()
        
        for key in sortedKeys {
            
            let sprite = spriteMap[key]
            
            let spriteTexture = sprite!.texture!
            
            frames.append(spriteTexture)
        }
        
        let firstFrame : SKTexture? = frames[0]
        
        super.init(texture: firstFrame)
        
        self.frames = frames
        
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func animateAtRate( rate : TimeInterval ) {
        
      //  self.removeAllActions()
        
        self.run(SKAction.repeatForever(
            SKAction.animate(with: self.frames!,
                             timePerFrame:rate,
                             resize: false,
                             restore: true)),
                 withKey:"spriteAnimation")
        
    }

    
    deinit {
        
       // self.removeAllActions()
        self.frames = nil
        
    }

}
