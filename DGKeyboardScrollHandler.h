//
//  DGKeyboardScrollHandler.h
//  DGKeyboardScrollHandler
//
//  Created by Daniel Cohen Gindi on 6/15/13.
//  Copyright (c) 2013 danielgindi@gmail.com. All rights reserved.
//
//  https://github.com/danielgindi/DGKeyboardScrollHandler
//
//  To use this class, just make an instance of it (you can do this in code or in Interface Builder)
//  And attach the viewController to it in the property or in the initializer.
//  Then if possible - attach it to the delegate for your UITextFields and UITextViews (you can draw a delegate from the DGKeyboardScrollHandler as well, if needed)
//  And then forward any viewDidAppear/viewWillDisappear/viewDidDisappear events from your viewController.
//
//  The MIT License (MIT)
//  
//  Copyright (c) 2014 Daniel Cohen Gindi (danielgindi@gmail.com)
//  
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//  
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//  
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE. 
//  

#import <UIKit/UIKit.h>

typedef CGPoint (^DGKeyboardScrollHandlerScrollAmountBlock)(UIScrollView *scrollView, CGRect keyboardFrame);

@interface DGKeyboardScrollHandler : NSObject <UITextFieldDelegate, UITextViewDelegate, UISearchBarDelegate>

/*! @property scrollView
    @brief This specifies the scrollView (or tableView) to scroll when the keyboard is showing.
           If your viewController contains a property named scrollView or tableView - it will be recognized automatically. */
@property (nonatomic, weak) IBOutlet UIScrollView *scrollView;

/*! @property viewController
    @brief Your viewController. We use this to automatically attach delegates and the scrollView,
           and to recognize interfaceOrientation and other stuff */
@property (nonatomic, weak) IBOutlet UIViewController *viewController;

/*! @property scrollToOriginalPositionAfterKeyboardHide
    @brief Set this to YES if you want to record the position of the scroll before the keyboard was shown, 
          to return to that exact point regardless of where the user scrolled to. 
          Default is NO */
@property (nonatomic, assign) BOOL scrollToOriginalPositionAfterKeyboardHide;

/*! @property staticScrollOffset
 @brief Set this property if you need, for some reason, to add an arbitrary offset to the scroll when the keyboard is first showing.
 Default is {0, 0} */
@property (nonatomic, assign) CGPoint staticScrollOffset;

/*! @property scrollOffsetBlock
 @brief Set this property if you need, for some reason, to calculate your own scroll offset to animate to when the keyboard is showing.
 Default is nil */
@property (nonatomic, copy) DGKeyboardScrollHandlerScrollAmountBlock scrollOffsetBlock;

/*! @property suppressKeyboardEvents
    @brief Set this to YES if you want us to ignore keyboard showing/hiding events for a while.
           Default is NO */
@property (nonatomic, assign) BOOL suppressKeyboardEvents;

/*! @property useEndEditingForDismiss
    @brief Set this to YES if you want us to try to force the current viewController's view to dismiss the keyboard,
           regardless of whether we know the current first responder or whether it wants to do so or not.
           Default is YES */
@property (nonatomic, assign) BOOL useEndEditingForDismiss;

/*! @property doNotResignForButtons
    @brief Set this to YES if you want us to not resign the keyboard if tapped the scrollView on a UIButton
           Default is NO */
@property (nonatomic, assign) BOOL doNotResignForButtons;

/*! @property doNotResignWhenTappingResponders
    @brief Set this to YES if you want us to not resign the keyboard if tapped the scrollView a UIResponder (i.e. a UITextField)
           Default is YES */
@property (nonatomic, assign) BOOL doNotResignWhenTappingResponders;

/*! @property currentFirstResponder
    @brief The currently recognized firstResponder */
@property (nonatomic, weak, readonly) id currentFirstResponder;

/*! @property textFieldDelegate
    @brief A delegate forwarded from all UITextFields in which we have set ourselves as delegate */
@property (nonatomic, weak) id<UITextFieldDelegate> textFieldDelegate;

/*! @property textViewDelegate
    @brief A delegate forwarded from all UITextViews in which we have set ourselves as delegate */
@property (nonatomic, weak) id<UITextViewDelegate> textViewDelegate;

/*! @property searchBarDelegate
 @brief A delegate forwarded from all UISearchBars in which we have set ourselves as delegate */
@property (nonatomic, weak) id<UISearchBarDelegate> searchBarDelegate;

/*! Init the DGKeyboardScrollHandler with a viewController to handle...
    @param viewController Your viewController. We use this to automatically attach delegates and the scrollView,
                          and to recognize interfaceOrientation and other stuff */
- (id)initForViewController:(UIViewController *)viewController;

/*! Convenience initializer
    @param viewController Your viewController. We use this to automatically attach delegates and the scrollView, 
                          and to recognize interfaceOrientation and other stuff */
+ (id)keyboardScrollHandlerForViewController:(UIViewController *)viewController;

/*! This will traverse the scrollView and find all UITextFields and UITextViews, and set their delegate.
    Note that inside a UITableView this method is faulty, as cells are added and removed as you scroll. So set the delegate manually. */
- (void)attachAllFieldDelegates;

/*! This will try to resign the first responder, dismissing the keyboard. 
    But will work only when we have a record of the current first responder, unless useEndEditingForDismiss is set to YES.
    You can also use the endEditing: of your UIView */
- (void)dismissKeyboardIfPossible;

/*! Please propogate this event from your UIViewController when you receive it, after calling super! */
- (void)viewDidAppear;

/*! Please propogate this event from your UIViewController when you receive it, after calling super! */
- (void)viewWillDisappear;

/*! Please propogate this event from your UIViewController when you receive it, after calling super! */
- (void)viewDidDisappear;

/*! If you override touchesBegan, and want touches on your view to dismiss the keyboard, please forward the events to us too! */
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;

/*! This you need to call when you *know* that a view has become the first responder, 
    and that view is NOT a UITextField or a UITextView that is delegated to DGKeyboardScrollHandler 
    @param firstResponder The view that became first responder */
- (void)viewBecameFirstResponder:(UIView *)firstResponder;

@end
