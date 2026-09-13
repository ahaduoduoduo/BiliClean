#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^BLCCDNSpeedProbeCompletion)(NSNumber * _Nullable megabytesPerSecond,
                                           NSError * _Nullable error);

@interface BLCCDNSpeedProbe : NSObject

- (void)startWithURL:(NSURL *)URL completion:(BLCCDNSpeedProbeCompletion)completion;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
