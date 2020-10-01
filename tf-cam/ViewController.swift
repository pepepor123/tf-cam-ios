//
//  ViewController.swift
//  tf-cam
//
//  Created by hrbysnk on 2020/10/01.
//

import UIKit

class ViewController: UIViewController {

  var tableView = UITableView()
  var tableData = ["Item 0", "Item 1", "Item 2", "Item 3"]

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

