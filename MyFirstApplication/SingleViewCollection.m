//
// Created by Michael Pryor on 10/07/2016.
//

#import "SingleViewCollection.h"
#import "ViewInteractions.h"
#import "Timer.h"
#import "Threading.h"

@implementation SingleViewCollection {
    float _duration;
    UIView *_requestedView;

    UIView *_currentRealView;
    UIView *_viewBeingLoaded;

    id <ViewChangeNotifier> _viewChangeNotifier;
    Timer *_timer;
}
- (id)initWithDuration:(float)duration viewChangeNotifier:(id <ViewChangeNotifier>)viewChangeNotifier {
    self = [super init];
    if (self) {
        _duration = duration;
        _requestedView = nil;
        _currentRealView = nil;
        _viewChangeNotifier = viewChangeNotifier;
        _timer = [[Timer alloc] init];
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

        if (_requestedView == nil) {
            _viewBeingLoaded = nil;
            return;
        }
        viewToUse = _viewBeingLoaded = _requestedView;
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
        [_timer reset];
        doDisplay = _viewBeingLoaded == nil;
        if (doDisplay) {
            _viewBeingLoaded = view;
        } else {
            _requestedView = view;
        }
        previousView = _currentRealView;
    }
    if (doDisplay) {
        [self doReplaceView:previousView withView:view];
    }
}

// The idea behind this is to delay switching screens, if we predict that we will not be returning
// to that screen soon. Feels alot smoother.
- (void)displayView:(UIView *)view ifNoChangeForMilliseconds:(uint)milliseconds {
    bool doNow;
    @synchronized (self) {
        doNow = _currentRealView == nil || _currentRealView == view;
    }
    if (doNow) {
        [self displayView:view];
        return;
    }

    __block Timer *_timeSubmitted = [[Timer alloc] initFromTimer:_timer];
    dispatch_async_main(^{
        if ([_timeSubmitted getTimerEpoch] != [_timer getTimerEpoch]) {
            return;
        }
        [self displayView:view];
    }, milliseconds);
}

- (void)doReplaceView:(UIView *)oldView withView:(UIView *)newView {
    if (oldView == nil) {
        [_viewChangeNotifier onStartedFadingIn:newView duration:_duration];
        [ViewInteractions fadeIn:newView completion:^(BOOL completion) {
            if (!completion) {
                [newView setAlpha:1];
            }
            [_viewChangeNotifier onFinishedFadingIn:newView duration:_duration];
            [self onCompletion];
        }               duration:_duration];

        return;
    }

    // It looks much nicer not to fade out all the way when there's no change in screen.
    float outAlpha;
    if (oldView == newView) {
        outAlpha = 0.6f;
    } else {
        outAlpha = 0;
    }

    [_viewChangeNotifier onStartedFadingOut:oldView duration:_duration];
    [ViewInteractions fadeOut:oldView completion:^(BOOL completionOut) {
        if (!completionOut) {
            [oldView setAlpha:0];
        }
        [_viewChangeNotifier onFinishedFadingOut:oldView duration:_duration];
        [_viewChangeNotifier onStartedFadingIn:newView duration:_duration];
        [ViewInteractions fadeIn:newView completion:^(BOOL completionIn) {
            if (!completionIn) {
                [newView setAlpha:1];
            }
            [_viewChangeNotifier onFinishedFadingIn:newView duration:_duration];

            [self onCompletion];
        }               duration:_duration];
    }                duration:_duration toAlpha:outAlpha];
}

@end