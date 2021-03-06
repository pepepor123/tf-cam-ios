//
//  ViewController.swift
//  tf-cam
//
//  Created by hrbysnk on 2020/10/01.
//

import UIKit
import AVFoundation

var selectedCategory = ""

class ViewController: UIViewController {

  var tableView = UITableView()
  var tableData = [[String: String]]()

  var cameraPermission: AVAuthorizationStatus = .notDetermined

  override var prefersStatusBarHidden: Bool {
    return true
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor.white
    navigationItem.title = "被写体カテゴリ選択画面"

    guard let fileURL = Bundle.main.url(forResource: "labelmap", withExtension: "txt")  else {
      fatalError("Could not find file")
    }

    guard let fileContents = try? String(contentsOf: fileURL) else {
      fatalError("Could not read file")
    }

    let lines = fileContents.components(separatedBy: "\n")
    for line in lines {
      let category = line.components(separatedBy: ",")
      if category[0] != "???" && category[0] != "" {
        tableData.append(["label": category[0], "label_jp": category[1]])
      }
    }

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
    cell.textLabel?.text = tableData[indexPath.row]["label_jp"]
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    print("Cell \(indexPath.row) was pressed.")
    selectedCategory = tableData[indexPath.row]["label"] ?? ""
    let vc = SecondViewController()
    navigationController?.pushViewController(vc, animated: true)
  }

}

