//
//  SecondViewController.swift
//  tf-cam
//
//  Created by hrbysnk on 2020/10/02.
//

import UIKit

class SecondViewController: UIViewController {

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

    let button = UIButton(frame: CGRect(x: 40, y: 100, width: 200, height: 60))
    button.backgroundColor = UIColor.yellow
    button.setTitle("button", for: .normal)
    button.setTitleColor(.black, for: .normal)
    self.view.addSubview(button)
  }

}

