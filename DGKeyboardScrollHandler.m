//
//  DGKeyboardScrollHandler.m
//  DGKeyboardScrollHandler
//
//  Created by Daniel Cohen Gindi on 6/15/13.
//  Copyright (c) 2013 danielgindi@gmail.com. All rights reserved.
//
//  https://github.com/danielgindi/DGKeyboardScrollHandler
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

#import "DGKeyboardScrollHandler.h"

@interface DGKeyboardScrollHandler ()
{
    BOOL _isKeyboardShowingForThisVC;
    CGPoint _lastOffsetBeforeKeyboardWasShown;
    UITapGestureRecognizer *scrollViewTapGestureRecognizer;
    CGFloat _scrollViewBottomInset;
    int _currentKeyboardInsetEveningMode; // For even show/hide notification tracking
}

@property (nonatomic, weak) id currentFirstResponder;

@end

@implementation DGKeyboardScrollHandler

- (id)init
{
    self = [super init];
    if (self)
    {
        _doNotResignWhenTappingResponders = YES;
        _useEndEditingForDismiss = YES;
    }
    return self;
}

- (void)dealloc
{
	NSNotificationCenter *dc = [NSNotificationCenter defaultCenter];
    
	[dc removeObserver:self name:UIKeyboardWillShowNotification object:nil];
	[dc removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

- (id)initForViewController:(UIViewController *)viewController
{
    self = [self init];
    if (self)
    {
        self.viewController = viewController;
    }
    return self;
}

+ (id)keyboardScrollHandlerForViewController:(UIViewController *)viewController
{
    return [[DGKeyboardScrollHandler alloc] initForViewController:viewController];
}

- (void)viewDidAppear
{
	[_scrollView flashScrollIndicators];
    
	NSNotificationCenter *dc = [NSNotificationCenter defaultCenter];
    
	[dc removeObserver:self name:UIKeyboardWillShowNotification object:nil];
	[dc removeObserver:self name:UIKeyboardWillHideNotification object:nil];
    
	[dc addObserver:self
           selector:@selector(keyboardWillShow:)
               name:UIKeyboardWillShowNotification
             object:nil];
	[dc addObserver:self
           selector:@selector(keyboardWillHide:)
               name:UIKeyboardWillHideNotification
             object:nil];
}

- (void)viewWillDisappear
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
	[self dismissKeyboardIfPossible];
}

- (void)viewDidDisappear
{
	NSNotificationCenter *dc = [NSNotificationCenter defaultCenter];
	[dc removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

- (void)setViewController:(UIViewController *)viewController
{
	_viewController = viewController;
        
        // Try to detect scrollview
        if ([viewController respondsToSelector:@selector(scrollView)])
        {
            self.scrollView = [((id)viewController) performSelector:@selector(scrollView) withObject:nil];
        }
        else if ([viewController respondsToSelector:@selector(tableView)])
        {
            self.scrollView = [((id)viewController) performSelector:@selector(tableView) withObject:nil];
        }
        
        // Try to detect delegates
        if ([viewController conformsToProtocol:@protocol(UITextFieldDelegate)])
        {
            self.textFieldDelegate = (id<UITextFieldDelegate>)viewController;
        }
        if ([viewController conformsToProtocol:@protocol(UITextViewDelegate)])
        {
            self.textViewDelegate = (id<UITextViewDelegate>)viewController;
        }
        if ([viewController conformsToProtocol:@protocol(UISearchBarDelegate)])
        {
            self.searchBarDelegate = (id<UISearchBarDelegate>)viewController;
        }
}

- (void)attachAllFieldDelegates
{
    [self attachAllFieldDelegatesFromView:self.scrollView];
}

- (void)attachAllFieldDelegatesFromView:(UIView *)view
{
    for (UIView *subview in view.subviews)
    {
        if ([subview isKindOfClass:[UITextField class]])
        {
            ((UITextField *)subview).delegate = self;
        }
        else if ([subview isKindOfClass:[UITextView class]])
        {
            ((UITextView *)subview).delegate = self;
        }
        else if ([subview isKindOfClass:[UISearchBar class]])
        {
            ((UISearchBar *)subview).delegate = self;
        }
        else
        {
            [self attachAllFieldDelegatesFromView:subview];
        }
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    if (_isKeyboardShowingForThisVC)
    {
        [self dismissKeyboardIfPossible];
    }
}

- (void)setScrollView:(UIScrollView *)scrollView
{
    if (_scrollView)
    {
        if (scrollViewTapGestureRecognizer)
        {
            [_scrollView removeGestureRecognizer:scrollViewTapGestureRecognizer];
        }
    }
    _scrollView = scrollView;
    if (_scrollView)
    {
        if (!scrollViewTapGestureRecognizer)
        {
            scrollViewTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(scrollViewTapGestureRecognized:)];
            scrollViewTapGestureRecognizer.numberOfTapsRequired = 1;
            scrollViewTapGestureRecognizer.numberOfTouchesRequired = 1;
            scrollViewTapGestureRecognizer.cancelsTouchesInView = NO;
        }
        [_scrollView addGestureRecognizer:scrollViewTapGestureRecognizer];
    }
}

#pragma mark - Actions

- (void)scrollViewTapGestureRecognized:(UIGestureRecognizer *)recognizer
{
    if (_isKeyboardShowingForThisVC)
    {
        if (_doNotResignWhenTappingResponders || _doNotResignForButtons)
        {
            UIView *hitTest = [_scrollView hitTest:[recognizer locationInView:_scrollView] withEvent:nil];
            if ((_doNotResignForButtons && [hitTest isKindOfClass:UIButton.class]) || 
            	(_doNotResignWhenTappingResponders && [hitTest canBecomeFirstResponder]))
            {
                return;
            }
        }
        [self dismissKeyboardIfPossible];
    }
}

- (void)viewBecameFirstResponder:(UIView *)firstResponder
{
	self.currentFirstResponder = firstResponder;
    if (_isKeyboardShowingForThisVC)
    {
        [_scrollView scrollRectToVisible:[firstResponder.superview convertRect:firstResponder.frame toView:_scrollView] animated:YES];
    }
    else
    {
        _lastOffsetBeforeKeyboardWasShown = _scrollView.contentOffset;
    }
}

#pragma mark - UITextFieldDelegate Functions

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
    if ([textField isDescendantOfView:self.scrollView])
    {
        self.currentFirstResponder = textField;
    }
    
    if ([_textFieldDelegate respondsToSelector:@selector(textFieldShouldBeginEditing:)])
    {
        return [_textFieldDelegate textFieldShouldBeginEditing:textField];
    }
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    if ([textField isDescendantOfView:self.scrollView])
    {
        self.currentFirstResponder = textField;
    }
    if (_isKeyboardShowingForThisVC)
    {
        [_scrollView scrollRectToVisible:[textField.superview convertRect:textField.frame toView:_scrollView] animated:YES];
    }
    else
    {
        _lastOffsetBeforeKeyboardWasShown = _scrollView.contentOffset;
    }
    if ([_textFieldDelegate respondsToSelector:@selector(textFieldDidBeginEditing:)])
    {
        [_textFieldDelegate textFieldDidBeginEditing:textField];
    }
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    if ([textField isDescendantOfView:self.scrollView])
    {
        self.currentFirstResponder = nil;
    }
    if ([_textFieldDelegate respondsToSelector:@selector(textFieldDidEndEditing:)])
    {
        [_textFieldDelegate textFieldDidEndEditing:textField];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    if ([_textFieldDelegate respondsToSelector:@selector(textFieldShouldReturn:)])
    {
        return [_textFieldDelegate textFieldShouldReturn:textField];
    }
	return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    if ([_textFieldDelegate respondsToSelector:@selector(textField:shouldChangeCharactersInRange:replacementString:)])
    {
        return [_textFieldDelegate textField:textField shouldChangeCharactersInRange:range replacementString:string];
    }
    return YES;
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField
{
    if ([_textFieldDelegate respondsToSelector:@selector(textFieldShouldEndEditing:)])
    {
        return [_textFieldDelegate textFieldShouldEndEditing:textField];
    }
    return YES;
}

- (BOOL)textFieldShouldClear:(UITextField *)textField
{
    if ([_textFieldDelegate respondsToSelector:@selector(textFieldShouldClear:)])
    {
        return [_textFieldDelegate textFieldShouldClear:textField];
    }
    return YES;
}

#pragma mark - UITextViewDelegate

- (BOOL)textViewShouldBeginEditing:(UITextView *)textView
{
    if ([textView isDescendantOfView:self.scrollView])
    {
        self.currentFirstResponder = nil;
    }
    if ([_textViewDelegate respondsToSelector:@selector(textViewShouldBeginEditing:)])
    {
        return [_textViewDelegate textViewShouldBeginEditing:textView];
    }
    return YES;
}

- (BOOL)textViewShouldEndEditing:(UITextView *)textView
{
    if ([_textViewDelegate respondsToSelector:@selector(textViewShouldEndEditing:)])
    {
        return [_textViewDelegate textViewShouldEndEditing:textView];
    }
    return YES;
}

- (void)textViewDidBeginEditing:(UITextView *)textView
{
    if ([textView isDescendantOfView:self.scrollView])
    {
        self.currentFirstResponder = textView;
    }
    if (_isKeyboardShowingForThisVC)
    {
        [_scrollView scrollRectToVisible:[textView.superview convertRect:textView.frame toView:_scrollView] animated:YES];
    }
    else
    {
        _lastOffsetBeforeKeyboardWasShown = _scrollView.contentOffset;
    }
    if ([_textViewDelegate respondsToSelector:@selector(textViewDidBeginEditing:)])
    {
        [_textViewDelegate textViewDidBeginEditing:textView];
    }
}

- (void)textViewDidEndEditing:(UITextView *)textView
{
    if ([textView isDescendantOfView:self.scrollView])
    {
        self.currentFirstResponder = nil;
    }
    if ([_textViewDelegate respondsToSelector:@selector(textViewDidEndEditing:)])
    {
        [_textViewDelegate textViewDidEndEditing:textView];
    }
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if ([_textViewDelegate respondsToSelector:@selector(textField:shouldChangeCharactersInRange:replacementString:)])
    {
        return [_textViewDelegate textView:textView shouldChangeTextInRange:range replacementText:text];
    }
    return YES;
}

- (void)textViewDidChange:(UITextView *)textView
{
    if ([_textViewDelegate respondsToSelector:@selector(textViewDidChange:)])
    {
        [_textViewDelegate textViewDidChange:textView];
    }
}

- (void)textViewDidChangeSelection:(UITextView *)textView
{
    if ([_textViewDelegate respondsToSelector:@selector(textViewDidChangeSelection:)])
    {
        [_textViewDelegate textViewDidChangeSelection:textView];
    }
}

#pragma mark - UISearchBarDelegate

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar
{
    if ([searchBar isDescendantOfView:self.scrollView])
    {
        self.currentFirstResponder = searchBar;
    }
    
    if ([_searchBarDelegate respondsToSelector:@selector(searchBarShouldBeginEditing:)])
    {
        return [_searchBarDelegate searchBarShouldBeginEditing:searchBar];
    }
    return YES;
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar
{
    if ([searchBar isDescendantOfView:self.scrollView])
    {
        self.currentFirstResponder = searchBar;
    }
    if (_isKeyboardShowingForThisVC)
    {
        [_scrollView scrollRectToVisible:[searchBar.superview convertRect:searchBar.frame toView:_scrollView] animated:YES];
    }
    else
    {
        _lastOffsetBeforeKeyboardWasShown = _scrollView.contentOffset;
    }
    if ([_searchBarDelegate respondsToSelector:@selector(searchBarTextDidBeginEditing:)])
    {
        [_searchBarDelegate searchBarTextDidBeginEditing:searchBar];
    }
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar
{
    if ([searchBar isDescendantOfView:self.scrollView])
    {
        self.currentFirstResponder = nil;
    }
    if ([_searchBarDelegate respondsToSelector:@selector(searchBarTextDidEndEditing:)])
    {
        [_searchBarDelegate searchBarTextDidEndEditing:searchBar];
    }
}

- (BOOL)searchBar:(UISearchBar *)searchBar shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if ([_searchBarDelegate respondsToSelector:@selector(searchBar:shouldChangeTextInRange:replacementText:)])
    {
        return [_searchBarDelegate searchBar:searchBar shouldChangeTextInRange:range replacementText:text];
    }
    return YES;
}

- (BOOL)searchBarShouldEndEditing:(UISearchBar *)searchBar
{
    if ([_searchBarDelegate respondsToSelector:@selector(searchBarShouldEndEditing:)])
    {
        return [_searchBarDelegate searchBarShouldEndEditing:searchBar];
    }
    return YES;
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    if ([_searchBarDelegate respondsToSelector:@selector(searchBarSearchButtonClicked:)])
    {
        return [_searchBarDelegate searchBarSearchButtonClicked:searchBar];
    }
}

- (void)searchBarBookmarkButtonClicked:(UISearchBar *)searchBar
{
    if ([_searchBarDelegate respondsToSelector:@selector(searchBarBookmarkButtonClicked:)])
    {
        return [_searchBarDelegate searchBarBookmarkButtonClicked:searchBar];
    }
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    if ([_searchBarDelegate respondsToSelector:@selector(searchBarCancelButtonClicked:)])
    {
        return [_searchBarDelegate searchBarCancelButtonClicked:searchBar];
    }
}

- (void)searchBarResultsListButtonClicked:(UISearchBar *)searchBar
{
    if ([_searchBarDelegate respondsToSelector:@selector(searchBarResultsListButtonClicked:)])
    {
        return [_searchBarDelegate searchBarResultsListButtonClicked:searchBar];
    }
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    if ([_searchBarDelegate respondsToSelector:@selector(searchBar:textDidChange:)])
    {
        return [_searchBarDelegate searchBar:searchBar textDidChange:searchText];
    }
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope
{
    if ([_searchBarDelegate respondsToSelector:@selector(searchBar:selectedScopeButtonIndexDidChange:)])
    {
        return [_searchBarDelegate searchBar:searchBar selectedScopeButtonIndexDidChange:selectedScope];
    }
}

#pragma mark - Keyboard Management

- (void)keyboardWillShow:(NSNotification *)notification
{
	/*if (self.viewController.navigationController.topViewController == self ||
     (!self.viewController.navigationController && !self.modalViewController))*/
	if ((!self.viewController || ((self.viewController.navigationController.topViewController == self.viewController || self.viewController.navigationController.presentedViewController == self.viewController || self.viewController.navigationController == nil) &&
        self.viewController.isViewLoaded && self.viewController.view.window)) && !_suppressKeyboardEvents)
    {
        _isKeyboardShowingForThisVC = YES;
        
		NSDictionary *userInfo = [notification userInfo];
        
		NSValue *keyboardFrameValue = userInfo[UIKeyboardFrameEndUserInfoKey];
        CGRect keyboardFrame = [keyboardFrameValue CGRectValue];
		if (UIInterfaceOrientationLandscapeLeft == self.viewController.interfaceOrientation || UIInterfaceOrientationLandscapeRight == self.viewController.interfaceOrientation)
        {
            CGRect swappedRect;
            swappedRect.origin.x = keyboardFrame.origin.y;
            swappedRect.origin.y = keyboardFrame.origin.x;
            swappedRect.size.width = keyboardFrame.size.height;
            swappedRect.size.height = keyboardFrame.size.width;
            keyboardFrame = swappedRect;
		}
		
		// Reduce the scrollView height by the part of the keyboard that actually covers the scrollView
		CGRect windowRect = [[UIApplication sharedApplication] keyWindow].bounds;
		if (UIInterfaceOrientationLandscapeLeft == self.viewController.interfaceOrientation || UIInterfaceOrientationLandscapeRight == self.viewController.interfaceOrientation)
        {
            CGRect swappedRect;
            swappedRect.origin.x = windowRect.origin.y;
            swappedRect.origin.y = windowRect.origin.x;
            swappedRect.size.width = windowRect.size.height;
            swappedRect.size.height = windowRect.size.width;
            windowRect = swappedRect;
		}
		CGRect viewRectAbsolute = [_scrollView convertRect:_scrollView.bounds toView:[[UIApplication sharedApplication] keyWindow]];
		if (UIInterfaceOrientationLandscapeLeft == self.viewController.interfaceOrientation || UIInterfaceOrientationLandscapeRight == self.viewController.interfaceOrientation)
        {
			CGRect swappedRect;
            swappedRect.origin.x = viewRectAbsolute.origin.y;
            swappedRect.origin.y = viewRectAbsolute.origin.x;
            swappedRect.size.width = viewRectAbsolute.size.height;
            swappedRect.size.height = viewRectAbsolute.size.width;
            viewRectAbsolute = swappedRect;
		}
        
        CGFloat bottomInset = keyboardFrame.size.height - CGRectGetMaxY(windowRect) + CGRectGetMaxY(viewRectAbsolute);
        
        UIViewAnimationOptions animOptions = 0;
        switch ([[userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue])
        {
            case UIViewAnimationCurveEaseIn:
                animOptions = UIViewAnimationOptionCurveEaseIn;
                break;
            case UIViewAnimationCurveEaseOut:
                animOptions = UIViewAnimationOptionCurveEaseOut;
                break;
            case UIViewAnimationCurveEaseInOut:
                animOptions = UIViewAnimationOptionCurveEaseInOut;
                break;
            case UIViewAnimationCurveLinear:
                animOptions = UIViewAnimationOptionCurveLinear;
                break;
        }
        
        _scrollViewBottomInset = bottomInset;
        [UIView animateWithDuration:[[userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue] delay:0 options:animOptions animations:^
         {
             if (_currentKeyboardInsetEveningMode == 0)
             {
                 UIEdgeInsets insets = _scrollView.contentInset;
                 insets.bottom += _scrollViewBottomInset;
                 _scrollView.contentInset = insets;
                 
                 _currentKeyboardInsetEveningMode++;
             }
         } completion:^(BOOL finished)
         {
             if (_scrollOffsetBlock != nil)
             {
                 CGPoint offset = _scrollOffsetBlock(_scrollView, keyboardFrame);
                 
                 [UIView animateWithDuration:0.15f delay:0.f options:UIViewAnimationOptionCurveEaseIn animations:^{
                     _scrollView.contentOffset = offset;
                 } completion:^(BOOL finished) {
                     
                 }];
             }
             else if (_staticScrollOffset.y != 0.f)
             {
                 [UIView animateWithDuration:0.15f delay:0.f options:UIViewAnimationOptionCurveEaseIn animations:^{
                     _scrollView.contentOffset = CGPointMake(_scrollView.contentOffset.x, _staticScrollOffset.y);
                 } completion:^(BOOL finished) {
                     
                 }];
             }
             else
             {
                 [_scrollView scrollRectToVisible:[((UIView *)_currentFirstResponder).superview convertRect:((UIView *)_currentFirstResponder).frame toView:_scrollView] animated:YES];
             }
         }];
	}
}

- (void)keyboardWillHide:(NSNotification *)notification
{
	//if (self.navigationController.topViewController == self ||
    //    (!self.navigationController && !self.modalViewController))
	if ((!self.viewController || ((self.viewController.navigationController.topViewController == self.viewController ||
         self.viewController.navigationController.presentedViewController == self.viewController ||
         (self.viewController.navigationController == nil)) && self.viewController.isViewLoaded && self.viewController.view.window)) && !_suppressKeyboardEvents)
    {
        _isKeyboardShowingForThisVC = NO;
        
		NSDictionary *userInfo = [notification userInfo];
        
        UIViewAnimationOptions animOptions = 0;
        switch ([[userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue])
        {
            case UIViewAnimationCurveEaseIn:
                animOptions = UIViewAnimationOptionCurveEaseIn;
                break;
            case UIViewAnimationCurveEaseOut:
                animOptions = UIViewAnimationOptionCurveEaseOut;
                break;
            case UIViewAnimationCurveEaseInOut:
                animOptions = UIViewAnimationOptionCurveEaseInOut;
                break;
            case UIViewAnimationCurveLinear:
                animOptions = UIViewAnimationOptionCurveLinear;
                break;
        }
        
        [UIView animateWithDuration:[[userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue] delay:0 options:animOptions animations:^
         {
             if (_currentKeyboardInsetEveningMode == 1)
             {
                 UIEdgeInsets insets = _scrollView.contentInset;
                 insets.bottom -= _scrollViewBottomInset;
                 _scrollView.contentInset = insets;
                 
                 _currentKeyboardInsetEveningMode--;
             }
         } completion:^(BOOL finished)
         {
             if (_scrollToOriginalPositionAfterKeyboardHide)
             {
                 [_scrollView setContentOffset:_lastOffsetBeforeKeyboardWasShown animated:YES];
             }
         }];
	}
}

- (void)dismissKeyboardIfPossible
{
    BOOL resigned = NO;
    if (_useEndEditingForDismiss)
    {
        if (self.viewController && self.viewController.isViewLoaded)
        {
            resigned = [self.viewController.view endEditing:YES];
        }
        
        if (!resigned && self.scrollView)
        {
            resigned = [self.scrollView endEditing:YES];
        }
    }
    
    if (!resigned && [_currentFirstResponder canResignFirstResponder])
    {
        resigned = [_currentFirstResponder resignFirstResponder];
    }
    
    if (resigned)
    {
        self.currentFirstResponder = nil;
    }
}

@end
