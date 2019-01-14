//
//  DGKeyboardScrollHandler.swift
//  DGKeyboardScrollHandler
//
//  https://github.com/danielgindi/DGKeyboardScrollHandler
//

import Foundation
import UIKit

typealias DGKeyboardScrollHandlerScrollAmountBlock = (UIScrollView, CGRect) -> CGPoint

@objc protocol DGKeyboardScrollHandlerDelegate: NSObjectProtocol
{
    @objc optional func keyboardScrollHandler(
        _ handler: DGKeyboardScrollHandler,
        didRecognizeTapAt tapPoint: CGPoint,
        on scrollView: UIScrollView,
        withKeyboardVisible keyboardVisible: Bool)
}

class DGKeyboardScrollHandler: NSObject, UITextFieldDelegate, UITextViewDelegate, UISearchBarDelegate
{
    // MARK: - Private variables
    
    private var lastOffsetBeforeKeyboardWasShown = CGPoint.zero
    private var scrollViewTapGestureRecognizer: UITapGestureRecognizer?
    private var scrollViewBottomInset: CGFloat = 0.0
    private var currentKeyboardInsetEveningMode: Int = 0 // For even show/hide notification tracking
    
    // MARK: - Public accessors
    
    //! @property delegate
    @IBOutlet weak var delegate: DGKeyboardScrollHandlerDelegate?
    
    /*! @property scrollView
     @brief This specifies the scrollView (or tableView) to scroll when the keyboard is showing.
     If your viewController contains a property named scrollView or tableView - it will be recognized automatically. */
    @IBOutlet weak var scrollView: UIScrollView? = nil
    {
        willSet
        {
            if scrollView != nil
            {
                if scrollViewTapGestureRecognizer != nil
                {
                    if let scrollViewTapGestureRecognizer = scrollViewTapGestureRecognizer
                    {
                        scrollView?.removeGestureRecognizer(scrollViewTapGestureRecognizer)
                    }
                }
            }
        }
        
        didSet
        {
            if scrollView != nil
            {
                if scrollViewTapGestureRecognizer == nil
                {
                    scrollViewTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(DGKeyboardScrollHandler.scrollViewTapGestureRecognized(_:)))
                    scrollViewTapGestureRecognizer?.numberOfTapsRequired = 1
                    scrollViewTapGestureRecognizer?.numberOfTouchesRequired = 1
                    scrollViewTapGestureRecognizer?.cancelsTouchesInView = false
                }
                
                if let scrollViewTapGestureRecognizer = scrollViewTapGestureRecognizer
                {
                    scrollView?.addGestureRecognizer(scrollViewTapGestureRecognizer)
                }
            }
        }
    }
    
    /*! @property viewController
     @brief Your viewController. We use this to automatically attach delegates and the scrollView,
     and to recognize interfaceOrientation and other stuff */
    @IBOutlet weak var viewController: UIViewController? = nil
    {
        didSet
        {
            // Try to detect scrollview
            if viewController?.responds(to: #selector(getter: scrollView)) ?? false
            {
                scrollView = (viewController)?.perform(#selector(getter: scrollView), with: nil)?.takeUnretainedValue() as? UIScrollView
            }
            else if viewController?.responds(to: #selector(getter: UITableViewController.tableView)) ?? false
            {
                scrollView = (viewController)?.perform(#selector(getter: UITableViewController.tableView), with: nil)?.takeUnretainedValue() as? UIScrollView
            }
            
            // Try to detect delegates
            if viewController is UITextFieldDelegate
            {
                textFieldDelegate = viewController as? UITextFieldDelegate
            }
            
            if viewController is UITextViewDelegate
            {
                textViewDelegate = viewController as? UITextViewDelegate
            }
            
            if viewController is UISearchBarDelegate
            {
                searchBarDelegate = viewController as? UISearchBarDelegate
            }
        }
    }
    
    /*! @property isKeyboardShowingForThisVC
     @brief A flag indicating whether the keyboard is known to be visible for the current view controller */
    @objc private(set) var isKeyboardShowingForThisVC = false
    
    /*! @property scrollToOriginalPositionAfterKeyboardHide
     @brief Set this to YES if you want to record the position of the scroll before the keyboard was shown,
     to return to that exact point regardless of where the user scrolled to.
     Default is NO */
    @objc var scrollToOriginalPositionAfterKeyboardHide = false
    
    /*! @property staticScrollOffset
     @brief Set this property if you need, for some reason, to add an arbitrary offset to the scroll when the keyboard is first showing.
     Default is {0, 0} */
    @objc var staticScrollOffset = CGPoint.zero
    
    /*! @property scrollOffsetBlock
     @brief Set this property if you need, for some reason, to calculate your own scroll offset to animate to when the keyboard is showing.
     Default is nil */
    @objc var scrollOffsetBlock: DGKeyboardScrollHandlerScrollAmountBlock?
    
    /*! @property suppressKeyboardEvents
     @brief Set this to YES if you want us to ignore keyboard showing/hiding events for a while.
     Default is NO */
    @objc var suppressKeyboardEvents = false
    /*! @property useEndEditingForDismiss
     @brief Set this to YES if you want us to try to force the current viewController's view to dismiss the keyboard,
     regardless of whether we know the current first responder or whether it wants to do so or not.
     Default is YES */
    @objc var useEndEditingForDismiss = false
    
    /*! @property doNotResignForButtons
     @brief Set this to YES if you want us to not resign the keyboard if tapped the scrollView on a UIButton
     Default is NO */
    @objc var doNotResignForButtons = false
    
    /*! @property doNotResignWhenTappingResponders
     @brief Set this to YES if you want us to not resign the keyboard if tapped the scrollView a UIResponder (i.e. a UITextField)
     Default is YES */
    @objc var doNotResignWhenTappingResponders = false
    
    /*! @property currentFirstResponder
     @brief The currently recognized firstResponder */
    @objc private(set) weak var currentFirstResponder: AnyObject?
    
    /*! @property textFieldDelegate
     @brief A delegate forwarded from all UITextFields in which we have set ourselves as delegate */
    @objc weak var textFieldDelegate: UITextFieldDelegate?
    
    /*! @property textViewDelegate
     @brief A delegate forwarded from all UITextViews in which we have set ourselves as delegate */
    @objc weak var textViewDelegate: UITextViewDelegate?
    
    /*! @property searchBarDelegate
     @brief A delegate forwarded from all UISearchBars in which we have set ourselves as delegate */
    @objc weak var searchBarDelegate: UISearchBarDelegate?
    
    // MARK: - Constructors
    
    override init()
    {
        super.init()
        
        doNotResignWhenTappingResponders = true
        useEndEditingForDismiss = true
    }
    
    deinit
    {
        let nc = NotificationCenter.default
        
        nc.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        nc.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    /*! Init the DGKeyboardScrollHandler with a viewController to handle...
     @param viewController Your viewController. We use this to automatically attach delegates and the scrollView,
     and to recognize interfaceOrientation and other stuff */
    convenience init(for viewController: UIViewController?)
    {
        self.init()
        
        defer // let it call setters
        {
            self.viewController = viewController
        }
    }
    
    /*! Init the DGKeyboardScrollHandler with a viewController to handle...
     @param viewController Your viewController. We use this to automatically attach delegates and the scrollView,
     and to recognize interfaceOrientation and other stuff */
    @objc convenience init(forViewController viewController: UIViewController?)
    {
        self.init()
        
        defer // let it call setters
        {
            self.viewController = viewController
        }
    }
    
    // MARK: - Public methods
    
    /*! This will traverse the scrollView and find all UITextFields and UITextViews, and set their delegate.
     Note that inside a UITableView this method is faulty, as cells are added and removed as you scroll. So set the delegate manually. */
    @objc func attachAllFieldDelegates()
    {
        attachAllFieldDelegates(from: scrollView)
    }
    
    private func attachAllFieldDelegates(from view: UIView?)
    {
        for subview in view?.subviews ?? []
        {
            if (subview is UITextField)
            {
                (subview as? UITextField)?.delegate = self
            }
            else if (subview is UITextView)
            {
                (subview as? UITextView)?.delegate = self
            }
            else if (subview is UISearchBar)
            {
                (subview as? UISearchBar)?.delegate = self
            }
            else
            {
                attachAllFieldDelegates(from: subview)
            }
        }
    }
    
    /*! This will try to resign the first responder, dismissing the keyboard.
     But will work only when we have a record of the current first responder, unless useEndEditingForDismiss is set to YES.
     You can also use the endEditing: of your UIView */
    @objc func dismissKeyboardIfPossible()
    {
        var resigned = false
        if useEndEditingForDismiss
        {
            if viewController != nil && viewController?.isViewLoaded == true
            {
                resigned = viewController?.view.endEditing(true) ?? false
            }
            
            if !resigned && scrollView != nil
            {
                resigned = scrollView?.endEditing(true) ?? false
            }
        }
        
        if !resigned && currentFirstResponder?.canResignFirstResponder ?? false
        {
            resigned = currentFirstResponder?.resignFirstResponder() ?? false
        }
        
        if resigned
        {
            currentFirstResponder = nil
        }
    }
    
    //! Please propogate this event from your UIViewController when you receive it, after calling super!
    @objc func viewDidAppear()
    {
        scrollView?.flashScrollIndicators()
        
        let dc = NotificationCenter.default
        
        dc.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        dc.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        
        dc.addObserver(self, selector: #selector(DGKeyboardScrollHandler.keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        dc.addObserver(self, selector: #selector(DGKeyboardScrollHandler.keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    //! Please propogate this event from your UIViewController when you receive it, after calling super!
    @objc func viewWillDisappear()
    {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        dismissKeyboardIfPossible()
    }
    
    //! Please propogate this event from your UIViewController when you receive it, after calling super!
    @objc func viewDidDisappear()
    {
        let dc = NotificationCenter.default
        dc.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    //! If you override touchesBegan, and want touches on your view to dismiss the keyboard, please forward the events to us too!
    @objc func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent)
    {
        if isKeyboardShowingForThisVC
        {
            dismissKeyboardIfPossible()
        }
    }
    
    /*! This you need to call when you *know* that a view has become the first responder,
     and that view is NOT a UITextField or a UITextView that is delegated to DGKeyboardScrollHandler
     @param firstResponder The view that became first responder */
    @objc func viewBecameFirstResponder(_ firstResponder: UIView?)
    {
        currentFirstResponder = firstResponder
        
        if isKeyboardShowingForThisVC
        {
            DGKeyboardScrollHandler.scroll(scrollView, rectToVisible: firstResponder?.superview?.convert(firstResponder?.frame ?? CGRect.zero, to: scrollView) ?? CGRect.zero, animated: true, checkForBug: true)
        }
        else
        {
            lastOffsetBeforeKeyboardWasShown = scrollView?.contentOffset ?? CGPoint.zero
        }
    }
    
    // MARK: - Actions
    
    @objc private func scrollViewTapGestureRecognized(_ recognizer: UIGestureRecognizer)
    {
        if let scrollView = scrollView,
            delegate?.responds(to: #selector(DGKeyboardScrollHandlerDelegate.keyboardScrollHandler(_:didRecognizeTapAt:on:withKeyboardVisible:))) == true
        {
            delegate?.keyboardScrollHandler?(
                self,
                didRecognizeTapAt: recognizer.location(in: recognizer.view),
                on: scrollView,
                withKeyboardVisible: isKeyboardShowingForThisVC)
        }
        
        if isKeyboardShowingForThisVC
        {
            if doNotResignWhenTappingResponders || doNotResignForButtons
            {
                let hitTest = scrollView?.hitTest(recognizer.location(in: scrollView), with: nil)
                if (doNotResignForButtons && (hitTest is UIButton)) || (doNotResignWhenTappingResponders && hitTest?.canBecomeFirstResponder ?? false)
                {
                    return
                }
            }
            
            dismissKeyboardIfPossible()
        }
    }
    
    // MARK: - UITextFieldDelegate Functions
    
    @objc func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool
    {
        if let scrollView = scrollView, textField.isDescendant(of: scrollView)
        {
            currentFirstResponder = textField
        }
        
        if textFieldDelegate?.responds(to: #selector(textFieldShouldBeginEditing(_:))) == true
        {
            return textFieldDelegate?.textFieldShouldBeginEditing?(textField) ?? true
        }
        return true
    }
    
    @objc func textFieldDidBeginEditing(_ textField: UITextField)
    {
        if let scrollView = scrollView, textField.isDescendant(of: scrollView)
        {
            currentFirstResponder = textField
        }
        
        if isKeyboardShowingForThisVC
        {
            DGKeyboardScrollHandler.scroll(scrollView, rectToVisible: textField.superview?.convert(textField.frame, to: scrollView) ?? CGRect.zero, animated: true, checkForBug: true)
        }
        else
        {
            lastOffsetBeforeKeyboardWasShown = scrollView?.contentOffset ?? CGPoint.zero
        }
        
        if textFieldDelegate?.responds(to: #selector(textFieldDidBeginEditing(_:))) == true
        {
            textFieldDelegate?.textFieldDidBeginEditing?(textField)
        }
    }
    
    @objc func textFieldDidEndEditing(_ textField: UITextField)
    {
        if let scrollView = scrollView, textField.isDescendant(of: scrollView)
        {
            currentFirstResponder = nil
        }
        
        if textFieldDelegate?.responds(to: #selector(textFieldDidEndEditing(_:))) == true
        {
            textFieldDelegate?.textFieldDidEndEditing?(textField)
        }
    }
    
    @objc func textFieldShouldReturn(_ textField: UITextField) -> Bool
    {
        textField.resignFirstResponder()
        
        if textFieldDelegate?.responds(to: #selector(textFieldShouldReturn(_:))) == true
        {
            return textFieldDelegate?.textFieldShouldReturn?(textField) ?? true
        }
        return true
    }
    
    @objc func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool
    {
        if textFieldDelegate?.responds(to: #selector(textField(_:shouldChangeCharactersIn:replacementString:)))  == true
        {
            return textFieldDelegate?.textField?(textField, shouldChangeCharactersIn: range, replacementString: string) ?? true
        }
        return true
    }
    
    @objc func textFieldShouldEndEditing(_ textField: UITextField) -> Bool
    {
        if textFieldDelegate?.responds(to: #selector(textFieldShouldEndEditing(_:))) == true
        {
            return textFieldDelegate?.textFieldShouldEndEditing?(textField) ?? true
        }
        return true
    }
    
    @objc func textFieldShouldClear(_ textField: UITextField) -> Bool
    {
        if textFieldDelegate?.responds(to: #selector(textFieldShouldClear(_:))) == true
        {
            return textFieldDelegate?.textFieldShouldClear?(textField) ?? true
        }
        return true
    }
    
    // MARK: - UITextViewDelegate
    @objc func textViewShouldBeginEditing(_ textView: UITextView) -> Bool
    {
        if let scrollView = scrollView, textView.isDescendant(of: scrollView)
        {
            currentFirstResponder = nil
        }
        
        if textViewDelegate?.responds(to: #selector(textViewShouldBeginEditing(_:))) == true
        {
            return textViewDelegate?.textViewShouldBeginEditing?(textView) ?? true
        }
        return true
    }
    
    @objc func textViewShouldEndEditing(_ textView: UITextView) -> Bool
    {
        if textViewDelegate?.responds(to: #selector(textViewShouldEndEditing(_:))) == true
        {
            return textViewDelegate?.textViewShouldEndEditing?(textView) ?? true
        }
        return true
    }
    
    @objc func textViewDidBeginEditing(_ textView: UITextView)
    {
        if let scrollView = scrollView, textView.isDescendant(of: scrollView)
        {
            currentFirstResponder = textView
        }
        
        if isKeyboardShowingForThisVC
        {
            DGKeyboardScrollHandler.scroll(scrollView, rectToVisible: textView.superview?.convert(textView.frame, to: scrollView) ?? CGRect.zero, animated: true, checkForBug: true)
        }
        else
        {
            lastOffsetBeforeKeyboardWasShown = scrollView?.contentOffset ?? CGPoint.zero
        }
        
        if textViewDelegate?.responds(to: #selector(textViewDidBeginEditing(_:))) == true
        {
            textViewDelegate?.textViewDidBeginEditing?(textView)
        }
    }
    
    @objc func textViewDidEndEditing(_ textView: UITextView)
    {
        if let scrollView = scrollView, textView.isDescendant(of: scrollView)
        {
            currentFirstResponder = nil
        }
        
        if textViewDelegate?.responds(to: #selector(textViewDidEndEditing(_:))) == true
        {
            textViewDelegate?.textViewDidEndEditing?(textView)
        }
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool
    {
        if textViewDelegate?.responds(to: #selector(textField(_:shouldChangeCharactersIn:replacementString:))) == true
        {
            return textViewDelegate?.textView?(textView, shouldChangeTextIn: range, replacementText: text) ?? true
        }
        return true
    }
    
    @objc func textViewDidChange(_ textView: UITextView)
    {
        if textViewDelegate?.responds(to: #selector(textViewDidChange(_:))) == true
        {
            textViewDelegate?.textViewDidChange?(textView)
        }
    }
    
    @objc func textViewDidChangeSelection(_ textView: UITextView)
    {
        if textViewDelegate?.responds(to: #selector(textViewDidChangeSelection(_:))) == true
        {
            textViewDelegate?.textViewDidChangeSelection?(textView)
        }
    }
    
    // MARK: - UISearchBarDelegate
    
    @objc func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool
    {
        if let scrollView = scrollView, searchBar.isDescendant(of: scrollView)
        {
            currentFirstResponder = searchBar
        }
        
        if searchBarDelegate?.responds(to: #selector(searchBarShouldBeginEditing(_:))) == true
        {
            return searchBarDelegate?.searchBarShouldBeginEditing?(searchBar) ?? true
        }
        return true
    }
    
    @objc func searchBarTextDidBeginEditing(_ searchBar: UISearchBar)
    {
        if let scrollView = scrollView, searchBar.isDescendant(of: scrollView)
        {
            currentFirstResponder = searchBar
        }
        
        if isKeyboardShowingForThisVC
        {
            DGKeyboardScrollHandler.scroll(scrollView, rectToVisible: searchBar.superview?.convert(searchBar.frame, to: scrollView) ?? CGRect.zero, animated: true, checkForBug: true)
        }
        else
        {
            lastOffsetBeforeKeyboardWasShown = scrollView?.contentOffset ?? CGPoint.zero
        }
        
        if searchBarDelegate?.responds(to: #selector(searchBarTextDidBeginEditing(_:))) ?? true
        {
            searchBarDelegate?.searchBarTextDidBeginEditing?(searchBar)
        }
    }
    
    @objc func searchBarTextDidEndEditing(_ searchBar: UISearchBar)
    {
        if let scrollView = scrollView, searchBar.isDescendant(of: scrollView)
        {
            currentFirstResponder = nil
        }
        
        if searchBarDelegate?.responds(to: #selector(searchBarTextDidEndEditing(_:))) == true
        {
            searchBarDelegate?.searchBarTextDidEndEditing?(searchBar)
        }
    }
    
    @objc func searchBar(_ searchBar: UISearchBar, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool
    {
        if searchBarDelegate?.responds(to: #selector(searchBar(_:shouldChangeTextIn:replacementText:))) == true
        {
            return searchBarDelegate?.searchBar?(searchBar, shouldChangeTextIn: range, replacementText: text) ?? true
        }
        return true
    }
    
    @objc func searchBarShouldEndEditing(_ searchBar: UISearchBar) -> Bool
    {
        if searchBarDelegate?.responds(to: #selector(searchBarShouldEndEditing(_:))) == true
        {
            return searchBarDelegate?.searchBarShouldEndEditing?(searchBar) ?? true
        }
        return true
    }
    
    @objc func searchBarSearchButtonClicked(_ searchBar: UISearchBar)
    {
        if searchBarDelegate?.responds(to: #selector(searchBarSearchButtonClicked(_:))) == true
        {
            searchBarDelegate?.searchBarSearchButtonClicked?(searchBar)
        }
    }
    
    @objc func searchBarBookmarkButtonClicked(_ searchBar: UISearchBar)
    {
        if searchBarDelegate?.responds(to: #selector(searchBarBookmarkButtonClicked(_:))) == true
        {
            searchBarDelegate?.searchBarBookmarkButtonClicked?(searchBar)
        }
    }
    
    @objc func searchBarCancelButtonClicked(_ searchBar: UISearchBar)
    {
        if searchBarDelegate?.responds(to: #selector(searchBarCancelButtonClicked(_:))) == true
        {
            searchBarDelegate?.searchBarCancelButtonClicked?(searchBar)
        }
    }
    
    @objc func searchBarResultsListButtonClicked(_ searchBar: UISearchBar)
    {
        if searchBarDelegate?.responds(to: #selector(searchBarResultsListButtonClicked(_:))) == true
        {
            searchBarDelegate?.searchBarResultsListButtonClicked?(searchBar)
        }
    }
    
    @objc func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String)
    {
        if searchBarDelegate?.responds(to: #selector(searchBar(_:textDidChange:))) == true
        {
            searchBarDelegate?.searchBar?(searchBar, textDidChange: searchText)
        }
    }
    
    @objc func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int)
    {
        if searchBarDelegate?.responds(to: #selector(searchBar(_:selectedScopeButtonIndexDidChange:))) == true
        {
            searchBarDelegate?.searchBar?(searchBar, selectedScopeButtonIndexDidChange: selectedScope)
        }
    }
    
    // MARK: - Keyboard Management
    
    private func detectIfKeyboardEventBelongsToUs() -> Bool
    {
        return (viewController == nil
            || (
                (viewController?
                    .navigationController?.topViewController == viewController
                    || viewController?
                        .navigationController?.presentedViewController == viewController
                    || viewController?
                        .navigationController == nil
                    )
                    && viewController?.isViewLoaded == true
                    && viewController?.view.window != nil
            )
            ) && !suppressKeyboardEvents
    }
    
    @objc private func keyboardWillShow(_ notification: Notification?)
    {
        if detectIfKeyboardEventBelongsToUs()
        {
            isKeyboardShowingForThisVC = true
            
            let userInfo = notification?.userInfo
            
            let keyboardFrame: CGRect = DGKeyboardScrollHandler.keyboardFrame(fromUserInfo: userInfo)
            
            let intersection: CGRect = DGKeyboardScrollHandler.keyboardFrame(fromUserInfo: userInfo, intersectedWith: scrollView)
            
            let bottomInset: CGFloat = intersection.size.height
            
            let animOptions: UIView.AnimationOptions = DGKeyboardScrollHandler.keyboardAnimationOptions(fromUserInfo: userInfo)
            
            scrollViewBottomInset = bottomInset
            UIView.animate(withDuration: TimeInterval((userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.0), delay: 0, options: animOptions, animations: {
                if self.currentKeyboardInsetEveningMode == 0
                {
                    var insets = self.scrollView?.contentInset ?? .zero
                    insets.bottom += self.scrollViewBottomInset
                    self.scrollView?.contentInset = insets
                    
                    self.currentKeyboardInsetEveningMode += 1
                }
            }) { finished in
                if self.scrollOffsetBlock != nil
                {
                    var offset = CGPoint.zero
                    
                    if let scrollView = self.scrollView
                    {
                        offset = self.scrollOffsetBlock?(scrollView, keyboardFrame) ?? offset
                    }
                    
                    UIView.animate(withDuration: 0.15, delay: 0.0, options: .curveEaseIn, animations: {
                        
                        self.scrollView?.contentOffset = offset
                        
                    }, completion: { finished in
                        
                    })
                }
                else if self.staticScrollOffset.y != 0.0
                {
                    UIView.animate(withDuration: 0.15, delay: 0.0, options: .curveEaseIn, animations: {
                        
                        self.scrollView?.contentOffset = CGPoint(x: self.scrollView?.contentOffset.x ?? 0.0, y: self.staticScrollOffset.y)
                        
                    }, completion: { finished in
                        
                    })
                }
                else
                {
                    let targetRect = ((self.currentFirstResponder as? UIView)?.superview)?.convert((self.currentFirstResponder as? UIView)?.frame ?? CGRect.zero, to: self.scrollView)
                    
                    DGKeyboardScrollHandler.scroll(self.scrollView, rectToVisible: targetRect ?? CGRect.zero, animated: true, checkForBug: true)
                }
            }
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification?)
    {
        if detectIfKeyboardEventBelongsToUs()
        {
            isKeyboardShowingForThisVC = false
            
            let userInfo = notification?.userInfo
            
            let animOptions: UIView.AnimationOptions = DGKeyboardScrollHandler.keyboardAnimationOptions(fromUserInfo: userInfo)
            
            UIView.animate(withDuration: TimeInterval((userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.0), delay: 0, options: animOptions, animations: {
                    
                if self.currentKeyboardInsetEveningMode == 1
                {
                    var insets = self.scrollView?.contentInset ?? .zero
                    insets.bottom -= self.scrollViewBottomInset
                    self.scrollView?.contentInset = insets
                    
                    self.currentKeyboardInsetEveningMode -= 1
                }
            }) { finished in
                if self.scrollToOriginalPositionAfterKeyboardHide
                {
                    self.scrollView?
                        .setContentOffset(self.lastOffsetBeforeKeyboardWasShown, animated: true)
                }
            }
        }
    }
    
    // MARK: - Utility
    
    //! This calculates the bottom-most position inside a scroll view, if you need to dynamically calculate the contentSize of a scrollView
    @objc func calculatedContentHeightForCurrentScrollView() -> CGFloat
    {
        return DGKeyboardScrollHandler.calculatedContentHeight(for: scrollView)
    }
    
    /*! This calculates the bottom-most position inside a scroll view, if you need to dynamically calculate the contentSize of a scrollView
     @param scrollView The scrollView to calculate for */
    @objc class func calculatedContentHeight(for scrollView: UIScrollView?) -> CGFloat
    {
        var maxY: CGFloat = 0.0
        var y: CGFloat
        
        for subview in scrollView?.subviews ?? []
        {
            y = subview.frame.maxY
            if y > maxY
            {
                maxY = y
            }
        }
        
        return maxY
    }
    
    private class func isScrollToRectBuggy(on scrollView: UIScrollView?) -> Bool
    {
        let bounds: CGRect? = scrollView?.bounds
        let contentSize: CGSize? = scrollView?.contentSize
        
        return (contentSize?.height ?? 0.0) < (bounds?.size.height ?? 0.0) || (contentSize?.width ?? 0.0) < (bounds?.size.width ?? 0.0)
    }
    
    
    @objc class func scroll(_ scrollView: UIScrollView?, rectToVisible rect: CGRect, animated: Bool, checkForBug ifBuggy: Bool)
    {
        if let scrollView = scrollView,
            !ifBuggy || self.isScrollToRectBuggy(on: scrollView)
        {
            self.scroll(scrollView, rectToVisible: rect, animated: animated)
        }
        else
        {
            scrollView?.scrollRectToVisible(rect, animated: animated)
        }
    }
    
    @objc class func scroll(_ scrollView: UIScrollView, rectToVisible rect: CGRect, animated: Bool)
    {
        let scrollInsets = scrollView.contentInset
        let scrollSize = scrollView.contentSize
        let scrollBounds = scrollView.bounds
        
        var scrollInsetBounds = scrollBounds
        scrollInsetBounds.origin.x += scrollInsets.left
        scrollInsetBounds.origin.y += scrollInsets.top
        scrollInsetBounds.size.width -= scrollInsets.left + scrollInsets.right
        scrollInsetBounds.size.height -= scrollInsets.top + scrollInsets.bottom
        
        var visibleRect = scrollInsetBounds
        visibleRect.origin.x += scrollView.contentOffset.x
        visibleRect.origin.y += scrollView.contentOffset.y
        
        if !visibleRect.contains(rect)
        {
            var offset = scrollView.contentOffset
            
            if rect.size.width > visibleRect.size.width
            {
                offset.x -= visibleRect.minX - rect.minX - (rect.size.width - visibleRect.size.width) / 2.0
            }
            else if rect.maxX > visibleRect.maxX
            {
                offset.x += rect.maxX - visibleRect.maxX
            }
            else if rect.minX < visibleRect.minX
            {
                offset.x -= visibleRect.minX - rect.minX
            }
            
            if rect.size.height > visibleRect.size.height
            {
                offset.y -= visibleRect.minY - rect.minY - (rect.size.height - visibleRect.size.height) / 2.0
            }
            else if rect.maxY > visibleRect.maxY
            {
                offset.y += rect.maxY - visibleRect.maxY
            }
            else if rect.minY < visibleRect.minY
            {
                offset.y -= visibleRect.minY - rect.minY
            }
            
            offset.x = CGFloat(fmax(fmin(Float(offset.x), Float(scrollSize.width - scrollInsetBounds.size.width)), 0.0))
            offset.y = CGFloat(fmax(fmin(Float(offset.y), Float(scrollSize.height - scrollInsetBounds.size.height)), 0.0))
            
            if animated
            {
                scrollView.setContentOffset(offset, animated: 0.15 != 0)
            }
            else
            {
                scrollView.contentOffset = offset
            }
        }
    }
    
    /*! This calculates the keyboard's frame from the user info, and rotates it based on the device's orientation
     @param userInfo The `userInfo` member of an `NSNotification` */
    @objc class func keyboardFrame(fromUserInfo userInfo: [AnyHashable : Any]?) -> CGRect
    {
        return self.keyboardFrame(fromUserInfo: userInfo, intersectedWith: nil)
    }
    
    /*! This calculates the keyboard's frame from the user info, and rotates it based on the device's orientation, and intersecting with the supplied view
     @param userInfo The `userInfo` member of an `NSNotification`
     @param view The `UIView` to intersect with */
    @objc class func keyboardFrame(fromUserInfo userInfo: [AnyHashable : Any]?, intersectedWith view: UIView?) -> CGRect
    {
        let keyboardFrameValue = userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        var keyboardFrame = keyboardFrameValue?.cgRectValue ?? .zero
        
        let needsSwap: Bool = UIDevice.current.orientation == .landscapeLeft || UIDevice.current.orientation == .landscapeRight
        
        if needsSwap
        {
            keyboardFrame = CGRect(
                x: keyboardFrame.origin.y,
                y: keyboardFrame.origin.x,
                width: keyboardFrame.size.height,
                height: keyboardFrame.size.width)
        }
        
        if let view = view
        {
            var viewRectAbsolute = view.convert(view.bounds, to: UIApplication.shared.keyWindow)
        
            if needsSwap
            {
                viewRectAbsolute = CGRect(
                    x: viewRectAbsolute.origin.y,
                    y: viewRectAbsolute.origin.x,
                    width: viewRectAbsolute.size.height,
                    height: viewRectAbsolute.size.width)
            }
            
            keyboardFrame = keyboardFrame.intersection(viewRectAbsolute)
        }
        
        return keyboardFrame
    }
    
    /*! This calculates the `UIViewAnimationOptions` from the `userInfo` supplied in the `NSNotification`
     @param userInfo The `userInfo` member of an NSNotification */
    @objc class func keyboardAnimationOptions(fromUserInfo userInfo: [AnyHashable : Any]?) -> UIView.AnimationOptions
    {
        var animOptions: UIView.AnimationOptions = []
        
        if let curve = userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UIView.AnimationCurve
        {
            switch (curve)
            {
            case .easeIn:
                animOptions = [.curveEaseIn]
            case .easeOut:
                animOptions = [.curveEaseOut]
            case .easeInOut:
                animOptions = [.curveEaseInOut]
            case .linear:
                animOptions = [.curveLinear]
            default:
                break
            }
        }
        
        return animOptions
    }
}
