//
//  AVLoopedPlayer.swift
//  ARMetal
//
//  Created by joshua bauer on 3/16/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

import Foundation
import AVFoundation
import CoreVideo


class AVLoopedlayer: AVPlayer {
 
    var loopPlayback : Bool? {
        
        didSet {

            NotificationCenter.default.addObserver(forName: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: nil, queue: nil) { notification in
           
                    self.seek(to: kCMTimeZero)
                    self.playImmediately(atRate: 1.0)
                
                
            }
            
            self.play()
        }
        
    }
    
}


