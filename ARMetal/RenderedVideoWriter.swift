//
//  RenderedVideoWriter.swift
//  ARMetal
//
//  Created by joshua bauer on 3/28/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

import Foundation

import Metal
import AVFoundation
import CoreVideo
import Photos

class RenderedVideoWriter: RenderPixelBufferConsumer {
  
 
    var pixelBufferAttributes : [String : Any]?
    
    var writerInput : AVAssetWriterInput!
    
    var assetWriter : AVAssetWriter!
    
    var outputFileURL : URL?
    
    var bufferAdaptor : AVAssetWriterInputPixelBufferAdaptor!
    
    var renderCallbackQueue = DispatchQueue(label: "Pixel Writer Sync Queue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    var hasStarted : Bool = false
    
    func renderedOutput(didRender: CVPixelBuffer, atTime: CMTime ) {
        
        if !hasStarted {
            hasStarted = true
           assetWriter.startSession(atSourceTime: atTime)
        }
        if bufferAdaptor != nil && writerInput.isReadyForMoreMediaData {
            let result = bufferAdaptor.append(didRender, withPresentationTime: atTime)
            //print("time = \(CMTimeGetSeconds(atTime))")
            if !result {
                print("result = \(result)")

            }
        }
        
    }
    
    
    
    init( pixelBufferAttributes : [String : Any]? = nil ) {
        
        self.pixelBufferAttributes = pixelBufferAttributes
        
  
        
    }
    
    func startRecording() {
        
        let outputFileName = NSUUID().uuidString
        let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
        
        outputFileURL = URL(fileURLWithPath:outputFilePath)
        
        guard let avAssetWriter = try? AVAssetWriter(url: outputFileURL!, fileType: AVFileType.mov ) else {
            print("Unable to create writer :(")
            return
        }
        
        assetWriter = avAssetWriter
        
        
        writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
        
        writerInput.expectsMediaDataInRealTime = true
        
        writerInput.transform = CGAffineTransform(rotationAngle:-CGFloat.pi / 2)
        
        bufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: self.pixelBufferAttributes)
        
        assetWriter.add(writerInput)
        
        assetWriter.startWriting()
        
        print("outputFilePath: \(outputFileURL!)")
    }

    func stopRecording() {
        
        writerInput.markAsFinished()
        
        assetWriter.finishWriting { () -> Void in
            
            print("DONE!!! -> \(self.assetWriter.status.rawValue)")
            
            print("outputFilePath: \(self.outputFileURL!)")
            
            if self.assetWriter.status == AVAssetWriterStatus.failed {
                print("error: \(self.assetWriter.error!)")
            }
            
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    // Save the movie file to the photo library and cleanup.
                    PHPhotoLibrary.shared().performChanges({
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = true
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .video, fileURL: self.outputFileURL!, options: options)
                    }, completionHandler: { success, error in
                        if !success {
                            print("Could not save movie to photo library: \(String(describing: error))")
                        }
                     }
                    )
                } else {
                    
                }
            }

        }
        
    }
    
}
