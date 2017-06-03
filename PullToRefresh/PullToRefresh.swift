//
//  Created by Anastasiya Gorban on 4/14/15.
//  Copyright (c) 2015 Yalantis. All rights reserved.
//
//  Licensed under the MIT license: http://opensource.org/licenses/MIT
//  Latest version can be found at https://github.com/Yalantis/PullToRefresh
//

import UIKit

public enum Position {
    
    case scrollTop, top, bottom
}

open class PullToRefresh: NSObject {
    
    open var position: Position = .top
    
    open var animationDuration: TimeInterval = 1
    open var hideDelay: TimeInterval = 0
    open var springDamping: CGFloat = 0.4
    open var initialSpringVelocity: CGFloat = 0.8
    open var animationOptions: UIViewAnimationOptions = [.curveLinear]

    let refreshView: UIView
    var action: (() -> ())?
    
    fileprivate var isObserving = false
    fileprivate let animator: RefreshViewAnimator
    
    // MARK: - ScrollView & Observing

    fileprivate var isModifyingInsetsInternally = false
    fileprivate var scrollViewDefaultInsets: UIEdgeInsets = .zero
    weak var scrollView: UIScrollView? {
        willSet {
            removeScrollViewObserving()
        }
        didSet {
            if let scrollView = scrollView {
                scrollViewDefaultInsets = scrollView.contentInset
                addScrollViewObserving()
            }
        }
    }
    
    // MARK: - State
    
    open fileprivate(set) var state: State = .initial {
        didSet {
            animator.animate(state)
            switch state {
            case .loading:
                if oldValue != .loading {
                    animateLoadingState()
                }
                
            case .finished:
                if isCurrentlyVisible() {
                    animateFinishedState()
                } else {
                    scrollView?.contentInset = self.scrollViewDefaultInsets
                    state = .initial
                }
        
            default: break
            }
        }
    }
    
    // MARK: - Initialization
    
    public init(refreshView: UIView, animator: RefreshViewAnimator, height: CGFloat, position: Position) {
        self.refreshView = refreshView
        self.animator = animator
        self.position = position
    }
    
    public convenience init(height: CGFloat = 40, position: Position = .top) {
        let refreshView = DefaultRefreshView()
        refreshView.translatesAutoresizingMaskIntoConstraints = false
        refreshView.autoresizingMask = [.flexibleWidth]
        refreshView.frame.size.height = height
        self.init(refreshView: refreshView, animator: DefaultViewAnimator(refreshView: refreshView), height: height, position: position)
    }
    
    deinit {
        removeScrollViewObserving()
    }
    
    // MARK: KVO

    fileprivate var KVOContext = "PullToRefreshKVOContext"
    fileprivate let contentOffsetKeyPath = "contentOffset"
    fileprivate let contentInsetKeyPath = "contentInset"
    fileprivate let contentSizeKeyPath = "contentSize"
    fileprivate var previousOffset: CGFloat = 0.0
    
    override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let scrollView = scrollView, context == &KVOContext && object as? UIScrollView == scrollView else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        
        if (keyPath == contentOffsetKeyPath) {
            var offset: CGFloat
            switch position {
            case .scrollTop:
                let rect = scrollView.convert(scrollView.bounds, to: scrollView)
                let y = min(rect.origin.y, -(scrollViewDefaultInsets.top + refreshView.bounds.height))
                refreshView.frame = CGRect(x: rect.origin.x, y: y, width: rect.size.width, height: refreshView.bounds.height)
                fallthrough
            case .top:
                offset = previousOffset + scrollViewDefaultInsets.top
                
            case .bottom:
                if scrollView.contentSize.height > scrollView.bounds.height {
                    offset = scrollView.contentSize.height - previousOffset - scrollView.bounds.height
                } else {
                    offset = scrollView.contentSize.height - previousOffset
                }
            }
            let refreshViewHeight = refreshView.frame.size.height
            
            switch offset {
            case 0 where (state != .loading): state = .initial
            case -refreshViewHeight...0 where (state != .loading && state != .finished):
                state = .releasing(progress: -offset / refreshViewHeight)
                
            case -1000...(-refreshViewHeight):
                if state == .releasing(progress: 1) && scrollView.isDragging == false {
                    state = .loading
                } else if state != .loading && state != .finished {
                    state = .releasing(progress: 1)
                }
            default: break
            }
        } else if (keyPath == contentSizeKeyPath) {
            if case .bottom = position {
                refreshView.frame = CGRect(x: 0, y: scrollView.contentSize.height, width: scrollView.bounds.width, height: refreshView.bounds.height)
            }
        } else if (keyPath == contentInsetKeyPath) {
            if !isModifyingInsetsInternally {
                scrollViewDefaultInsets = scrollView.contentInset
            }
          
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
        
        previousOffset = scrollView.contentOffset.y
    }
    
    fileprivate func addScrollViewObserving() {
        guard let scrollView = scrollView, !isObserving else {
            return
        }
        
        scrollView.addObserver(self, forKeyPath: contentOffsetKeyPath, options: .initial, context: &KVOContext)
        scrollView.addObserver(self, forKeyPath: contentSizeKeyPath, options: .initial, context: &KVOContext)
        scrollView.addObserver(self, forKeyPath: contentInsetKeyPath, options: .new, context: &KVOContext)
      
        isObserving = true
    }
    
    fileprivate func removeScrollViewObserving() {
        guard let scrollView = scrollView, isObserving else {
            return
        }
        
        scrollView.removeObserver(self, forKeyPath: contentOffsetKeyPath, context: &KVOContext)
        scrollView.removeObserver(self, forKeyPath: contentSizeKeyPath, context: &KVOContext)
        scrollView.removeObserver(self, forKeyPath: contentInsetKeyPath, context: &KVOContext)
      
        isObserving = false
    }
}

// MARK: - Start/End Refreshin
extension PullToRefresh {
    
    func startRefreshing() {
        guard let scrollView = scrollView else { return }
        
        if self.state != .initial {
            return
        }
        
        var offsetY: CGFloat
        switch position {
        case .top, .scrollTop:
            offsetY = -refreshView.frame.height - scrollViewDefaultInsets.top
            
        case .bottom:
            offsetY = scrollView.contentSize.height + refreshView.frame.height + scrollViewDefaultInsets.bottom - scrollView.bounds.height
        }

        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: offsetY), animated: true)
        let delayTime = DispatchTime.now() + 0.27
        DispatchQueue.main.asyncAfter(deadline: delayTime) { [weak self] in
            self?.state = .loading
        }
    }
    
    func endRefreshing() {
        if state == .loading {
            state = .finished
        }
    }
}

// MARK: - Animate scroll view
private extension PullToRefresh {
    
    func animateLoadingState() {
        guard let scrollView = scrollView else { return }
        
        scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: previousOffset)
        scrollView.bounces = false
        UIView.animate(
            withDuration: 0.3,
            animations: {
                switch self.position {
                case .top, .scrollTop:
                    let insets = self.refreshView.frame.height + self.scrollViewDefaultInsets.top
                    self.isModifyingInsetsInternally = true
                    scrollView.contentInset.top = insets
                    self.isModifyingInsetsInternally = false
                    scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: -insets)
                    
                case .bottom:
                    let insets = self.refreshView.frame.height + self.scrollViewDefaultInsets.bottom
                    self.isModifyingInsetsInternally = true
                    scrollView.contentInset.bottom = insets
                    self.isModifyingInsetsInternally = false
                }
            },
            completion: { _ in
                scrollView.bounces = true
            }
        )
        
        action?()
    }
    
    func animateFinishedState() {
        removeScrollViewObserving()
        UIView.animate(
            withDuration: animationDuration,
            delay: hideDelay,
            usingSpringWithDamping: springDamping,
            initialSpringVelocity: initialSpringVelocity,
            options: animationOptions,
            animations: {
                self.scrollView?.contentInset = self.scrollViewDefaultInsets
                if case .top = self.position {
                    self.scrollView?.contentOffset.y = -self.scrollViewDefaultInsets.top
                }
            },
            completion: { _ in
                self.addScrollViewObserving()
                self.state = .initial
            }
        )
    }
}

// MARK: - Helpers
private extension PullToRefresh {
    
    func isCurrentlyVisible() -> Bool {
        guard let scrollView = scrollView else { return false }
        
        return scrollView.contentOffset.y <= -scrollViewDefaultInsets.top
    }
}
