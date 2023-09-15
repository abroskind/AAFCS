//
//  HUDScene.swift
//  AAFCS
//
//  Created by Dmytro Abroskin on 13/09/2023.
//

import Foundation
import SpriteKit
import CoreMotion
import DequeModule
import AVFoundation

extension Sequence where Element: AdditiveArithmetic {
    func sum() -> Element { reduce(.zero, +) }
}

extension Collection where Element: BinaryInteger {
    func average() -> Element { isEmpty ? .zero : sum() / Element(count) }
    func average<T: FloatingPoint>() -> T { isEmpty ? .zero : T(sum()) / T(count) }
}
extension Collection where Element: BinaryFloatingPoint {
    func average() -> Element { isEmpty ? .zero : sum() / Element(count) }
}

class HUDScene: SKScene {
    var zoom = 5.0
    var camera_fov = 111.0
    var angleLabel: SKLabelNode
    var crosshair: SKShapeNode
    var targetReticleL: SKShapeNode
    var targetReticleR: SKShapeNode
    var motionManager: CMMotionManager
    
    var degPerSecX_H: Deque = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
    var degPerSecY_H: Deque = [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override init(size:CGSize){
        
        motionManager = CMMotionManager()
        angleLabel = SKLabelNode(fontNamed: "Helvetica")
        crosshair = SKShapeNode()
        targetReticleL = SKShapeNode()
        targetReticleR = SKShapeNode()

        super.init(size:size)
        
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.01
            motionManager.startDeviceMotionUpdates()
        }

        angleLabel.text = "0.0"
        angleLabel.fontSize = 20
        angleLabel.fontColor = SKColor.green
        angleLabel.position = CGPoint(x: frame.midX, y: frame.maxY-50)
        addChild(angleLabel)
        
        
        let pathToDraw = CGMutablePath()
        pathToDraw.move(to: CGPoint(x: frame.midX, y: frame.midY-10))
        pathToDraw.addLine(to: CGPoint(x: frame.midX, y: frame.midY+10))
        pathToDraw.move(to: CGPoint(x: frame.midX-10, y: frame.midY))
        pathToDraw.addLine(to: CGPoint(x: frame.midX+10, y: frame.midY))
        crosshair.path = pathToDraw
        crosshair.strokeColor = SKColor.red
        crosshair.lineWidth = 2
        addChild(crosshair)
        addChild(targetReticleL)
        addChild(targetReticleR)
    }
    
    override func update(_ currentTime: TimeInterval) {
        if let motionData = motionManager.deviceMotion {
            
            let rotation = atan2(motionData.gravity.x,
                                 motionData.gravity.z) - .pi/2
            angleLabel.text = "Gun angle: " + String(Double(round(10 * -rotation * 180.0 / .pi)) / 10)    + " deg (currently ignored)"
            
            
            let start_angle = 0.25
            let max_angle = 3.0
            let angle_step = 0.05
            
            let v = 100.0 // projectile speed m/s
            let g = 9.8
            let drone_size = 3.0 // average shahed 136 size (w: 2.5, l: 3.5)
            
            guard let videoDevice = AVCaptureDevice.default(.builtInDualWideCamera,for: .video, position: .back) else { return }
            camera_fov = Double(videoDevice.activeFormat.videoFieldOfView)
            
            let fov = camera_fov / zoom
            let pixel_per_fov = frame.maxX / fov

            
            degPerSecX_H.append(motionData.rotationRate.x * 180 / .pi)
            degPerSecX_H.popFirst()
            degPerSecY_H.append(motionData.rotationRate.y * 180 / .pi)
            degPerSecY_H.popFirst()
            
            let degPerSecX = degPerSecX_H.average()
            let degPerSecY = degPerSecY_H.average()
            
            let pathToDrawTargetReticleL = CGMutablePath()
            let pathToDrawTargetReticleR = CGMutablePath()
            let rad = Double(start_angle) * .pi / 180
            let distance = v*v*sin(2*rad)/g
            let time = 2 * v * sin(rad) / g
            
            let fov_size = atan(drone_size / (2.0 * distance)) * 180 / .pi
            let pixel_size = fov_size * pixel_per_fov
            
            let pixel_adj_x = time * degPerSecX * pixel_per_fov
            let pixel_adj_y = time * degPerSecY * pixel_per_fov
            
            
            pathToDrawTargetReticleL.move(to: CGPoint(x: frame.midX - pixel_size / 2 - pixel_adj_x, y: frame.midY - Double(start_angle) * pixel_per_fov - pixel_adj_y))
            pathToDrawTargetReticleR.move(to: CGPoint(x: frame.midX + pixel_size / 2 - pixel_adj_x, y: frame.midY - Double(start_angle) * pixel_per_fov - pixel_adj_y))
            
            for i in stride(from: start_angle+angle_step, to: max_angle, by: angle_step){
                let rad = Double(i) * .pi / 180
                let distance = v*v*sin(2*rad)/g
                let time = 2 * v * sin(rad) / g
                
                let fov_size = atan(drone_size / (2.0 * distance)) * 180 / .pi
                let pixel_size = fov_size * pixel_per_fov
                
                let pixel_adj_x = time * degPerSecX * pixel_per_fov
                let pixel_adj_y = time * degPerSecY * pixel_per_fov
                
                pathToDrawTargetReticleL.addLine(to: CGPoint(x: frame.midX - pixel_size / 2 - pixel_adj_x, y: frame.midY - Double(i) * pixel_per_fov - pixel_adj_y))
                pathToDrawTargetReticleR.addLine(to: CGPoint(x: frame.midX + pixel_size / 2 - pixel_adj_x, y: frame.midY - Double(i) * pixel_per_fov - pixel_adj_y))

                targetReticleL.path = pathToDrawTargetReticleL
                targetReticleL.strokeColor = SKColor.green
                targetReticleL.lineWidth = 3
                targetReticleR.path = pathToDrawTargetReticleR
                targetReticleR.strokeColor = SKColor.green
                targetReticleR.lineWidth = 3
            }

            
            
            
            
            
        }
    }
    
    
}
