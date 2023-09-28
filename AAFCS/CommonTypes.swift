//
//  CommonTypes.swift
//  AAFCS
//
//  Created by Dmytro Abroskin on 27/09/2023.
//

import Foundation
import UIKit
import Vision
import Spatial
import DequeModule


enum TrackedPolyRectStyle: Int {
    case solid
    case dashed
}

struct TrackedObjectsPalette {
    static var palette = [
        UIColor.green,
        UIColor.cyan,
        UIColor.orange,
        UIColor.brown,
        UIColor.darkGray,
        UIColor.red,
        UIColor.yellow,
        UIColor.magenta,
        #colorLiteral(red: 0, green: 1, blue: 0, alpha: 1), // light green
        UIColor.gray,
        UIColor.purple,
        UIColor.clear,
        #colorLiteral(red: 0, green: 0.9800859094, blue: 0.941437602, alpha: 1),   // light blue
        UIColor.lightGray,
        UIColor.black,
        UIColor.blue
    ]
    
    static func color(atIndex index: Int) -> UIColor {
        if index < palette.count {
            return palette[index]
        }
        return randomColor()
    }
    
    static func randomColor() -> UIColor {
        func randomComponent() -> CGFloat {
            return CGFloat(arc4random_uniform(256)) / 255.0
        }
        return UIColor(red: randomComponent(), green: randomComponent(), blue: randomComponent(), alpha: 1.0)
    }
}

struct TrackedPolyRect {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomLeft: CGPoint
    var bottomRight: CGPoint
    var color: UIColor
    var style: TrackedPolyRectStyle
    
    var cornerPoints: [CGPoint] {
        return [topLeft, topRight, bottomRight, bottomLeft]
    }
    
    var boundingBox: CGRect {
        let topLeftRect = CGRect(origin: topLeft, size: .zero)
        let topRightRect = CGRect(origin: topRight, size: .zero)
        let bottomLeftRect = CGRect(origin: bottomLeft, size: .zero)
        let bottomRightRect = CGRect(origin: bottomRight, size: .zero)

        return topLeftRect.union(topRightRect).union(bottomLeftRect).union(bottomRightRect)
    }
    
    init(observation: VNDetectedObjectObservation, color: UIColor, style: TrackedPolyRectStyle = .solid) {
        self.init(cgRect: observation.boundingBox, color: color, style: style)
    }
    
    init(observation: VNRectangleObservation, color: UIColor, style: TrackedPolyRectStyle = .solid) {
        topLeft = observation.topLeft
        topRight = observation.topRight
        bottomLeft = observation.bottomLeft
        bottomRight = observation.bottomRight
        self.color = color
        self.style = style
    }

    init(cgRect: CGRect, color: UIColor, style: TrackedPolyRectStyle = .solid) {
        topLeft = CGPoint(x: cgRect.minX, y: cgRect.maxY)
        topRight = CGPoint(x: cgRect.maxX, y: cgRect.maxY)
        bottomLeft = CGPoint(x: cgRect.minX, y: cgRect.minY)
        bottomRight = CGPoint(x: cgRect.maxX, y: cgRect.minY)
        self.color = color
        self.style = style
    }
}


struct TargetPosition {
    var position: Point3D
    var time: UInt64
    
    init(x: CGFloat, y: CGFloat, z: CGFloat){
        self.time = 0
        self.position = Point3D(x:x,y:y,z:z)
    }
    init(distance: CGFloat, azimuth: CGFloat, elevation: CGFloat, time: UInt64){
        position = Point3D(x: distance * sin((90.0 - elevation) * .pi / 180.0) * cos( azimuth * .pi / 180.0)  , y: distance * sin((90.0 - elevation) * .pi / 180.0) * sin( azimuth * .pi / 180.0), z: distance * cos((90.0 - elevation) * .pi / 180.0))
        self.time = time
    }
    
    func getSpherical() -> Point3D{
        var res: Point3D = Point3D(x: 0.0, y: 0.0, z: 0.0)
        res.x = sqrt(position.x * position.x + position.y * position.y + position.z * position.z)
        if res.x != 0 {
            res.y = 90.0 - acos(position.z/res.x) * 180.0 / .pi
        }
        if (position.x * position.x + position.y * position.y) > 0 {
            if position.y >= 0 {
                res.z = acos(position.x / sqrt (position.x * position.x + position.y * position.y)) * 180.0 / .pi
            } else {
                res.z = -acos(position.x / sqrt (position.x * position.x + position.y * position.y)) * 180.0 / .pi
            }
        }
        return res
    }
}

class Target {
    var positionHistory: Deque<TargetPosition>
    init(){
        self.positionHistory = []
    }
    init(position:TargetPosition){
        self.positionHistory = [position]
    }
    func updatePosition(position:TargetPosition){
        self.positionHistory.append(position)
        if(self.positionHistory.count>10){
            self.positionHistory.popFirst()
        }
    }
    
    func getSpeedVector()->Vector3D{
        let count = self.positionHistory.count
        var i : Int = 0
        var i1 : Int = 0
        var i2 : Int = 0
        var point1: Point3D = Point3D(x: 0.0, y: 0.0, z: 0.0)
        var point2: Point3D = Point3D(x: 0.0, y: 0.0, z: 0.0)
        var time1: UInt64 = 0
        var time2: UInt64 = 0
        for pos in self.positionHistory {
            if i < count / 2 {
                point1.x += pos.position.x
                point1.y += pos.position.y
                point1.z += pos.position.z
                time1 += pos.time
                i1 += 1
            } else {
                point2.x += pos.position.x
                point2.y += pos.position.y
                point2.z += pos.position.z
                time2 += pos.time
                i2 += 1
            }
            i+=1
        }
        point1 = point1 / CGFloat(i1)
        point2 = point2 / CGFloat(i1)
        let timeDiff = (CGFloat(time2) / CGFloat(i2) - CGFloat(time1) / CGFloat(i1)) / 1e+9
        return (point2-point1) / timeDiff
    }
}


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

