#import "BLCDownloadProgressView.h"

@interface BLCDownloadProgressView ()
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *detailLabel;
@property(nonatomic, strong) UIProgressView *bar;
@property(nonatomic, strong) UIButton *close;
@property(nonatomic, weak) UIWindow *host;
@property(nonatomic) BOOL dismissing;
@end
@implementation BLCDownloadProgressView
- (instancetype)init {
    if (!(self = [super initWithFrame:CGRectMake(0, 0, 248, 44)])) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.66]; self.layer.cornerRadius = 22; self.clipsToBounds = YES;
    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 5, 194, 17)];
    _titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold]; _titleLabel.textColor = UIColor.whiteColor;
    _detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 22, 194, 13)];
    _detailLabel.font = [UIFont systemFontOfSize:10]; _detailLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1];
    _bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault]; _bar.frame = CGRectMake(14, 39, 220, 2);
    _bar.progressTintColor = [UIColor colorWithRed:1 green:0.4 blue:0.6 alpha:1]; _bar.trackTintColor = [UIColor colorWithWhite:0.3 alpha:0.7];
    _close = [UIButton buttonWithType:UIButtonTypeCustom]; _close.frame = CGRectMake(210, 0, 38, 44);
    [_close setTitle:@"×" forState:UIControlStateNormal]; _close.titleLabel.font = [UIFont systemFontOfSize:21]; _close.accessibilityLabel = @"取消下载";
    [_close addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *view in @[_titleLabel, _detailLabel, _bar, _close]) [self addSubview:view];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(retryTapped)]; tap.cancelsTouchesInView = NO; [self addGestureRecognizer:tap];
    self.accessibilityIdentifier = @"BiliClean.DownloadProgress";
    return self;
}
- (void)cancelTapped { if (self.cancelAction) self.cancelAction(); }
- (void)retryTapped { if (self.retryAction) self.retryAction(); }
- (void)presentInWindow:(UIWindow *)window {
    self.host = window; [window addSubview:self]; [self keepVisible];
    self.alpha = 0; self.transform = UIAccessibilityIsReduceMotionEnabled() ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(0, -8);
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ self.alpha = 1; self.transform = CGAffineTransformIdentity; } completion:nil];
}
- (void)keepVisible {
    if (self.dismissing || !self.host || self.host.hidden) return;
    self.center = CGPointMake(CGRectGetMidX(self.host.bounds), self.host.safeAreaInsets.top + 29);
    [self.host bringSubviewToFront:self];
}
- (void)updateTitle:(NSString *)title detail:(NSString *)detail progress:(double)progress cancellable:(BOOL)cancellable {
    self.titleLabel.text = title; self.detailLabel.text = detail; self.bar.hidden = progress < 0;
    if (progress >= 0) [self.bar setProgress:(float)MIN(1, MAX(0, progress)) animated:YES]; self.close.hidden = !cancellable;
}
- (void)completeWithQuality:(NSString *)quality destination:(NSString *)destination {
    self.retryAction = nil; self.bar.progressTintColor = UIColor.systemGreenColor;
    [self updateTitle:[@"✓ 已保存到 " stringByAppendingString:destination] detail:[quality stringByAppendingString:@" · 完整视频"] progress:1 cancellable:YES];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, [@"视频已保存到 " stringByAppendingString:destination]);
    if (!UIAccessibilityIsReduceMotionEnabled()) [UIView animateWithDuration:0.18 animations:^{ self.transform = CGAffineTransformMakeScale(1.025, 1.025); } completion:^(__unused BOOL finished) {
        if (!self.dismissing) [UIView animateWithDuration:0.18 animations:^{ self.transform = CGAffineTransformIdentity; }];
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self dismiss]; });
}
- (void)dismiss {
    if (self.dismissing) return; self.dismissing = YES;
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.alpha = 0; if (!UIAccessibilityIsReduceMotionEnabled()) self.transform = CGAffineTransformMakeTranslation(0, -6);
    } completion:^(__unused BOOL finished) { [self removeFromSuperview]; self.cancelAction = nil; self.retryAction = nil; }];
}
@end
