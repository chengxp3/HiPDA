//
//  HomeViewController.swift
//  HiPDA
//
//  Created by leizh007 on 16/9/3.
//  Copyright © 2016年 HiPDA. All rights reserved.
//

import UIKit
import Moya
import RxSwift
import RxCocoa

/// 主页的ViewController
class HomeViewController: BaseViewController {
    /// 是否展示登录成功的提示信息
    private var showLoginSuccessInformation = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if Settings.shared.activeAccount != nil {
            self.showPromptInformation(of: .loading)
        }
        
        Driver.combineLatest(EventBus.shared.activeAccount, isAppeared.asDriver()) { ($0, $1) }
            .filter { $0.1 }
            .map { $0.0 }
            .drive(onNext: { [weak self] (result) in
            guard let `self` = self, let result = result else { return }
            self.hidePromptInformation()
            switch result {
            case .success(_):
                if self.showLoginSuccessInformation {
                    self.showPromptInformation(of: .success("登录成功"))
                    self.showLoginSuccessInformation = false
                }
                // FIXME: - Do load data action
            case .failure(let error):
                self.showPromptInformation(of: .failure("\(error)"))
                self.showLoginSuccessInformation = false
            }
        }).addDisposableTo(disposeBag)
    }
    
    override func configureApperance(of navigationBar: UINavigationBar) {
        super.configureApperance(of: navigationBar)
        navigationItem.title = "Discovery"
    }
}
