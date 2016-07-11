//
// Created by Michael Pryor on 10/07/2016.
//

#import "SingleViewCollection.h"
#import "ViewInteractions.h"

@implementation SingleViewCollection {
    float _duration;
    UIView *_requestedView;

    UIView *_currentRealView;
    UIView *_viewBeingLoaded;

    id <ViewChangeNotifier> _viewChangeNotifier;
}
- (id)initWithDuration:(float)duration viewChangeNotifier:(id <ViewChangeNotifier>)viewChangeNotifier {
    self = [super init];
    if (self) {
        _duration = duration;
        _requestedView = nil;
        _currentRealView = nil;
        _viewChangeNotifier = viewChangeNotifier;
        NSLog(@"&&&&&&&&&INSTNATIATING SingleViewController!!!");
    }
    return self;
}

- (UIView *)getCurrentlyDisplayedView {
    return _currentRealView;
}

- (bool)isViewDisplayedWideSearch:(UIView *)view {
    return (_currentRealView == view ||
            _viewBeingLoaded == view ||
            _requestedView == view);
}

- (void)onCompletion {
    UIView *viewToUse;
    UIView *previousViewToUse;
    @synchronized (self) {
        // We just finished loading, so update the real view.
        _currentRealView = _viewBeingLoaded;
        previousViewToUse = _currentRealView;

        [_viewChangeNotifier onGenericAcivity:_currentRealView activity:@"_currentRealView = _viewBeingLoaded"];

        if (_requestedView == nil) {
            _viewBeingLoaded = nil;
            [_viewChangeNotifier onGenericAcivity:_viewBeingLoaded activity:@"_viewBeingLoaded = nil"];
            return;
        }
        viewToUse = _viewBeingLoaded = _requestedView;
        [_viewChangeNotifier onGenericAcivity:viewToUse activity:@"viewToUse = _requestedView (viewToUse)"];
        [_viewChangeNotifier onGenericAcivity:_viewBeingLoaded activity:@"_viewBeingLoaded = _requestedView (_viewBeingLoaded)"];
        [_viewChangeNotifier onGenericAcivity:_requestedView activity:@"_viewBeingLoaded = _requestedView (_requestedView)"];
        _requestedView = nil;
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
        doDisplay = _viewBeingLoaded == nil;
        if (doDisplay) {
            _viewBeingLoaded = view;
            [_viewChangeNotifier onGenericAcivity:_viewBeingLoaded activity:@"_viewBeingLoaded = view (force action)"];
        } else {
            _requestedView = view;
            [_viewChangeNotifier onGenericAcivity:_requestedView activity:@"_requestedView = view"];
        }
        previousView = _currentRealView;
        [_viewChangeNotifier onGenericAcivity:previousView activity:@"previousView = _currentRealView"];
    }
    if (doDisplay) {
        [self doReplaceView:previousView withView:view];
    }
}

- (void)doReplaceView:(UIView *)oldView withView:(UIView *)newView {
    if (oldView == nil) {
        [_viewChangeNotifier onStartedFadingIn:newView duration:_duration];
        [ViewInteractions fadeIn:newView completion:^(BOOL completion) {
            if (!completion) {
                NSLog(@"***FAILED TO COMPLETE FADE IN!");
                [newView setAlpha:1];
            }
            [_viewChangeNotifier onFinishedFadingIn:newView duration:_duration];
            [self onCompletion];
        }               duration:_duration];

        return;
    }

    [_viewChangeNotifier onStartedFadingOut:oldView duration:_duration];
    [ViewInteractions fadeOut:oldView completion:^(BOOL completionOut) {
        if (!completionOut) {
            NSLog(@"***FAILED TO COMPLETE FADE OUT!");
            [oldView setAlpha:0];
        }
        [_viewChangeNotifier onFinishedFadingOut:oldView duration:_duration];
        [_viewChangeNotifier onStartedFadingIn:newView duration:_duration];
        [ViewInteractions fadeIn:newView completion:^(BOOL completionIn) {
            if (!completionIn) {
                NSLog(@"***FAILED TO COMPLETE FADE IN!");
                [newView setAlpha:1];
            }
            [_viewChangeNotifier onFinishedFadingIn:newView duration:_duration];

            [self onCompletion];
        }               duration:_duration];
    }                duration:_duration];
}

@end