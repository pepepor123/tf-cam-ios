//
//  SecondViewController.swift
//  tf-cam
//
//  Created by hrbysnk on 2020/10/02.
//

import UIKit
import AVFoundation

class SecondViewController: UIViewController {

  var previewView: PreviewView!
  var overlayView: OverlayView!
  let button = UIButton(frame: CGRect(x: 40, y: 60, width: 120, height: 60))
  private lazy var cameraFeedManager = CameraFeedManager(previewView: previewView)

  // MARK: Constants
  private let displayFont = UIFont.systemFont(ofSize: 14.0, weight: .medium)
  private let edgeOffset: CGFloat = 2.0
  private let labelOffset: CGFloat = 10.0
  private let delayBetweenInferencesMs: Double = 200

  // Holds the detection result
  private var result: Result?
  private var previousInferenceTimeMs: TimeInterval = Date.distantPast.timeIntervalSince1970 * 1000

  private var modelDataHandler: ModelDataHandler? = ModelDataHandler(modelFileInfo: MobileNetSSD.modelInfo, labelsFileInfo: MobileNetSSD.labelsInfo)

  init() {
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var prefersStatusBarHidden: Bool {
    return true
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor.black
    navigationItem.title = "Second View"

    previewView = PreviewView(frame: self.view.bounds)

    let overlayViewHeight = self.view.bounds.height
    let overlayViewWidth = overlayViewHeight * (4 / 3)
    let marginLeft = (self.view.bounds.width - overlayViewWidth) / 2
    let overlayViewFrame = CGRect(x: marginLeft, y: 0, width: overlayViewWidth, height: overlayViewHeight)
    overlayView = OverlayView(frame: overlayViewFrame)
    overlayView.clearsContextBeforeDrawing = true
    overlayView.backgroundColor = UIColor.clear

    cameraFeedManager.delegate = self
    cameraFeedManager.checkCameraConfigurationAndStartSession()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    self.previewView.previewLayer.connection?.videoOrientation = .landscapeLeft
    self.previewView.previewLayer.videoGravity = .resizeAspect
    view.addSubview(previewView)
    view.addSubview(overlayView)

    button.backgroundColor = UIColor.yellow
    button.setTitle("button", for: .normal)
    button.setTitleColor(.black, for: .normal)
    button.addTarget(self, action: #selector(btnFunc), for: .touchUpInside)
    self.view.addSubview(button)
  }

  @objc func btnFunc() {
    print("Button was pressed.")
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    cameraFeedManager.stopSession()
  }

}

// MARK: CameraFeedManagerDelegate Methods
extension SecondViewController: CameraFeedManagerDelegate {

  func didOutput(pixelBuffer: CVPixelBuffer) {
    runModel(onPixelBuffer: pixelBuffer)
  }

  func presentVideoConfigurationErrorAlert() {
    let alertController = UIAlertController(
      title: "Confirguration Failed",
      message: "Configuration of camera has failed.",
      preferredStyle: .alert
    )
    
    let okAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
    alertController.addAction(okAction)

    present(alertController, animated: true, completion: nil)
  }

  func presentCameraPermissionsDeniedAlert() {
    let alertController = UIAlertController(
      title: "Camera Permissions Denied",
      message: "Camera permissions have been denied for this app. You can change this by going to Settings",
      preferredStyle: .alert
    )

    let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
    let settingsAction = UIAlertAction(title: "Settings", style: .default) { (action) in
      UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:], completionHandler: nil)
    }

    alertController.addAction(cancelAction)
    alertController.addAction(settingsAction)

    present(alertController, animated: true, completion: nil)
  }

  /**
   This method runs the live camera pixelBuffer through TensorFlow to get the result.
   */
  @objc  func runModel(onPixelBuffer pixelBuffer: CVPixelBuffer) {
    
    let currentTimeMs = Date().timeIntervalSince1970 * 1000

    guard (currentTimeMs - previousInferenceTimeMs) >= delayBetweenInferencesMs else {
      return
    }

    previousInferenceTimeMs = currentTimeMs
    result = self.modelDataHandler?.runModel(onFrame: pixelBuffer)

    guard let displayResult = result else {
      return
    }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    DispatchQueue.main.async {
      // Draws the bounding boxes, class names, and confidence scores.
      self.drawAfterPerformingCalculations(onInferences: displayResult.inferences, withImageSize: CGSize(width: CGFloat(width), height: CGFloat(height)))
    }

  }

  /**
   This method draws the bounding boxes, class names, and confidence scores of inferences.
   */
  func drawAfterPerformingCalculations(onInferences inferences: [Inference], withImageSize imageSize: CGSize) {

    self.overlayView.objectOverlays = []
    self.overlayView.setNeedsDisplay()

    guard !inferences.isEmpty else {
      return
    }

    var objectOverlays: [ObjectOverlay] = []

    for inference in inferences {

      // Scales the bounding box rect with respect to the `overlayView` dimensions.
      var convertedRect = inference.rect.applying(CGAffineTransform(scaleX: self.overlayView.bounds.size.width / imageSize.width, y: self.overlayView.bounds.size.height / imageSize.height))

      if convertedRect.origin.x < 0 {
        convertedRect.origin.x = self.edgeOffset
      }

      if convertedRect.origin.y < 0 {
        convertedRect.origin.y = self.edgeOffset
      }

      if convertedRect.maxY > self.overlayView.bounds.maxY {
        convertedRect.size.height = self.overlayView.bounds.maxY - convertedRect.origin.y - self.edgeOffset
      }

      if convertedRect.maxX > self.overlayView.bounds.maxX {
        convertedRect.size.width = self.overlayView.bounds.maxX - convertedRect.origin.x - self.edgeOffset
      }

      let confidenceValue = Int(inference.confidence * 100.0)
      let string = "\(inference.className)  (\(confidenceValue)%)"

      let size = string.size(usingFont: self.displayFont)

      let objectOverlay = ObjectOverlay(name: string, borderRect: convertedRect, nameStringSize: size, color: inference.displayColor, font: self.displayFont)

      objectOverlays.append(objectOverlay)
    }

    // Hands off drawing to the `overlayView`.
    self.draw(objectOverlays: objectOverlays)

  }

  /**
   This method updates the `overlayView` with detected bounding boxes and class names.
   */
  func draw(objectOverlays: [ObjectOverlay]) {
    self.overlayView.objectOverlays = objectOverlays
    self.overlayView.setNeedsDisplay()
  }

}

extension String {
  /**
   This method gets the size of a string with a particular font.
   */
  func size(usingFont font: UIFont) -> CGSize {
    let attributedString = NSAttributedString(string: self, attributes: [NSAttributedString.Key.font : font])
    return attributedString.size()
  }
}

