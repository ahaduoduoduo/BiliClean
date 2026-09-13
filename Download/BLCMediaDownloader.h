#import "BLCDownloadModel.h"
@interface BLCMediaDownloader : NSObject
@property(nonatomic, readonly) int64_t receivedBytes;
@property(nonatomic, readonly) int64_t expectedBytes;
- (void)startPlan:(BLCDownloadPlan *)plan directory:(NSURL *)directory completion:(void (^)(NSArray<NSURL *> *, NSError *))completion;
- (void)cancel;
@end
