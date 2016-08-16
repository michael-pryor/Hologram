//
// Created by Michael Pryor on 10/07/2016.
//

#import "SingleViewCollection.h"
#import "ViewInteractions.h"
#import "Timer.h"
#import "Threading.h"

@implementation SingleViewCollection {
    float _duration;

    // View requested to be faded in, but not currently being actioned.
    UIView *_requestedView;

    // Currently fully displayed view (or partially if something is currently being loaded).
    UIView *_currentRealView;

    // View currently fading in.
    UIView *_viewBeingLoaded;

    id _requestedMeta;
    id _metaBeingLoaded;

    id <ViewChangeNotifier> _viewChangeNotifier;
    Timer *_timer;

    // List of items which we do not fade out/in, but we do still call the fading callbacks.
    NSMutableArray *_noFade;
}
- (id)initWithDuration:(float)duration viewChangeNotifier:(id <ViewChangeNotifier>)viewChangeNotifier {
    self = [super init];
    if (self) {
        _duration = duration;
        _requestedView = nil;
        _requestedMeta = nil;
        _currentRealView = nil;
        _viewChangeNotifier = viewChangeNotifier;
        _timer = [[Timer alloc] init];
        _noFade = [[NSMutableArray alloc] init];
    }
    return self;
}

- (UIView *)getCurrentlyDisplayedView {
    return _currentRealView;
}

- (bool)isViewCurrent:(UIView *)view {
    // If its the currently displayed view, and nothing else is loaded OR
    // If its the view currently being loaded OR
    // If its the next requested view.
    return ((_currentRealView == view && _viewBeingLoaded == nil) ||
            _viewBeingLoaded == view ||
            _requestedView == view);
}

- (void)registerNoFadeView:(UIView *)view {
    [_noFade addObject:view];
}

- (void)onCompletion {
    UIView *viewToUse;
    UIView *previousViewToUse;
    id metaToUse;
    @synchronized (self) {
        // We just finished loading, so update the real view.
        _currentRealView = _viewBeingLoaded;
        previousViewToUse = _currentRealView;

        if (_requestedView == nil) {
            _viewBeingLoaded = nil;
            _metaBeingLoaded = nil;
            return;
        }
        viewToUse = _viewBeingLoaded = _requestedView;
        metaToUse = _metaBeingLoaded = _requestedMeta;
        _requestedView = nil;
        _requestedMeta = nil;
    }

    [self doReplaceView:previousViewToUse withView:viewToUse meta:metaToUse];
}

- (void)displayView:(UIView *)view meta:(id)meta {
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
            _metaBeingLoaded = meta;
        } else {
            _requestedView = view;
            _requestedMeta = meta;
        }
        previousView = _currentRealView;
    }
    if (doDisplay) {
        [self doReplaceView:previousView withView:view meta:meta];
    }
}

// The idea behind this is to delay switching screens, if we predict that we will not be returning
// to that screen soon. Feels alot smoother.
- (void)displayView:(UIView *)view ifNoChangeForMilliseconds:(uint)milliseconds meta:(id)meta {
    bool doNow;
    @synchronized (self) {
        doNow = _currentRealView == nil || _currentRealView == view;
    }
    if (doNow) {
        [self displayView:view meta:meta];
        return;
    }

    __block Timer *_timeSubmitted = [[Timer alloc] initFromTimer:_timer];
    dispatch_async_main(^{
        if ([_timeSubmitted getTimerEpoch] != [_timer getTimerEpoch]) {
            return;
        }
        [self displayView:view meta:meta];
    }, milliseconds);
}

- (void)doReplaceView:(UIView *)oldView withView:(UIView *)newView meta:(id)meta {
    if (oldView == nil) {
        [_viewChangeNotifier onStartedFadingIn:newView duration:_duration meta:meta];
        [ViewInteractions fadeIn:newView completion:^(BOOL completion) {
            if (!completion) {
                [newView setAlpha:1];
            }
            [_viewChangeNotifier onFinishedFadingIn:newView duration:_duration meta:meta];
            [self onCompletion];
        }               duration:_duration];

        return;
    }

    // It looks much nicer not to fade out all the way when there's no change in screen.
    float outAlpha;
    if (oldView == newView) {
        if ([_noFade containsObject:newView]) {
            outAlpha = 1.0f;
        } else {
            outAlpha = 0.6f;
        }
    } else {
        outAlpha = 0;
    }

    if (outAlpha == 1.0f) {
        const uint durationMs = (uint)(_duration * 1000.0f);
        [_viewChangeNotifier onStartedFadingOut:oldView duration:_duration alpha:outAlpha];

        dispatch_async_main(^{
            [_viewChangeNotifier onFinishedFadingOut:oldView duration:_duration alpha:outAlpha];
            [_viewChangeNotifier onStartedFadingIn:newView duration:_duration meta:meta];
            dispatch_async_main(^{
                [_viewChangeNotifier onFinishedFadingIn:newView duration:_duration meta:meta];
                [self onCompletion];
            }, durationMs);
        }, durationMs);
        return;
    }

    [_viewChangeNotifier onStartedFadingOut:oldView duration:_duration alpha:outAlpha];
    [ViewInteractions fadeOut:oldView completion:^(BOOL completionOut) {
        if (!completionOut) {
            [oldView setAlpha:outAlpha];
        }
        [_viewChangeNotifier onFinishedFadingOut:oldView duration:_duration alpha:outAlpha];
        [_viewChangeNotifier onStartedFadingIn:newView duration:_duration meta:meta];
        [ViewInteractions fadeIn:newView completion:^(BOOL completionIn) {
            if (!completionIn) {
                [newView setAlpha:1];
            }
            [_viewChangeNotifier onFinishedFadingIn:newView duration:_duration meta:meta];

            [self onCompletion];
        }               duration:_duration];
    }                duration:_duration toAlpha:outAlpha];
}

@end