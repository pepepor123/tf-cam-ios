//
//  ViewController.swift
//  tf-cam
//
//  Created by hrbysnk on 2020/10/01.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {

  var tableView = UITableView()
  var tableData = ["Item 0", "Item 1", "Item 2", "Item 3"]

  var cameraPermission: AVAuthorizationStatus = .notDetermined

  override var prefersStatusBarHidden: Bool {
    return true
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor.white
    navigationItem.title = "First View"

    tableView = UITableView(frame: self.view.bounds)
    tableView.delegate = self
    tableView.dataSource = self
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "item")
    view.addSubview(tableView)

    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      print("camera: authorized")
    case .notDetermined:
      print("camera: notDetermined")
      AVCaptureDevice.requestAccess(for: .video) { (granted) in
        self.cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
      }
    case .denied:
      print("camera: denied")
    default:
      break
    }
  }
  
}

extension ViewController: UITableViewDelegate, UITableViewDataSource {

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return tableData.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "item", for: indexPath)
    cell.textLabel?.text = "Label: \(tableData[indexPath.row])"
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    print("Cell \(indexPath.row) was pressed.")
    let vc = SecondViewController()
    navigationController?.pushViewController(vc, animated: true)
  }

}

