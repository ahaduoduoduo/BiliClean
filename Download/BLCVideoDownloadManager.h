#import <UIKit/UIKit.h>
#import "BLCDownloadModel.h"
@interface BLCVideoDownloadManager : NSObject
+ (instancetype)sharedManager;
- (void)startAID:(int64_t)aid cid:(int64_t)cid window:(UIWindow *)window;
@end
FOUNDATION_EXPORT void BLCInstallVideoDownloadHooks(void);
FOUNDATION_EXPORT void BLCDownloadObservePlayback(id playback);
