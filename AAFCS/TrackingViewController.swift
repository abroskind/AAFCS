//
//  TrackingViewController.swift
//  AAFCS
//
//  Created by Dmytro Abroskin on 27/09/2023.
//

import AVFoundation
import UIKit
import Vision
import AVKit
import SwiftUI
import CoreMotion
import Spatial

class TrackingViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    private var trackingView: TrackingImageView = TrackingImageView()
    private var distanceLabel: UILabel!
    private var angleLabel: UILabel!
    private var positionLabel: UILabel!
    var trackingLevel = VNRequestTrackingLevel.accurate
    var session: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var videoDataOutput: AVCaptureVideoDataOutput?
    var videoDataOutputQueue: DispatchQueue?
    var captureDevice: AVCaptureDevice?
    var captureDeviceResolution: CGSize = CGSize()

    var inputObservations = [UUID: VNDetectedObjectObservation]()
    var trackedObjects = [UUID: TrackedPolyRect]()
    
    var motionManager: CMMotionManager!
    
    lazy var sequenceRequestHandler = VNSequenceRequestHandler()

    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    
    private var objectsToTrack = [TrackedPolyRect]()
    
    private var trackedTarget: Target!
    
    private var zoom: CGFloat = 3.0
    private var cameraFov: CGFloat = 111.0
    
    override func loadView() {
        self.view = self.trackingView
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        


        
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(didPan(sender:)))
        
        self.view.addGestureRecognizer(panGestureRecognizer)
        
        self.distanceLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 700, height: 21))
        self.distanceLabel.center = CGPoint(x: 450, y: 700)
        self.distanceLabel.textAlignment = .center
        self.distanceLabel.text = "Distance"
        self.view.addSubview(self.distanceLabel)
        self.angleLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 700, height: 21))
        self.angleLabel.center = CGPoint(x: 450, y: 750)
        self.angleLabel.textAlignment = .center
        self.angleLabel.text = "Angle"
        self.view.addSubview(self.angleLabel)
        self.positionLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 700, height: 21))
        self.positionLabel.center = CGPoint(x: 450, y: 800)
        self.positionLabel.textAlignment = .center
        self.positionLabel.text = "Position"
        self.view.addSubview(self.positionLabel)
        self.trackedTarget = Target()
        
        sessionQueue.async { [unowned self] in
        
            self.session = self.setupAVCaptureSession()
            self.session?.startRunning()
            self.motionManager = CMMotionManager()
            if self.motionManager.isDeviceMotionAvailable {
                self.motionManager.deviceMotionUpdateInterval = 0.01
                self.motionManager.startDeviceMotionUpdates()
            }
        }

    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
    

    
    /// - Tag: CreateCaptureSession
    fileprivate func setupAVCaptureSession() -> AVCaptureSession? {
        let captureSession = AVCaptureSession()
        do {
            let inputDevice = try self.configureCamera(for: captureSession)
            self.configureVideoDataOutput(for: inputDevice.device, resolution: inputDevice.resolution, captureSession: captureSession)
            self.designatePreviewLayer(for: captureSession)
            return captureSession
        } catch let executionError as NSError {
            self.presentError(executionError)
        } catch {
            self.presentErrorAlert(message: "An unexpected failure has occured")
        }
        
        self.teardownAVCapture()
        
        return nil
    }
    
    fileprivate func highestResolution420Format(for device: AVCaptureDevice) -> (format: AVCaptureDevice.Format, resolution: CGSize)? {
        var highestResolutionFormat: AVCaptureDevice.Format? = nil
        var highestResolutionDimensions = CMVideoDimensions(width: 0, height: 0)
        
        for format in device.formats {
            let deviceFormat = format as AVCaptureDevice.Format
            
            let deviceFormatDescription = deviceFormat.formatDescription
            if CMFormatDescriptionGetMediaSubType(deviceFormatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
                let candidateDimensions = CMVideoFormatDescriptionGetDimensions(deviceFormatDescription)
                if (highestResolutionFormat == nil) || (candidateDimensions.width > highestResolutionDimensions.width) {
                    highestResolutionFormat = deviceFormat
                    highestResolutionDimensions = candidateDimensions
                }
            }
        }
        
        if highestResolutionFormat != nil {
            let resolution = CGSize(width: CGFloat(highestResolutionDimensions.width), height: CGFloat(highestResolutionDimensions.height))
            return (highestResolutionFormat!, resolution)
        }
        
        return nil
    }
    
    fileprivate func configureCamera(for captureSession: AVCaptureSession) throws -> (device: AVCaptureDevice, resolution: CGSize) {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back)
        
        if let device = deviceDiscoverySession.devices.first {
            if let deviceInput = try? AVCaptureDeviceInput(device: device) {
                if captureSession.canAddInput(deviceInput) {
                    captureSession.addInput(deviceInput)
                }
                
                if let highestResolution = self.highestResolution420Format(for: device) {
                    try device.lockForConfiguration()
                    device.activeFormat = highestResolution.format
                    self.cameraFov = CGFloat(device.activeFormat.geometricDistortionCorrectedVideoFieldOfView)
                    if (device.maxAvailableVideoZoomFactor >= self.zoom) {
                        device.videoZoomFactor = self.zoom
                    }
                    //device.setFocusModeLocked(lensPosition:0.9)
                    device.unlockForConfiguration()
                    
                    return (device, highestResolution.resolution)
                }
            }
        }
        
        throw NSError(domain: "TrackingViewController", code: 1, userInfo: nil)
    }
    
    /// - Tag: CreateSerialDispatchQueue
    fileprivate func configureVideoDataOutput(for inputDevice: AVCaptureDevice, resolution: CGSize, captureSession: AVCaptureSession) {
        
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        let videoDataOutputQueue = DispatchQueue(label: "AAFCS-dispatch-queue")
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }
        
        videoDataOutput.connection(with: .video)?.isEnabled = true
        
        if let captureConnection = videoDataOutput.connection(with: AVMediaType.video) {
            if captureConnection.isCameraIntrinsicMatrixDeliverySupported {
                captureConnection.isCameraIntrinsicMatrixDeliveryEnabled = true
            }
        }
        
        self.videoDataOutput = videoDataOutput
        self.videoDataOutputQueue = videoDataOutputQueue
        
        self.captureDevice = inputDevice
        self.captureDeviceResolution = resolution
    }
    
    /// - Tag: DesignatePreviewLayer
    fileprivate func designatePreviewLayer(for captureSession: AVCaptureSession) {
        let videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer = videoPreviewLayer
        
        videoPreviewLayer.name = "CameraPreview"
        videoPreviewLayer.backgroundColor = UIColor.black.cgColor
        videoPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        
    }
    
    fileprivate func teardownAVCapture() {
        self.videoDataOutput = nil
        self.videoDataOutputQueue = nil
        
        if let previewLayer = self.previewLayer {
            previewLayer.removeFromSuperlayer()
            self.previewLayer = nil
        }
    }
    
    fileprivate func presentErrorAlert(withTitle title: String = "Unexpected Failure", message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        self.present(alertController, animated: true)
    }
    
    fileprivate func presentError(_ error: NSError) {
        self.presentErrorAlert(withTitle: "Failed with error \(error.code)", message: error.localizedDescription)
    }
    
    func exifOrientationForDeviceOrientation(_ deviceOrientation: UIDeviceOrientation) -> CGImagePropertyOrientation {
        
        switch deviceOrientation {
        case .portraitUpsideDown:
            return .rightMirrored
            
        case .landscapeLeft:
            return .downMirrored
            
        case .landscapeRight:
            return .upMirrored
            
        default:
            return .leftMirrored
        }
    }
    
    func exifOrientationForCurrentDeviceOrientation() -> CGImagePropertyOrientation {
        return exifOrientationForDeviceOrientation(UIDevice.current.orientation)
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        var requestHandlerOptions: [VNImageOption: AnyObject] = [:]
        let cameraIntrinsicData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil)
        if cameraIntrinsicData != nil {
            requestHandlerOptions[VNImageOption.cameraIntrinsics] = cameraIntrinsicData
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to obtain a CVPixelBuffer for the current output frame.")
            return
        }
        let exifOrientation = self.exifOrientationForCurrentDeviceOrientation()
        
        
        var rects = [TrackedPolyRect]()
        var trackingRequests = [VNRequest]()
        for inputObservation in self.inputObservations {
            let request: VNTrackingRequest!

            request = VNTrackObjectRequest(detectedObjectObservation: inputObservation.value)

            request.trackingLevel = self.trackingLevel
         
            trackingRequests.append(request)
        }
        
        do {
            try self.sequenceRequestHandler.perform(trackingRequests,on: pixelBuffer,
                                       orientation: exifOrientation)
            
        } catch {
            NSLog("Failed to perform detection request")
        }

        for processedRequest in trackingRequests {
            guard let results = processedRequest.results else {
                continue
            }
            guard let observation = results.first as? VNDetectedObjectObservation else {
                continue
            }

            let rectStyle: TrackedPolyRectStyle = observation.confidence > 0.8 ? .solid : .dashed
            let knownRect = self.trackedObjects[observation.uuid]!

            rects.append(TrackedPolyRect(observation: observation, color: knownRect.color, style: rectStyle))

            self.inputObservations[observation.uuid] = observation
        }
        
        var cameraYaw : CGFloat = 0.0
        var cameraPitch : CGFloat = 0.0
        
        if let motionData = self.motionManager.deviceMotion {
            
            
            cameraYaw =  -motionData.attitude.yaw * 180.0 / .pi
            cameraPitch = -(motionData.attitude.roll + .pi/2) * 180.0 / .pi

        }
        
        var observedAngularSize : CGFloat = 0.0
        var distance : CGFloat = 0.0
        
        var droneElevation : CGFloat = 0.0
        var droneAzimuth : CGFloat = 0.0
        var observedPositionX : CGFloat = 0.0
        var observedPositionY : CGFloat = 0.0
        let droneSize = 3.0
        let v = 200.0 // projectile speed m/s
        let g = 9.8
        
        for inputObservation in self.inputObservations {
            let observedSize = inputObservation.value.boundingBox.width
            observedPositionX = inputObservation.value.boundingBox.midX
            observedPositionY = inputObservation.value.boundingBox.midY
            droneAzimuth = cameraYaw + (observedPositionX-0.5) * ( self.cameraFov / self.zoom )
            droneElevation = cameraPitch + (0.5-observedPositionY) * ( self.cameraFov / self.zoom ) * CGFloat(CVPixelBufferGetHeight(pixelBuffer)) / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
            
            observedAngularSize = ( self.cameraFov / self.zoom ) * observedSize
            distance = droneSize / tan((observedAngularSize / 2) * .pi / 180.0)
            
           
        }
        let dronePos = TargetPosition(distance: distance, azimuth: droneAzimuth, elevation: droneElevation, time: DispatchTime.now().uptimeNanoseconds)
        var posX: CGFloat = 0.0
        var posY: CGFloat = 0.0
        var posY_corrected: CGFloat = 0.0
        var speedVec: Vector3D = Vector3D(x:0,y:0,z:0)
        if distance>0{
            self.trackedTarget.updatePosition(position: dronePos)
            if self.trackedTarget.positionHistory.count > 4 {
                speedVec = self.trackedTarget.getSpeedVector()
                
                
                let rad = asin (distance * g / (v * v)) / 2
                let timeToTarget = 2 * v * sin(rad) / g
                
                let predictedPos = TargetPosition(x:dronePos.position.x+speedVec.x*timeToTarget,y:dronePos.position.y+speedVec.y*timeToTarget,z:dronePos.position.z+speedVec.z*timeToTarget)
                
                let spherical = predictedPos.getSpherical()
                posX = (spherical.z - cameraYaw ) / ( self.cameraFov / self.zoom ) + 0.5
                posY =  -((spherical.y - cameraPitch) / ( self.cameraFov / self.zoom ) / CGFloat(CVPixelBufferGetHeight(pixelBuffer)) * CGFloat(CVPixelBufferGetWidth(pixelBuffer)) - 0.5)
                posY_corrected = -((spherical.y + rad * 180.0 / .pi - cameraPitch) / ( self.cameraFov / self.zoom ) / CGFloat(CVPixelBufferGetHeight(pixelBuffer)) * CGFloat(CVPixelBufferGetWidth(pixelBuffer)) - 0.5)
                

                


                
            }
        }
        


        DispatchQueue.main.async {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let uiImage = UIImage(ciImage: ciImage)
            self.trackingView.image = uiImage
            self.trackingView.polyRects = rects
            self.trackingView.targetSpeedStart = CGPoint(x: observedPositionX, y: observedPositionY)
            self.trackingView.targetSpeedEnd = CGPoint(x: posX, y: posY)
            self.trackingView.targetReticle = CGPoint(x: posX, y: posY_corrected)
            
            self.distanceLabel.text = "Target size: "+String(Double(round(10 * droneSize) / 10)) + "m, Target angular size: " + String(Double(round(10 * observedAngularSize) / 10)) + "deg"
            self.angleLabel.text = "(Spherical) Target distance: " + String(Double(round(10 * distance) / 10))+"m, Target Azimuth: "+String(Double(round(10 * droneAzimuth) / 10)) + "deg, Target Elevation: " + String(Double(round(10 * droneElevation) / 10)) + "deg"
            
            self.positionLabel.text = "(Cartesian) X: "+String(Double(round(10 * dronePos.position.x) / 10)) + ", Y: " + String(Double(round(10 * dronePos.position.y) / 10)) + ", Z: " + String(Double(round(10 * dronePos.position.z) / 10)) + "; Target speed: " + String(Double(round(10 * speedVec.length) / 10)) + "m/s"
            self.trackingView.setNeedsDisplay()
        }
        
        
    }
    
    
    private func handleError(_ error: Error) {
        DispatchQueue.main.async {
            var title: String
            var message: String
            title = "Error"
            message = "Error"
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }
    


    func updateObservations() {
        self.sequenceRequestHandler = VNSequenceRequestHandler()
        self.inputObservations.removeAll()
        self.trackedObjects.removeAll()
        self.inputObservations = [UUID: VNDetectedObjectObservation]()
        self.trackedObjects = [UUID: TrackedPolyRect]()
        for rect in self.objectsToTrack {
            let inputObservation = VNDetectedObjectObservation(boundingBox: rect.boundingBox)
            self.inputObservations[inputObservation.uuid] = inputObservation
            self.trackedObjects[inputObservation.uuid] = rect
        }
        
        
    }
    

    @objc func didPan(sender: UIPanGestureRecognizer) {
        switch sender.state {
        case .began:
            let locationInView = sender.location(in: trackingView)
            if trackingView.isPointWithinDrawingArea(locationInView) {
                trackingView.rubberbandingStart = locationInView // start new rubberbanding
            }
        case .changed:
            let translation = sender.translation(in: trackingView)
            let endPoint = trackingView.rubberbandingStart.applying(CGAffineTransform(translationX: translation.x, y: translation.y))
            guard trackingView.isPointWithinDrawingArea(endPoint) else {
                return
            }
            trackingView.rubberbandingVector = translation
            trackingView.setNeedsDisplay()
        case .ended:
            let selectedBBox = trackingView.rubberbandingRectNormalized
            if selectedBBox.width > 0 && selectedBBox.height > 0 {
                let rectColor = TrackedObjectsPalette.color(atIndex: self.objectsToTrack.count)
                self.objectsToTrack.append(TrackedPolyRect(cgRect: selectedBBox, color: rectColor))
                self.updateObservations()
                self.trackingView.rubberbandingStart = CGPoint.zero
                self.trackingView.rubberbandingVector = CGPoint.zero
            }
        default:
            break
        }
    }
}

struct HostedTrackingViewController: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        return TrackingViewController()
        }

        func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        }
}
