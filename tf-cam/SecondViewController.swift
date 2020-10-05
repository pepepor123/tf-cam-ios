//
//  SecondViewController.swift
//  tf-cam
//
//  Created by hrbysnk on 2020/10/02.
//

import UIKit

class SecondViewController: UIViewController {

  var previewView: PreviewView!
  let button = UIButton(frame: CGRect(x: 40, y: 60, width: 200, height: 60))
  private lazy var cameraFeedManager = CameraFeedManager(previewView: previewView)

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
    view.backgroundColor = UIColor.white
    navigationItem.title = "Second View"

    previewView = PreviewView(frame: self.view.bounds)
    cameraFeedManager.checkCameraConfigurationAndStartSession()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    self.previewView.previewLayer.connection?.videoOrientation = .landscapeLeft
    self.previewView.previewLayer.videoGravity = .resizeAspect
    view.addSubview(previewView)

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
//    do something
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

}

