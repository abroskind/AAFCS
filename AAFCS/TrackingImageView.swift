//
//  TrackingImageView.swift
//  AAFCS
//
//  Created by Dmytro Abroskin on 27/09/2023.
//

import Foundation
import UIKit

class TrackingImageView: UIView {
    
    var image: UIImage!
    var polyRects = [TrackedPolyRect]()

    var imageAreaRect = CGRect.zero
    
    var targetSpeedStart = CGPoint.zero
    var targetSpeedEnd = CGPoint.zero
    var targetReticle = CGPoint.zero

    let dashedPhase = CGFloat(0.0)
    let dashedLinesLengths: [CGFloat] = [4.0, 2.0]

    // Rubber-banding setup
    var rubberbandingStart = CGPoint.zero
    var rubberbandingVector = CGPoint.zero
    var rubberbandingRect: CGRect {
        let pt1 = self.rubberbandingStart
        let pt2 = CGPoint(x: self.rubberbandingStart.x + self.rubberbandingVector.x, y: self.rubberbandingStart.y + self.rubberbandingVector.y)
        let rect = CGRect(x: min(pt1.x, pt2.x), y: min(pt1.y, pt2.y), width: abs(pt1.x - pt2.x), height: abs(pt1.y - pt2.y))
        
        return rect
    }

    var rubberbandingRectNormalized: CGRect {
        guard imageAreaRect.size.width > 0 && imageAreaRect.size.height > 0 else {
            return CGRect.zero
        }
        var rect = rubberbandingRect
        
        // Make it relative to imageAreaRect
        rect.origin.x = (rect.origin.x - self.imageAreaRect.origin.x) / self.imageAreaRect.size.width
        rect.origin.y = (rect.origin.y - self.imageAreaRect.origin.y) / self.imageAreaRect.size.height
        rect.size.width /= self.imageAreaRect.size.width
        rect.size.height /= self.imageAreaRect.size.height
        // Adjust to Vision.framework input requrement - origin at LLC
        //rect.origin.y = 1.0 - rect.origin.y - rect.size.height
        
        return rect
    }

    func isPointWithinDrawingArea(_ locationInView: CGPoint) -> Bool {
        return self.imageAreaRect.contains(locationInView)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.setNeedsDisplay()
    }
    
    override func draw(_ rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()!

        ctx.saveGState()
        
        ctx.clear(rect)
        ctx.setFillColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        ctx.setLineWidth(2.0)

        // Draw a frame
        guard let newImage = scaleImage(to: rect.size) else {
            return
        }
        
        newImage.draw(at: self.imageAreaRect.origin)

        // Draw rubberbanding rectangle, if available
        if self.rubberbandingRect != CGRect.zero {
            ctx.setStrokeColor(UIColor.blue.cgColor)

            // Switch to dashed lines for rubberbanding selection
            ctx.setLineDash(phase: dashedPhase, lengths: dashedLinesLengths)
            ctx.stroke(self.rubberbandingRect)
        }
        
        if self.targetSpeedStart != CGPoint.zero {
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineDash(phase: dashedPhase, lengths: dashedLinesLengths)
            let p1 = scale(cornerPoint: self.targetSpeedStart, toImageViewPointInViewRect: rect)
            ctx.move(to: p1)
            let p2 = scale(cornerPoint: self.targetSpeedEnd, toImageViewPointInViewRect: rect)
            ctx.addLine(to: p2)
            ctx.strokePath()
            

        }
        
        if self.targetReticle != CGPoint.zero {
            ctx.setStrokeColor(UIColor.red.cgColor)
            ctx.setLineDash(phase: dashedPhase, lengths: [])
            let p1 = scale(cornerPoint: self.targetReticle, toImageViewPointInViewRect: rect)
            let p1l = CGPoint(x:p1.x-20,y:p1.y)
            ctx.move(to: p1l)
            let p2r = CGPoint(x:p1.x+20,y:p1.y)
            ctx.addLine(to: p2r)
            let p1u = CGPoint(x:p1.x,y:p1.y-20)
            ctx.move(to: p1u)
            let p2d = CGPoint(x:p1.x,y:p1.y+20)
            ctx.addLine(to: p2d)
            ctx.strokePath()
            
            let rectangle = CGRect(x:p1.x-20,y:p1.y-20,width: 40.0,height: 40.0)
            ctx.addEllipse(in: rectangle)
            ctx.strokePath()
        }
        
        
        ctx.setStrokeColor(UIColor.blue.cgColor)
        ctx.setLineDash(phase: dashedPhase, lengths: [])
        let p1 = scale(cornerPoint: CGPoint(x:0.5,y:0.5), toImageViewPointInViewRect: rect)
        let p1l = CGPoint(x:p1.x-30,y:p1.y)
        ctx.move(to: p1l)
        let p2r = CGPoint(x:p1.x+30,y:p1.y)
        ctx.addLine(to: p2r)
        let p1u = CGPoint(x:p1.x,y:p1.y-30)
        ctx.move(to: p1u)
        let p2d = CGPoint(x:p1.x,y:p1.y+30)
        ctx.addLine(to: p2d)
        ctx.strokePath()
        
        
        

        // Draw rects
        for polyRect in self.polyRects {
            ctx.setStrokeColor(polyRect.color.cgColor)
            switch polyRect.style {
            case .solid:
                ctx.setLineDash(phase: dashedPhase, lengths: [])
            case .dashed:
                ctx.setLineDash(phase: dashedPhase, lengths: dashedLinesLengths)
            }
            let cornerPoints = polyRect.cornerPoints
            var previous = scale(cornerPoint: cornerPoints[cornerPoints.count - 1], toImageViewPointInViewRect: rect)
            for cornerPoint in cornerPoints {
                ctx.move(to: previous)
                let current = scale(cornerPoint: cornerPoint, toImageViewPointInViewRect: rect)
                ctx.addLine(to: current)
                previous = current
            }
            ctx.strokePath()
        }
        
        ctx.restoreGState()
    }

    private func scaleImage(to viewSize: CGSize) -> UIImage? {
        guard self.image != nil && self.image.size != CGSize.zero else {
            return nil
        }
        
        self.imageAreaRect = CGRect.zero

        // There are two possible cases to fully fit self.image into the the ImageTrackingView area:
        // Option 1) image.width = view.width ==> image.height <= view.height
        // Option 2) image.height = view.height ==> image.width <= view.width
        let imageAspectRatio = self.image.size.width / self.image.size.height

        // Check if we're in Option 1) case and initialize self.imageAreaRect accordingly
        let imageSizeOption1 = CGSize(width: viewSize.width, height: floor(viewSize.width / imageAspectRatio))
        if imageSizeOption1.height <= viewSize.height {
            let imageX: CGFloat = 0
            let imageY = floor((viewSize.height - imageSizeOption1.height) / 2.0)
            self.imageAreaRect = CGRect(x: imageX,
                                        y: imageY,
                                        width: imageSizeOption1.width,
                                        height: imageSizeOption1.height)
        }

        if self.imageAreaRect == CGRect.zero {
            // Check if we're in Option 2) case if Option 1) didn't work out and initialize imageAreaRect accordingly
            let imageSizeOption2 = CGSize(width: floor(viewSize.height * imageAspectRatio), height: viewSize.height)
            if imageSizeOption2.width <= viewSize.width {
                let imageX = floor((viewSize.width - imageSizeOption2.width) / 2.0)
                let imageY: CGFloat = 0
                self.imageAreaRect = CGRect(x: imageX,
                                            y: imageY,
                                            width: imageSizeOption2.width,
                                            height: imageSizeOption2.height)
            }
        }

        // In next line, pass 0.0 to use the current device's pixel scaling factor (and thus account for Retina resolution).
        // Pass 1.0 to force exact pixel size.
        UIGraphicsBeginImageContextWithOptions(self.imageAreaRect.size, false, 0.0)
        self.image.draw(in: CGRect(x: 0.0, y: 0.0, width: self.imageAreaRect.size.width, height: self.imageAreaRect.size.height))
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage
    }
    
    private func scale(cornerPoint point: CGPoint, toImageViewPointInViewRect viewRect: CGRect) -> CGPoint {
        // Adjust bBox from Vision.framework coordinate system (origin at LLC) to imageView coordinate system (origin at ULC)
        let pointY = point.y
        let scaleFactor = self.imageAreaRect.size
        
        return CGPoint(x: point.x * scaleFactor.width + self.imageAreaRect.origin.x, y: pointY * scaleFactor.height + self.imageAreaRect.origin.y)
    }
}
