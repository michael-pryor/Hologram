//
// Created by Michael Pryor on 10/07/2016.
//

#import "SingleViewCollection.h"
#import "ViewInteractions.h"

@implementation SingleViewCollection {
    float _duration;
    UIView *_requestedView;

    UIView *_currentRealView;
    UIView *_viewBeingDisplayedNow;

    id <ViewChangeNotifier> _viewChangeNotifier;
}
- (id)initWithDuration:(float)duration viewChangeNotifier:(id <ViewChangeNotifier>)viewChangeNotifier {
    self = [super init];
    if (self) {
        _duration = duration;
        _requestedView = nil;
        _currentRealView = nil;
        _viewChangeNotifier = viewChangeNotifier;
    }
    return self;
}

- (UIView *)getCurrentlyDisplayedView {
    return _currentRealView;
}

- (void)onCompletion:(BOOL)completed {
    UIView *viewToUse;
    UIView *previousViewToUse;
    @synchronized (self) {
        previousViewToUse = _currentRealView;
        if (completed) {
            _currentRealView = _viewBeingDisplayedNow;
        }

        if (_requestedView == nil) {
            if (previousViewToUse != nil) {
                [_viewChangeNotifier onFinishedDisplayingView:previousViewToUse];
            }
            _viewBeingDisplayedNow = nil;
            return;
        }
        viewToUse = _viewBeingDisplayedNow = _requestedView;
        _requestedView = nil;
    }

    if (_viewChangeNotifier != nil) {
        if (previousViewToUse != nil) {
            [_viewChangeNotifier onFinishedDisplayingView:previousViewToUse];
        }
        [_viewChangeNotifier onStartedDisplayingView:viewToUse];
    }

    [self doReplaceView:previousViewToUse withView:viewToUse];
}

- (void)displayView:(UIView *)view {
    if (view == nil) {
        return;
    }

    bool doDisplay;
    UIView *previousView;
    @synchronized (self) {
        _requestedView = view;

        doDisplay = _viewBeingDisplayedNow == nil;
        if (doDisplay) {
            _viewBeingDisplayedNow = view;
        }
        previousView = _currentRealView;
    }
    if (doDisplay) {
        [self doReplaceView:previousView withView:view];
    }
}

- (void)doReplaceView:(UIView *)oldView withView:(UIView *)newView {
    if (oldView == nil) {
        [ViewInteractions fadeIn:newView completion:^(BOOL completion) {
            [self onCompletion:completion];
        }               duration:_duration];
        return;
    }

    [ViewInteractions fadeOut:oldView completion:^(BOOL completionOut) {
        if (!completionOut) {
            return;
        }

        [ViewInteractions fadeIn:newView completion:^(BOOL completionIn) {
            [self onCompletion:completionOut && completionIn];
        }               duration:_duration];
    }                duration:_duration];
}

@end