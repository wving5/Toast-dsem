//
//  ViewController.m
//  Toast-dsem
//
//  Created by wving5 on 2019/6/24.
//

#import "ViewController.h"
#import "M4ToastUtil.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:@"Toast !\n." forState:UIControlStateNormal];
    [btn addTarget:self action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];
    btn.titleLabel.font = [UIFont systemFontOfSize:60];
    [btn sizeToFit];
    [self.view addSubview:btn];
}

- (void)onTap {
    NSTimeInterval timeoffset = 0;
    for (int i = 0; i < 10; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoffset * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [M4ToastUtil.shareInstance showTip:[NSString stringWithFormat:@"[%d] @%.2f",i, timeoffset]];
        });
        timeoffset += 0.25 * pow(2.0, arc4random()%4);
    }
}


@end
