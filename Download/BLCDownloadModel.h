#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface BLCDownloadMedia : NSObject
@property(nonatomic, copy) NSArray<NSURL *> *URLs;
@property(nonatomic) int64_t size;
@property(nonatomic) NSInteger identifier;
@property(nonatomic) NSInteger codec;
@property(nonatomic) NSInteger audioID;
@property(nonatomic) NSInteger width;
@property(nonatomic) NSInteger height;
@property(nonatomic) double fps;
@property(nonatomic) NSInteger bandwidth;
@property(nonatomic) BOOL intact;
@property(nonatomic) BOOL encrypted;
@end

@interface BLCDownloadPlan : NSObject
@property(nonatomic) int64_t aid;
@property(nonatomic) int64_t cid;
@property(nonatomic) NSTimeInterval duration;
@property(nonatomic, strong) BLCDownloadMedia *video;
@property(nonatomic, strong) BLCDownloadMedia *audio;
@property(nonatomic, copy) NSString *quality;
@end

FOUNDATION_EXPORT id _Nullable BLCDownloadValue(id _Nullable object, NSString *key);
FOUNDATION_EXPORT BOOL BLCDownloadSet(id object, NSString *key, id value);
FOUNDATION_EXPORT BOOL BLCDownloadHas(id object, NSString *key);
FOUNDATION_EXPORT NSError *BLCDownloadError(NSString *message);
FOUNDATION_EXPORT BLCDownloadPlan *_Nullable BLCDownloadSelect(NSArray<BLCDownloadMedia *> *videos, NSArray<BLCDownloadMedia *> *audios);
FOUNDATION_EXPORT BOOL BLCDownloadCompleteRange(NSInteger status, NSString *_Nullable range, int64_t actual, int64_t expected);
FOUNDATION_EXPORT void BLCDownloadCaptureReply(id reply);
FOUNDATION_EXPORT BLCDownloadPlan *_Nullable BLCDownloadReplyPlan(id reply);
NS_ASSUME_NONNULL_END
