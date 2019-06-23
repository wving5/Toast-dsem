

#import <UIKit/UIKit.h>

@interface M4ToastUtil : NSObject

+ (M4ToastUtil *)shareInstance;

@property (assign, nonatomic, getter=isTapToDismissEnabled) BOOL tapToDismissEnabled;
@property (assign, nonatomic, getter=isQueueEnabled) BOOL queueEnabled;
@property (assign, nonatomic) BOOL removePrevToastImmediatelyWhenOverlap; // ONLY work when queueEnabled==NO

- (void)showTip:(NSString *)tips;
- (void)showTip:(NSString *)tips inView:(UIView *)view;
- (void)showTip:(NSString *)tips inView:(UIView *)view duration:(NSTimeInterval)duration;
- (void)showTip:(NSString *)tips inView:(UIView *)view duration:(NSTimeInterval)duration completion:(void(^)(void))completion;

@end
