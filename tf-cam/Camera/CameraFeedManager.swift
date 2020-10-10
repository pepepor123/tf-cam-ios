//
//  CameraFeedManager.swift
//  tf-cam
//
//  Created by hrbysnk on 2020/10/05.
//

import UIKit
import AVFoundation

// MARK: CameraFeedManagerDelegate Declaration
protocol CameraFeedManagerDelegate: class {

  /**
   This method delivers the pixel buffer of the current frame seen by the device's camera.
   */
  func didOutput(pixelBuffer: CVPixelBuffer)

  /**
   This method intimates that the camera permissions have been denied.
   */
  func presentCameraPermissionsDeniedAlert()

  /**
   This method intimates that there was an error in the video configuration.
   */
  func presentVideoConfigurationErrorAlert()

}

/**
 This enum holds the states of the camera initialization.
 */
enum CameraConfiguration {
  case success
  case failure
  case permissionDenied
}

/**
 This class manages all camera related functionalities.
 */
class CameraFeedManager: NSObject {

  // MARK: Camera Related Instance Variables
  let session: AVCaptureSession = AVCaptureSession()
  private let previewView: PreviewView
  private let sessionQueue = DispatchQueue(label: "sessionQueue")
  private var cameraConfiguration: CameraConfiguration = .failure
  private var videoDataOutput = AVCaptureVideoDataOutput()
  private var photoOutput =  AVCapturePhotoOutput()
  private var isSessionRunning = false

  // MARK: CameraFeedManagerDelegate
  weak var delegate: CameraFeedManagerDelegate?

  // MARK: Initializer
  init(previewView: PreviewView) {
    self.previewView = previewView
    super.init()

    // Initializes the session.
    session.sessionPreset = .photo
    self.previewView.session = session
    self.attemptToConfigureSession()
  }

  // MARK: Session Start and End methods

  /**
   This method starts an AVCaptureSession based on whether the camera configuration was successful.
   */
  func checkCameraConfigurationAndStartSession() {
    sessionQueue.async {
      switch self.cameraConfiguration {
      case .success:
        self.addObservers()
        self.startSession()
      case .failure:
        DispatchQueue.main.async {
          self.delegate?.presentVideoConfigurationErrorAlert()
        }
      case .permissionDenied:
        DispatchQueue.main.async {
          self.delegate?.presentCameraPermissionsDeniedAlert()
        }
      }
    }
  }

  /**
   This method stops an AVCaptureSession.
   */
  func stopSession() {
    self.removeObservers()
    sessionQueue.async {
      if self.session.isRunning {
        self.session.stopRunning()
        self.isSessionRunning = self.session.isRunning
      }
    }
  }

  /**
   This method resumes an interrupted AVCaptureSession.
   */
  func resumeInterruptedSession(withCompletion completion: @escaping (Bool) -> ()) {
    sessionQueue.async {
      self.startSession()

      DispatchQueue.main.async {
        completion(self.isSessionRunning)
      }
    }
  }

  /**
   This method starts the AVCaptureSession
   */
  private func startSession() {
    self.session.startRunning()
    self.isSessionRunning = self.session.isRunning
  }

  // MARK: Session Configuration Methods.
  /**
   This method requests camera permissions, handles the configuration of the session, and stores the result of configuration.
   */
  private func attemptToConfigureSession() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      self.cameraConfiguration = .success
//    case .notDetermined:
//      self.sessionQueue.suspend()
//      self.requestCameraAccess(completion: { (granted) in
//        self.sessionQueue.resume()
//      })
    case .denied:
      self.cameraConfiguration = .permissionDenied
    default:
      break
    }

    self.sessionQueue.async {
      self.configureSession()
    }
  }

  /**
   This method requests camera permissions.
   */
  private func requestCameraAccess(completion: @escaping (Bool) -> ()) {
    AVCaptureDevice.requestAccess(for: .video) { (granted) in
      if !granted {
        self.cameraConfiguration = .permissionDenied
      }
      else {
        self.cameraConfiguration = .success
      }
      completion(granted)
    }
  }


  /**
   This method handles all the steps to configure an AVCaptureSession.
   */
  private func configureSession() {
    guard cameraConfiguration == .success else {
      return
    }
    session.beginConfiguration()

    // Tries to add an AVCaptureDeviceInput.
    guard addVideoDeviceInput() == true else {
      self.session.commitConfiguration()
      self.cameraConfiguration = .failure
      return
    }

    // Tries to add an AVCaptureVideoDataOutput.
    guard addVideoDataOutput() else {
      self.session.commitConfiguration()
      self.cameraConfiguration = .failure
      return
    }

    // Tries to add an AVCapturePhotoOutput.
    guard addPhotoOutput() else {
      self.session.commitConfiguration()
      self.cameraConfiguration = .failure
      return
    }

    session.commitConfiguration()
    self.cameraConfiguration = .success
  }

  /**
   This method tries to add an AVCaptureDeviceInput to the current AVCaptureSession.
   */
  private func addVideoDeviceInput() -> Bool {
    // Tries to get the default back camera.
    guard let camera  = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
      fatalError("Cannot find camera")
    }

    do {
      let videoDeviceInput = try AVCaptureDeviceInput(device: camera)
      if session.canAddInput(videoDeviceInput) {
        session.addInput(videoDeviceInput)
        return true
      }
      else {
        return false
      }
    }
    catch {
      fatalError("Cannot create video device input")
    }
  }

  /**
   This method tries to add an AVCaptureVideoDataOutput to the current AVCaptureSession.
   */
  private func addVideoDataOutput() -> Bool {
    let sampleBufferQueue = DispatchQueue(label: "sampleBufferQueue")
    videoDataOutput.setSampleBufferDelegate(self, queue: sampleBufferQueue)
    videoDataOutput.alwaysDiscardsLateVideoFrames = true
    videoDataOutput.videoSettings = [ String(kCVPixelBufferPixelFormatTypeKey) : kCMPixelFormat_32BGRA]

    if session.canAddOutput(videoDataOutput) {
      session.addOutput(videoDataOutput)
      videoDataOutput.connection(with: .video)?.videoOrientation = .landscapeLeft
      return true
    }
    return false
  }

  /**
   This method tries to add an AVCapturePhotoOutput to the current AVCaptureSession.
   */
  private func addPhotoOutput() -> Bool {
    if session.canAddOutput(photoOutput) {
      session.addOutput(photoOutput)
      photoOutput.connection(with: .video)?.videoOrientation = .landscapeLeft
      return true
    }
    return false
  }

  // MARK: Notification Observer Handling
  private func addObservers() {
    NotificationCenter.default.addObserver(self, selector: #selector(CameraFeedManager.sessionRuntimeErrorOccurred(notification:)), name: NSNotification.Name.AVCaptureSessionRuntimeError, object: session)
    NotificationCenter.default.addObserver(self, selector: #selector(CameraFeedManager.sessionWasInterrupted(notification:)), name: NSNotification.Name.AVCaptureSessionWasInterrupted, object: session)
    NotificationCenter.default.addObserver(self, selector: #selector(CameraFeedManager.sessionInterruptionEnded), name: NSNotification.Name.AVCaptureSessionInterruptionEnded, object: session)
  }

  private func removeObservers() {
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVCaptureSessionRuntimeError, object: session)
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVCaptureSessionWasInterrupted, object: session)
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVCaptureSessionInterruptionEnded, object: session)
  }

  // MARK: Notification Observers
  @objc func sessionWasInterrupted(notification: Notification) {
    if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
      let reasonIntegerValue = userInfoValue.integerValue,
      let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
      print("Capture session was interrupted with reason \(reason.rawValue)")
    }
  }

  @objc func sessionInterruptionEnded(notification: Notification) {
    print("Capture session interruption ended")
  }

  @objc func sessionRuntimeErrorOccurred(notification: Notification) {
    guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else {
      return
    }

    print("Capture session runtime error: \(error)")

    if error.code == .mediaServicesWereReset {
      sessionQueue.async {
        if self.isSessionRunning {
          self.startSession()
        }
      }
    }
  }

  /**
   This method takes a photo and saves it to the user's Camera Roll album.
   */
  func takePhoto() {
    let photoSettings = AVCapturePhotoSettings()
    photoSettings.flashMode = .auto
    photoSettings.isHighResolutionPhotoEnabled = false
    photoOutput.capturePhoto(with: photoSettings, delegate: self)
  }

}

/**
 AVCaptureVideoDataOutputSampleBufferDelegate
 */
extension CameraFeedManager: AVCaptureVideoDataOutputSampleBufferDelegate {
  /**
   This method delegates the CVPixelBuffer of the frame seen by the camera.
   */
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

    // Converts the CMSampleBuffer to a CVPixelBuffer.
    let pixelBuffer: CVPixelBuffer? = CMSampleBufferGetImageBuffer(sampleBuffer)

    guard let imagePixelBuffer = pixelBuffer else {
      return
    }

    // Delegates the pixel buffer to the ViewController.
    delegate?.didOutput(pixelBuffer: imagePixelBuffer)
  }
}

/**
 AVCapturePhotoCaptureDelegate
 */
extension CameraFeedManager: AVCapturePhotoCaptureDelegate {
  /**
   This method saves the photo to the user's Camera Roll album.
   */
  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
    let imageData = photo.fileDataRepresentation()
    let photo = UIImage(data: imageData!)
    UIImageWriteToSavedPhotosAlbum(photo!, self, nil, nil)
  }

}

