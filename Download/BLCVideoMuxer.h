#import <AVFoundation/AVFoundation.h>
@interface BLCVideoMuxer : NSObject
@property(nonatomic, readonly) float progress;
- (void)mergeVideo:(NSURL *)video audio:(NSURL *)audio output:(NSURL *)output duration:(NSTimeInterval)duration completion:(void (^)(NSError *))completion;
- (void)cancel;
@end
