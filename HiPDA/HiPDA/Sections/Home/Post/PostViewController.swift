//
//  PostViewController.swift
//  HiPDA
//
//  Created by leizh007 on 2017/5/15.
//  Copyright © 2017年 HiPDA. All rights reserved.
//

import UIKit
import WebKit
import WebViewJavascriptBridge
import MJRefresh
import MLeaksFinder
import Perform
import Argo
import SDWebImage

/// 浏览帖子页面
class PostViewController: BaseViewController {
    fileprivate static let shared = PostViewController.load(from: .home)
    
    var postInfo: PostInfo! {
        didSet {
            guard let viewModel = viewModel else { return }
            viewModel.postInfo = postInfo
        }
    }
    
    fileprivate var viewModel: PostViewModel!
    fileprivate var webView: BaseWebView!
    fileprivate var bridge: WKWebViewJavascriptBridge!
    fileprivate lazy var imageUtils = ImageUtils()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        viewModel = PostViewModel(postInfo: postInfo)
        webView = BaseWebView()
        view.addSubview(webView)
        bridge = WKWebViewJavascriptBridge(for: webView)
        bridge.setWebViewDelegate(self)
        skinWebView(webView)
        skinWebViewJavascriptBridge(bridge)
        loadData()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        let yOffset = C.UI.navigationBarHeight + C.UI.statusBarHeight
        webView.frame = CGRect(x: 0,
                               y: yOffset,
                               width: view.bounds.size.width,
                               height: view.bounds.size.height - yOffset)
    }
    
    func canJump(to postInfo: PostInfo) -> Bool {
        return postInfo.authorid == self.viewModel.postInfo.authorid &&
            postInfo.tid == self.viewModel.postInfo.tid &&
            postInfo.page == self.viewModel.postInfo.page &&
            viewModel.contains(pid: postInfo.pid)
    }
    
    func jump(to postInfo: PostInfo) {
        guard canJump(to: postInfo) else { return }
        if let pid =  postInfo.pid {
            bridge.callHandler("jumpToPid", data: pid)
        }
    }
    
    fileprivate func updateWebViewState() {
        let states: [MJRefreshState] = [.idle, .pulling, .refreshing]
        for state in states {
            webView.refreshHeader?.setTitle(viewModel.headerTitle(for: state), for: state)
        }
    }
    
    override func configureApperance(of navigationBar: UINavigationBar) {
        if navigationController?.viewControllers.count == 1 {
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: #imageLiteral(resourceName: "image_browser_close"), style: .plain, target: self, action: #selector(close))
        }
    }
    
    func close() {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    fileprivate func animationOptions(of status: PostViewStatus) -> UIViewAnimationOptions {
        switch status {
        case .loadingFirstPage:
            return [.allowAnimatedContent]
        case .loadingPreviousPage:
            return [.transitionCurlDown, .allowAnimatedContent]
        case .loadingNextPage:
            return [.transitionCurlUp, .allowAnimatedContent]
        default:
            return [.allowAnimatedContent]
        }
    }
    
    fileprivate func  handleDataLoadResult(_ result: PostResult) {
        switch result {
        case .success(let html):
            if viewModel.hasData {
                let options = animationOptions(of: viewModel.status)
                UIView.transition(with: webView, duration: C.UI.animationDuration * 4.0, options: options, animations: {
                    self.webView.loadHTMLString(html, baseURL: C.URL.baseWebViewURL)
                    self.configureWebViewAfterLoadData()
                }, completion: nil)
            } else {
                webView.endRefreshing()
                webView.endLoadMore()
                webView.status = .noResult
                viewModel.status = .idle
            }
        case .failure(let error):
            showPromptInformation(of: .failure("\(error)"))
            viewModel.status = .idle
            if webView.status == .loading {
                webView.status = .tapToLoad
            } else {
                webView.endRefreshing()
                webView.endLoadMore()
            }
        }
    }
    
    fileprivate func configureWebViewAfterLoadData() {
        if webView.status == .pullUpLoading {
            if viewModel.hasMoreData {
                webView.endLoadMore()
                webView.resetNoMoreData()
            } else {
                webView.endLoadMoreWithNoMoreData()
            }
        } else if webView.status ==  .pullDownRefreshing {
            webView.endRefreshing()
            if viewModel.hasMoreData {
                webView.resetNoMoreData()
            } else {
                webView.endLoadMoreWithNoMoreData()
            }
        } else {
            if viewModel.hasMoreData {
                webView.resetNoMoreData()
            } else {
                webView.endLoadMoreWithNoMoreData()
            }
        }
        webView.status = .normal
        viewModel.status = .idle
    }
}

// MARK: - Initialization Configure

extension PostViewController {
    fileprivate func skinWebView(_ webView: BaseWebView) {
        webView.hasRefreshHeader = true
        webView.hasLoadMoreFooter = true
        webView.loadMoreFooter?.isHidden = true
        webView.scrollView.delegate = self
        webView.allowsLinkPreview = false
        webView.uiDelegate = self
        webView.scrollView.backgroundColor = .groupTableViewBackground
        #if RELEASE
            webView.scrollView.showsHorizontalScrollIndicator = false
        #endif
        let states: [MJRefreshState] = [.idle, .pulling, .refreshing, .noMoreData]
        for state in states {
            webView.loadMoreFooter?.setTitle(viewModel.footerTitle(for: state), for: state)
        }
        webView.dataLoadDelegate = self
        webView.status = .loading
    }
    
    fileprivate func skinWebViewJavascriptBridge(_ bridge: WKWebViewJavascriptBridge) {
        bridge.registerHandler("userClicked") { [weak self] (data, _) in
            guard let `self` = self,
                let data = data,
                let user = try? User.decode(JSON(data)).dematerialize() else { return }
            self.perform(.userProfile) { userProfileVC in
                userProfileVC.user = user
            }
        }
        
        bridge.registerHandler("shouldImageAutoLoad") { [weak self] (_, callback) in
            self?.viewModel.shouldAutoLoadImage { autoLoad in
                callback?(autoLoad)
            }
        }
        
        bridge.registerHandler("linkActivated") { (data, _) in
            guard let data = data, let urlString = data as? String else { return }
            URLDispatchManager.shared.linkActived(PostViewModel.skinURL(url: urlString))
        }
        
        bridge.registerHandler("postClicked") { [weak self] (data, _) in
            guard let data = data, let pid = data as? Int else { return }
            self?.postClicked(pid: pid)
        }
        
        bridge.registerHandler("imageClicked") { [weak self] (data, _) in
            guard let data  = data,
                let dic = data as? [String: Any],
                let clickedImageURL = dic["clickedImageSrc"] as? String,
                let imageURLs = dic["imageSrcs"] as? [String] else { return }
            self?.imageClicked(clickedImageURL: clickedImageURL, imageURLs: imageURLs)
        }
        
        bridge.registerHandler("loadImage") { [weak self] (data, callback) in
            guard let data = data, let url = data as? String else { return }
            self?.viewModel.loadImage(url: url) { error in
                callback?(error == nil)
                if let error = error {
                    self?.showPromptInformation(of: .failure(error.localizedDescription))
                }
            }
        }
        
        bridge.registerHandler("imageLongPressed") { [weak self] (data, _) in
            guard let data = data, let url = data as? String else { return }
            self?.imageLongPressed(url: url)
        }
        
        if let pid =  postInfo.pid {
            bridge.callHandler("jumpToPid", data: pid)
        }
    }
}

// MARK: - Bridge Handler

extension PostViewController {
    fileprivate func postClicked(pid: Int) {
        // FIEXME: - Handle post clicked
        console(message: "\(pid)")
    }
    
    fileprivate func imageClicked(clickedImageURL: String, imageURLs: [String]) {
        showImageBrowser(clickedImageURL: clickedImageURL, imageURLs: imageURLs)
    }
    
    fileprivate func imageLongPressed(url: String) {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let look = UIAlertAction(title: "查看", style: .default) { [weak self] _ in
            self?.showImageBrowser(clickedImageURL: url, imageURLs: [url])
        }
        let copy = UIAlertAction(title: "复制", style: .default) { [weak self] _ in
            guard let `self` = self else { return }
            self.showPromptInformation(of: .loading("正在复制..."))
            ImageUtils.copyImage(url: url) { [weak self] (result) in
                self?.hidePromptInformation()
                switch result {
                case let .failure(error):
                    self?.showPromptInformation(of: .failure(error.localizedDescription))
                case .success(_):
                    self?.showPromptInformation(of: .success("复制成功！"))
                }
            }
        }
        let save = UIAlertAction(title: "保存", style: .default) { [weak self] _ in
            guard let `self` = self else { return }
            self.showPromptInformation(of: .loading("正在保存..."))
            ImageUtils.saveImage(url: url) { [weak self] (result) in
                self?.hidePromptInformation()
                switch result {
                case let .failure(error):
                    self?.showPromptInformation(of: .failure(error.localizedDescription))
                case .success(_):
                    self?.showPromptInformation(of: .success("保存成功！"))
                }
            }
        }
        let detectQrCode = UIAlertAction(title: "识别图中二维码", style: .default) { [weak self] _ in
            guard let `self` = self else { return }
            self.showPromptInformation(of: .loading("正在识别..."))
            ImageUtils.qrcode(from: url) { [weak self] result in
                self?.hidePromptInformation()
                switch result {
                case let .success(qrCode):
                    self?.showQrCode(qrCode)
                case let .failure(error):
                    self?.showPromptInformation(of: .failure(error.localizedDescription))
                }
            }
        }
        let cancel = UIAlertAction(title: "取消", style: .cancel, handler: nil)
        actionSheet.addAction(look)
        actionSheet.addAction(copy)
        actionSheet.addAction(save)
        actionSheet.addAction(detectQrCode)
        actionSheet.addAction(cancel)
        present(actionSheet, animated: true, completion: nil)
    }
    
    fileprivate func showQrCode(_ qrCode: String) {
        let actionSheet = UIAlertController(title: "识别二维码", message: "二维码内容为: \(qrCode)", preferredStyle: .actionSheet)
        let copy = UIAlertAction(title: "复制", style: .default) { _ in
            UIPasteboard.general.string = qrCode
        }
        var openLink: UIAlertAction!
        if qrCode.isLink {
            openLink = UIAlertAction(title: "打开链接", style: .default, handler: { _ in
                URLDispatchManager.shared.linkActived(qrCode)
            })
        }
        let cancel = UIAlertAction(title: "取消", style: .cancel, handler: nil)
        actionSheet.addAction(copy)
        if qrCode.isLink {
            actionSheet.addAction(openLink)
        }
        actionSheet.addAction(cancel)
        present(actionSheet, animated: true, completion: nil)
    }
}

// MARK: - Image Related

extension PostViewController {
    fileprivate func showImageBrowser(clickedImageURL: String, imageURLs: [String]) {
        guard let selectedIndex = imageURLs.index(of: clickedImageURL) else { return }
        let imageBrowser = ImageBrowserViewController.load(from: .views)
        imageBrowser.imageURLs = imageURLs
        imageBrowser.selectedIndex = selectedIndex
        imageBrowser.modalPresentationStyle = .custom
        imageBrowser.modalTransitionStyle = .crossDissolve
        imageBrowser.modalPresentationCapturesStatusBarAppearance = true
        present(imageBrowser, animated: true, completion: nil)
    }
}

// MARK: - DataLoadDelegate

extension PostViewController: DataLoadDelegate {
    func loadData() {
        viewModel.loadData { [weak self] result in
            self?.updateWebViewState()
            self?.handleDataLoadResult(result)
        }
    }
    
    func loadNewData() {
        viewModel.loadNewData { [weak self] result in
            self?.updateWebViewState()
            self?.handleDataLoadResult(result)
        }
    }
    
    func loadMoreData() {
        viewModel.loadMoreData { [weak self] result in
            self?.updateWebViewState()
            self?.handleDataLoadResult(result)
        }
    }
}

// MARK: - UIScrollViewDelegate

extension PostViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return nil
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        #if RELEASE
            if scrollView.contentOffset.x > 0 || scrollView.contentOffset.x < 0 {
                scrollView.contentOffset = CGPoint(x: 0, y: scrollView.contentOffset.y)
            }
        #endif
    }
}

// MARK: - WKNavigationDelegate

extension PostViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.scrollView.backgroundColor = .groupTableViewBackground
        (webView as? BaseWebView)?.loadMoreFooter?.isHidden = false
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel : .allow)
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleWebViewError(error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleWebViewError(error)
    }
    
    private func handleWebViewError(_ error: Error) {
        #if DEBUG
            showPromptInformation(of: .failure(String(describing: error)))
        #else
            if (error as NSError).code != NSURLErrorCancelled {
                showPromptInformation(of: .failure(error.localizedDescription))
            }
        #endif
    }
}

// MARK: - WKUIDelegate

extension PostViewController: WKUIDelegate {
    @available(iOS 10.0, *)
    func webView(_ webView: WKWebView, shouldPreviewElement elementInfo: WKPreviewElementInfo) -> Bool {
        return false
    }
}

// MARK: - StoryboardLoadable

extension PostViewController: StoryboardLoadable {}

// MARK: - Segue Extesion

extension Segue {
    /// 查看个人资料
    fileprivate static var userProfile: Segue<UserProfileViewController> {
        return .init(identifier: "userProfile")
    }
}

// MARK: - Tools

private func ==<T: Equatable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let(l?, r?):
        return l == r
    case (nil, nil):
        return true
    default:
        return false
    }
}
