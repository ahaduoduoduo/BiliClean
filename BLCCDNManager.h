#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const BLCCDNConfigurationDidChangeNotification;
FOUNDATION_EXPORT NSString *const BLCCDNSpeedTestDidUpdateNotification;

typedef void (^BLCCDNSpeedProgressBlock)(NSUInteger completed,
                                         NSUInteger total,
                                         NSString *host,
                                         NSNumber * _Nullable megabytesPerSecond,
                                         NSString * _Nullable errorMessage);
typedef void (^BLCCDNSpeedCompletionBlock)(NSArray<NSString *> *selectedHosts,
                                           NSDictionary<NSString *, NSNumber *> *speeds,
                                           NSError * _Nullable error);

@interface BLCCDNManager : NSObject

@property (nonatomic, readonly, getter=isTesting) BOOL testing;

+ (instancetype)sharedManager;
+ (void)registerDefaults;

- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)enabled;
- (NSString *)sampleBVID;
- (BOOL)setSampleBVID:(NSString *)bvid error:(NSError **)error;

- (NSArray<NSDictionary<NSString *, NSString *> *> *)candidates;
- (NSString *)displayNameForHost:(NSString *)host;
- (NSArray<NSString *> *)selectedHosts;
- (void)setSelectedHosts:(NSArray<NSString *> *)hosts;
- (NSDictionary<NSString *, NSNumber *> *)lastSpeeds;
- (NSString *)selectedSummary;

- (void)startSpeedTestWithProgress:(nullable BLCCDNSpeedProgressBlock)progress
                        completion:(nullable BLCCDNSpeedCompletionBlock)completion;
- (void)cancelSpeedTest;

- (void)rewritePlayViewReply:(id)reply;

@end

NS_ASSUME_NONNULL_END
