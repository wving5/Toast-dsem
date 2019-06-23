

#import "M4ToastUtil.h"
#import <objc/runtime.h>

#define Associate_Lazy_Getter(_type, _getter, _key) \
- (_type *)_getter {\
_type *_getter = objc_getAssociatedObject(self, &_key);\
if (_getter == nil) {\
_getter = [[_type alloc] init];\
objc_setAssociatedObject(self, &_key, _getter, OBJC_ASSOCIATION_RETAIN_NONATOMIC);\
}\
return _getter;\
}

#define TOAST_ALPHA  0.85
#define TOAST_DELAY_FLASH 0.3
#define TOAST_DELAY_SHORT_TXT 2.0
#define TOAST_SHOW_ANIME_DURATION  0.2
#define TOAST_HIDE_ANIME_DURATION  0.3

typedef NS_ENUM(NSUInteger, M4ToastStatus) {
    M4ToastStatusDefault,
    M4ToastStatusDoShowing,
    M4ToastStatusDisplaying,
    M4ToastStatusDoHiding,
    M4ToastStatusHidden,
};



@interface M4Toast : UIView
@property (nonatomic, assign) M4ToastStatus status;
@property (nonatomic, assign) NSTimeInterval moveToSupeViewAt;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, copy)   NSString *title;
@property (nonatomic, assign, readonly) NSTimeInterval showingTime;
@property (nonatomic, copy) void (^onCompletion)(BOOL tap);
@property (nonatomic, copy) void (^nextStep)(M4Toast* wSelf);
@end

@implementation M4Toast
+ (instancetype)newToastWithTip:(NSString *)tip inView:(UIView *)view {
    // content label
    UILabel *contentLabel           = [[UILabel alloc] init];
    contentLabel.numberOfLines      = 0;
    contentLabel.textAlignment      = NSTextAlignmentCenter;
    contentLabel.backgroundColor    = [UIColor clearColor];
    contentLabel.textColor          = [UIColor whiteColor];
    contentLabel.text               = tip;
    contentLabel.font               = [UIFont fontWithName:@"Helvetica" size:15];
    
    // content label frame
    CGSize maxsize                  = CGSizeMake([UIScreen mainScreen].bounds.size.width - 48, 600);
    CGFloat minWidth                = 88.0;
    NSDictionary *attdic            = @{NSFontAttributeName: [UIFont fontWithName:@"Helvetica" size:15]};
    CGSize tipsSize                 = [tip boundingRectWithSize:maxsize options:NSStringDrawingUsesFontLeading |NSStringDrawingUsesLineFragmentOrigin attributes:attdic context:nil].size;
    tipsSize.width                  = MAX(minWidth, tipsSize.width);
    contentLabel.frame              = CGRectMake(0, 0, tipsSize.width, tipsSize.height);
    
    // hud
    M4Toast* newHudView                = [[self alloc] init];
    newHudView.backgroundColor         = [UIColor blackColor];
    newHudView.layer.cornerRadius      = 2;
    newHudView.layer.opacity           = 0;
    newHudView.title                   = tip;
    
    // hud frame
    CGFloat horizontalMargin        = 16;
    CGFloat verticalMargin          = 6;
    CGSize hudViewSize              = CGSizeMake(contentLabel.bounds.size.width + horizontalMargin * 2,
                                                 contentLabel.bounds.size.height + verticalMargin * 2);
    
    CGPoint hudViewCenter           = view.center;
    if (![view isKindOfClass:[UIWindow class]]) {
        hudViewCenter.y -= 90;
    }
    
    newHudView.frame       = CGRectMake(0, 0, hudViewSize.width, hudViewSize.height);
    newHudView.center      = hudViewCenter;
    contentLabel.center    = CGPointMake(newHudView.bounds.size.width / 2, newHudView.bounds.size.height / 2);
    
    [newHudView addSubview:contentLabel];
    
    return newHudView;
}

- (void)willMoveToSuperview:(UIView *)newSuperview
{
    if (newSuperview != nil) {
        self.moveToSupeViewAt = CACurrentMediaTime();
    } else {
        self.moveToSupeViewAt = 0;
    }
}

- (NSTimeInterval)showingTime
{
    return self.moveToSupeViewAt > 0 ? CACurrentMediaTime() - self.moveToSupeViewAt : 0;
}
@end



/***
 **   copy impl from https://github.com/scalessec/Toast **
 ***/
@interface UIView (M4Toast)
- (void)m4_showToast:(M4Toast *)toast duration:(NSTimeInterval)duration completion:(void(^)(BOOL didTap))completion;
- (void)m4_hideToast:(M4Toast *)toast animated:(BOOL)animated;
@property (nonatomic, strong, readonly) NSMutableArray* m4_activeToasts;
@property (nonatomic, strong, readonly) NSMutableArray* m4_toastQueue;
@end
@implementation UIView (M4Toast)

static const NSString * M4NT_ToastQueueKey             = @"M4NT_ToastQueueKey";
static const NSString * M4NT_ToastActiveKey            = @"M4NT_ToastActiveKey";

Associate_Lazy_Getter(NSMutableArray, m4_activeToasts, M4NT_ToastActiveKey)
Associate_Lazy_Getter(NSMutableArray, m4_toastQueue, M4NT_ToastQueueKey)

#pragma mark - Events

- (void)m4_toastTimerDidFinish:(NSTimer *)timer {
    [self _m4_hideToast:(M4Toast *)timer.userInfo animated:YES];
}

- (void)m4_handleToastTapped:(UITapGestureRecognizer *)recognizer {
    M4Toast *toast = (M4Toast *)recognizer.view;
    [self _m4_hideToast:toast fromTap:YES animated:YES];
}

#pragma mark - Show Toast Methods

- (void)m4_showToast:(M4Toast *)toast duration:(NSTimeInterval)duration completion:(void(^)(BOOL didTap))completion {
    if (toast == nil) return;
    toast.onCompletion = completion;
    if (M4ToastUtil.shareInstance.isQueueEnabled && self.m4_activeToasts.count > 0) {
        if (self.m4_toastQueue.count > 0) { // already queued up
            // cut previous duration
            M4Toast *prevToast = self.m4_toastQueue.lastObject;
            prevToast.duration = TOAST_DELAY_FLASH;
        } else {
            M4Toast *activeToast = self.m4_activeToasts.lastObject;
            NSTimeInterval overTime = activeToast.showingTime - TOAST_DELAY_FLASH;
            if (overTime >= 0) { // timeout prev
                [self safe_hideToast:activeToast animated:YES];
            } else {  // wait & kill prev
                NSTimeInterval lifeLeft = 0 - overTime;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(lifeLeft * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                   [self safe_hideToast:activeToast animated:YES];
                });
            }
        }
        // enqueue
        [self.m4_toastQueue addObject:toast];
    } else {
        // present
        if (M4ToastUtil.shareInstance.isQueueEnabled == NO &&
            M4ToastUtil.shareInstance.removePrevToastImmediatelyWhenOverlap == YES
            ) {
            [self m4_hideToast:self.m4_activeToasts.lastObject animated:NO];
        }
        [self _m4_showToast:toast duration:duration];
    }
}

#pragma mark - Hide Toast Methods

- (void)safe_hideToast:(M4Toast *)activeToast animated:(BOOL)animated {
    if (activeToast.status <= M4ToastStatusDoShowing) {
        activeToast.nextStep = ^(M4Toast *wSelf) {
            [self m4_hideToast:wSelf animated:animated];
        };
    } else {
        [self m4_hideToast:activeToast animated:animated];
    }
}

- (void)m4_hideToast:(M4Toast *)toast animated:(BOOL)animated {
    // sanity
    if (!toast || ![[self m4_activeToasts] containsObject:toast]) return;
    
    [self _m4_hideToast:toast animated:animated];
}

- (void)m4_hideAllToasts {
    [[self m4_toastQueue] removeAllObjects];
    
    for (M4Toast *toast in [self m4_activeToasts]) {
        [self m4_hideToast:toast animated:YES];
    }
}

#pragma mark - Private Show/Hide Methods

- (void)_m4_showToast:(M4Toast *)toast duration:(NSTimeInterval)duration {
    toast.alpha = 0.0;
    
    if (toast.status >= M4ToastStatusDoShowing) {
        return;
    }
    toast.status = M4ToastStatusDoShowing;

    if ([M4ToastUtil.shareInstance isTapToDismissEnabled]) {
        UITapGestureRecognizer *recognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(m4_handleToastTapped:)];
        [toast addGestureRecognizer:recognizer];
        toast.userInteractionEnabled = YES;
        toast.exclusiveTouch = YES;
    }
    
    [[self m4_activeToasts] addObject:toast];
    
    [self addSubview:toast];
    
    [UIView animateWithDuration:TOAST_SHOW_ANIME_DURATION
                          delay:0.0
                        options:(UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction)
                     animations:^{
                         toast.alpha = 1.0;
                     } completion:^(BOOL finished) {
                         toast.status = M4ToastStatusDisplaying;

                         if (toast.nextStep) {
                             toast.nextStep(toast);
                             toast.nextStep = nil;
                             return;
                         }
                         
                         __weak typeof(self) wSelf = self;
                         __weak typeof(toast) wToast = toast;
                         NSTimer *timer = [NSTimer timerWithTimeInterval:duration
                                                                  target:wSelf
                                                                selector:@selector(m4_toastTimerDidFinish:)
                                                                userInfo:wToast
                                                                 repeats:NO];
                         [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
                         toast.timer = timer;
                     }];
}

- (void)_m4_hideToast:(M4Toast *)toast animated:(BOOL)animated {
    [self _m4_hideToast:toast fromTap:NO animated:animated];
}

- (void)_m4_hideToast:(M4Toast *)toast fromTap:(BOOL)fromTap animated:(BOOL)animated {
    NSTimer *timer = toast.timer;
    if (timer.isValid) {
        [timer invalidate];
    }
    
    if (toast.status >= M4ToastStatusDoHiding) {
        return;
    }
    
    toast.status = M4ToastStatusDoHiding;
    
    void (^onComplete)(BOOL finished) = ^(BOOL finished){
        [toast removeFromSuperview];
        [[self m4_activeToasts] removeObject:toast];
        
        toast.status = M4ToastStatusHidden;
        
        if (toast.nextStep) {
            toast.nextStep(toast);
            toast.nextStep = nil;
            return;
        }
        
        // execute the completion block, if necessary
        void (^completion)(BOOL didTap) = toast.onCompletion;
        if (completion) {
            completion(fromTap);
        }
        
        // deque next, if needed
        if ([self.m4_toastQueue count] > 0) {
            M4Toast *nextToast = [[self m4_toastQueue] firstObject];
            [[self m4_toastQueue] removeObjectAtIndex:0];
            
            [self _m4_showToast:nextToast duration:nextToast.duration];
        }
    };
    
    if (animated) {
        [UIView animateWithDuration:TOAST_HIDE_ANIME_DURATION
                              delay:0.0
                            options:(UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState)
                         animations:^{
                             toast.alpha = 0.0;
                         } completion:onComplete];
    } else {
        onComplete(NO);
    }
}

@end


@implementation M4ToastUtil

static id _m_instance = nil;
+ (M4ToastUtil *)shareInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _m_instance = [[M4ToastUtil alloc] init];
    });
    return _m_instance;
}

- (instancetype)init
{
    if (self = [super init]) {
        _tapToDismissEnabled = YES;
        _queueEnabled = YES;
        _removePrevToastImmediatelyWhenOverlap = NO;
    }
    return self;
}

#pragma mark - Public Methods

- (void)showTip:(NSString *)tips {
    if (!tips || tips.length == 0) {
        return;
    }
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    [self showTip:tips inView:window];
}

- (void)showTip:(NSString *)tips inView:(UIView *)view {
    [self showTip:tips inView:view duration:TOAST_DELAY_SHORT_TXT completion:nil];
}

- (void)showTip:(NSString *)tips inView:(UIView *)view duration:(NSTimeInterval)duration {
    [self showTip:tips inView:view duration:duration completion:nil];
}

- (void)showTip:(NSString *)tips inView:(UIView *)view duration:(NSTimeInterval)duration completion:(void(^)(void))completion {
    M4Toast *toast = [M4Toast newToastWithTip:tips inView:view];
    toast.duration = duration;
    [view m4_showToast:toast duration:duration completion:^(BOOL didTap) {
        if (completion) completion();
    }];
}

@end
