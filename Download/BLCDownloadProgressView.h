#import <UIKit/UIKit.h>
@interface BLCDownloadProgressView : UIView
@property(nonatomic, copy) dispatch_block_t cancelAction;
@property(nonatomic, copy) dispatch_block_t retryAction;
- (void)presentInWindow:(UIWindow *)window;
- (void)updateTitle:(NSString *)title detail:(NSString *)detail progress:(double)progress cancellable:(BOOL)cancellable;
- (void)keepVisible;
- (void)completeWithQuality:(NSString *)quality destination:(NSString *)destination;
- (void)dismiss;
@end
