#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const BLCTabConfigurationDidChangeNotification;

@interface BLCTabManager : NSObject

+ (instancetype)sharedManager;
+ (void)registerDefaults;

- (void)refresh;
- (NSArray<NSDictionary<NSString *, id> *> *)cachedItems;
- (NSDate * _Nullable)lastUpdatedAt;
- (BOOL)isTabVisible:(NSString *)tabID;
- (void)setTabID:(NSString *)tabID visible:(BOOL)visible;
- (NSArray<NSString *> *)tabKeywords;
- (void)setTabKeywords:(NSArray<NSString *> *)keywords;
- (NSUInteger)visibleItemCount;
- (NSUInteger)totalItemCount;

- (void)captureAndFilterResponseDictionary:(NSMutableDictionary *)root
                                 URLString:(NSString *)URLString;

@end

NS_ASSUME_NONNULL_END
