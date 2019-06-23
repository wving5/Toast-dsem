

#import "M4ToastUtil.h"
#import <objc/runtime.h>

#define TOAST_ALPHA  0.85
#define TOAST_DELAY_FLASH 0.1
#define TOAST_DELAY_SHORT 2.0
#define TOAST_SHOW_ANIME_DURATION  0.2
#define TOAST_HIDE_ANIME_DURATION  0.3

#define OBJC_ASSOCIATE_GETTER_SETTER(_type, _getter, _setter, _key) \
static char _key;\
- (_type *)_getter { return objc_getAssociatedObject(self, &_key); }\
- (void)_setter:(_type *)_getter { objc_setAssociatedObject(self, &_key, _getter, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

NSString* const kM4NoticeOperationDelay = @"delay";
NSString* const kM4NoticeOperationExtraLife = @"extra_life";

typedef NS_ENUM(NSUInteger, M4NoticeOpFlag) {
    M4NoticeOpFlagDefault,
    M4NoticeOpFlagDoShowing,
    M4NoticeOpFlagInDuration,
    M4NoticeOpFlagDoHiding,
};



@interface NSOperation (M4Notice)
@property (nonatomic, strong) NSNumber* ext_Duration;
@property (nonatomic, strong) NSOperation* ext_nextOperation;
@property (nonatomic, strong) NSNumber* ext_Flag;
@end
@implementation NSOperation (M4Notice)
OBJC_ASSOCIATE_GETTER_SETTER(NSNumber, ext_Duration, setExt_Duration, M4Notice_Operation_Duration_Key)
OBJC_ASSOCIATE_GETTER_SETTER(NSNumber, ext_Flag, setExt_Flag, M4Notice_Operation_Flag_Key)
OBJC_ASSOCIATE_GETTER_SETTER(NSOperation, ext_nextOperation, setExt_nextOperation, M4Notice_Operation_NextOperation_Key)
@end



@interface M4ToastUtil () {
    UIView * _m_hudView;
}
@property (strong, nonatomic) dispatch_semaphore_t noticeLock;
@property (nonatomic, strong) NSOperationQueue *operationQ;
@property (nonatomic, strong) NSMutableArray <NSString *> *pendingToastStrList;
@property (nonatomic, assign) NSTimeInterval lastShowingFrom;
@property (nonatomic, assign) BOOL isBusyWaiting;
@end

@implementation M4ToastUtil

static id _m_instance = nil;

+ (M4ToastUtil *)shareInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!_m_instance) {
            _m_instance = [[M4ToastUtil alloc] init];
        }
    });
    return _m_instance;
}

- (instancetype)init
{
    if (self = [super init]) {
        _operationQ = [NSOperationQueue new];
        _operationQ.maxConcurrentOperationCount = 1;
        _noticeLock = dispatch_semaphore_create(1);
        _pendingToastStrList = @[].mutableCopy;
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
    [self showTip:tips inView:view duration:TOAST_DELAY_SHORT completion:nil];
}

- (void)showTip:(NSString *)tips inView:(UIView *)view duration:(NSTimeInterval)duration {
    [self showTip:tips inView:view duration:duration completion:nil];
}

- (void)showTip:(NSString *)tips inView:(UIView *)view duration:(NSTimeInterval)duration completion:(void(^)(void))completion {
    [self _showTip:tips inView:view duration:duration completion:completion];
}

#pragma mark - Awful stuff beginning

- (void)_showTip:(NSString *)tips inView:(UIView *)view duration:(NSTimeInterval)duration completion:(void(^)(void))completion {
    
    BOOL isPending =  self.pendingToastStrList.count > 0;
    BOOL cutPreviousToast =  self.pendingToastStrList.count == 1;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval timeLeap = now  - self.lastShowingFrom;

    // cut running duration
    if (cutPreviousToast &&
        _m_hudView.superview) { // showing | waiting | hiding
        if (YES == self.isBusyWaiting) {
            if (timeLeap >= TOAST_DELAY_FLASH) {
                // cancel current delay
                dispatch_semaphore_signal(self.noticeLock);
            } else {
                // modify next delay if needed
                for (NSOperation *op in self.operationQ.operations) {
                    if (op.finished == NO &&
                        op.ext_Flag.integerValue == M4NoticeOpFlagInDuration &&
                        [op.name isEqualToString:kM4NoticeOperationDelay] &&
                        op.ext_nextOperation != nil
                        ) {
                        op.ext_nextOperation.ext_Duration = @(TOAST_DELAY_FLASH - timeLeap);
                    }
                }
                
                // cancel current delay
                dispatch_semaphore_signal(self.noticeLock);
            }
        }
    }
    
    if (isPending) {
        // cut next pending toast's duration
        [self.operationQ.operations enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(__kindof NSOperation * _Nonnull op, NSUInteger idx, BOOL * _Nonnull stop) {
            if (op.isExecuting == NO &&
                [op.name isEqualToString:kM4NoticeOperationDelay] &&
                op.ready == YES &&
                op.finished == NO &&
                op.cancelled == NO
                ) {
                op.ext_Duration = @(TOAST_DELAY_FLASH);
                *stop = YES;
            }
        }];
    }
    
    // pending toast
    [self.pendingToastStrList addObject:tips];
    
    // show HUD
    [self.operationQ addOperation: [self op_showToastInView:view tip:tips]];
    
    // delay
    NSOperation *delay = [self op_durationWithMaxInterval:duration tip:tips];
    delay.name = kM4NoticeOperationDelay;
    [self.operationQ addOperation: delay];
    // extra "life", default is a unnoticeable value
    NSOperation *delayNs = [self op_durationWithMaxInterval:0.01 tip:tips];
    delayNs.name = kM4NoticeOperationExtraLife;
    delay.ext_nextOperation = delayNs;
    [self.operationQ addOperation: delayNs];

    // hide HUD
    [self.operationQ addOperation: [self op_hideToast:tips]];
    
}

- (NSBlockOperation *)op_durationWithMaxInterval:(NSTimeInterval)maxDuration tip:(NSString *)tips {
    NSBlockOperation *blockOp = [NSBlockOperation new];
    blockOp.ext_Duration = @(maxDuration);
    __weak typeof(blockOp) weakOp = blockOp;
    __weak typeof(self) wself = self;
    [blockOp addExecutionBlock:^{
        // hold LOCK
        long ret = dispatch_semaphore_wait(self.noticeLock, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)));
        wself.isBusyWaiting = YES;
        weakOp.ext_Flag = @(M4NoticeOpFlagInDuration);
        
        // wait blocking
        ret = dispatch_semaphore_wait(
                                self.noticeLock,
                                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(weakOp.ext_Duration.doubleValue * NSEC_PER_SEC))
                                );
        
        // release lock
        dispatch_semaphore_signal(self.noticeLock);
    }];
    return blockOp;
}

- (NSBlockOperation *)op_showToastInView:(UIView *)view tip:(NSString *)tips {
    
    return [NSBlockOperation blockOperationWithBlock:^{
        dispatch_semaphore_wait(self.noticeLock, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)));
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _showToastInView:view tip:tips onCompletion:^{
                dispatch_semaphore_signal(self.noticeLock);
            }];
        });
    }];
}

- (NSBlockOperation *)op_hideToast:(NSString *)tips {
    return [NSBlockOperation blockOperationWithBlock:^{
        dispatch_semaphore_wait(self.noticeLock, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0 * NSEC_PER_SEC)));
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _hideToastTip:tips onCompletion:^{
                dispatch_semaphore_signal(self.noticeLock);
            }];
        });
    }];
}


#pragma mark Animatior
- (void)_showToastInView:(UIView *)view tip:(NSString *)tip onCompletion:(void (^)(void))completion {
    // new HUD
    _m_hudView = [self newHudViewWithTips:tip inView:view];
    [view addSubview:_m_hudView];
    [view bringSubviewToFront:_m_hudView];
    
    self.isBusyWaiting = NO;
    
    // tag timestamp
    self.lastShowingFrom = [[NSDate date] timeIntervalSince1970];
    
    // animation
    [UIView animateWithDuration:TOAST_SHOW_ANIME_DURATION
                          delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self->_m_hudView.layer.opacity = TOAST_ALPHA;
    } completion:^(BOOL finished) {
        if (completion != nil) {
            completion();
        }
    }];
}

- (void)_hideToastTip:(NSString *)tip onCompletion:(void (^)(void))completion {
    if (nil == _m_hudView.superview) return;
    
    self.isBusyWaiting = NO;
    
    [UIView animateWithDuration:TOAST_HIDE_ANIME_DURATION
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        self->_m_hudView.layer.opacity   = 0.0;
    } completion:^(BOOL finished) {
        // remove from pending list
        [self.pendingToastStrList removeObject:tip];
        
        [self->_m_hudView removeFromSuperview];
        if (completion != nil) {
            completion();
        }
    }];
}



#pragma mark  Constructor

- (UIView *)newHudViewWithTips:(NSString *)tips inView:(UIView *)view {
    // content label
    UILabel *contentLabel           = [[UILabel alloc] init];
    contentLabel.numberOfLines      = 0;
    contentLabel.textAlignment      = NSTextAlignmentCenter;
    contentLabel.backgroundColor    = [UIColor clearColor];
    contentLabel.textColor          = [UIColor whiteColor];
    contentLabel.text               = tips;
    contentLabel.font               = [UIFont fontWithName:@"Helvetica" size:15];
    
    // content label frame
    CGSize maxsize                  = CGSizeMake([UIScreen mainScreen].bounds.size.width - 48, 600);
    CGFloat minWidth                = 88.0;
    NSDictionary *attdic            = @{NSFontAttributeName: [UIFont fontWithName:@"Helvetica" size:15]};
    CGSize tipsSize                 = [tips boundingRectWithSize:maxsize options:NSStringDrawingUsesFontLeading |NSStringDrawingUsesLineFragmentOrigin attributes:attdic context:nil].size;
    if (tipsSize.width < minWidth) {
        tipsSize.width = minWidth;
    }
    contentLabel.frame              = CGRectMake(0, 0, tipsSize.width, tipsSize.height);
    
    // hudView
    UIView* newHudView                 = [[UIView alloc] init];
    newHudView.backgroundColor         = [UIColor blackColor];
    newHudView.layer.cornerRadius      = 2;
    newHudView.layer.opacity           = 0;
    
    // hudView frame
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
    contentLabel.center = CGPointMake(newHudView.bounds.size.width / 2, newHudView.bounds.size.height / 2);
    
    
    [newHudView addSubview:contentLabel];
    
    return newHudView;
}

@end
