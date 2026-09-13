#import "BLCVideoMuxer.h"
#import "BLCDownloadModel.h"
#import <UIKit/UIKit.h>

@interface BLCVideoMuxer ()
@property(nonatomic, strong) AVAssetExportSession *exporter;
@property(nonatomic, strong) NSArray<AVURLAsset *> *assets;
@property(nonatomic, copy) void (^completion)(NSError *);
@property(nonatomic) BOOL ended;
@end
@implementation BLCVideoMuxer
- (void)mergeVideo:(NSURL *)video audio:(NSURL *)audio output:(NSURL *)output duration:(NSTimeInterval)duration completion:(void (^)(NSError *))completion {
    self.completion = completion;
    self.assets = @[[AVURLAsset URLAssetWithURL:video options:nil], [AVURLAsset URLAssetWithURL:audio options:nil]];
    dispatch_group_t group = dispatch_group_create();
    for (AVURLAsset *asset in self.assets) {
        dispatch_group_enter(group);
        [asset loadValuesAsynchronouslyForKeys:@[@"tracks", @"duration"] completionHandler:^{ dispatch_group_leave(group); }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (self.ended) return;
        for (AVURLAsset *asset in self.assets) for (NSString *key in @[@"tracks", @"duration"]) {
            NSError *error = nil;
            if ([asset statusOfValueForKey:key error:&error] != AVKeyValueStatusLoaded) { [self finish:error ?: BLCDownloadError(@"无法读取音视频轨道")]; return; }
        }
        [self exportTo:output expectedDuration:duration];
    });
}
- (void)exportTo:(NSURL *)output expectedDuration:(NSTimeInterval)duration {
    AVURLAsset *video = self.assets.firstObject, *audio = self.assets.lastObject;
    AVAssetTrack *vt = [video tracksWithMediaType:AVMediaTypeVideo].firstObject;
    AVAssetTrack *at = [audio tracksWithMediaType:AVMediaTypeAudio].firstObject;
    double seconds = CMTimeGetSeconds(video.duration), audioSeconds = CMTimeGetSeconds(audio.duration);
    if (!vt || !at || !isfinite(seconds) || !isfinite(audioSeconds) || fabs(seconds - duration) > 2 || fabs(seconds - audioSeconds) > 2) {
        [self finish:BLCDownloadError(@"音视频轨道或时长不完整")]; return;
    }
    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *v = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *a = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    NSError *error = nil;
    if (![v insertTimeRange:CMTimeRangeMake(kCMTimeZero, video.duration) ofTrack:vt atTime:kCMTimeZero error:&error] ||
        ![a insertTimeRange:CMTimeRangeMake(kCMTimeZero, audio.duration) ofTrack:at atTime:kCMTimeZero error:&error]) {
        [self finish:error ?: BLCDownloadError(@"音视频合并失败")]; return;
    }
    v.preferredTransform = vt.preferredTransform;
    self.exporter = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetPassthrough];
    if (!self.exporter || ![self.exporter.supportedFileTypes containsObject:AVFileTypeMPEG4]) { [self finish:BLCDownloadError(@"当前编码不支持无损保存")]; return; }
    self.exporter.outputURL = output; self.exporter.outputFileType = AVFileTypeMPEG4;
    [self.exporter exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.ended) return;
            if (self.exporter.status != AVAssetExportSessionStatusCompleted) { [self finish:self.exporter.error ?: BLCDownloadError(@"合并失败")]; return; }
            if (!UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(output.path)) { [self finish:BLCDownloadError(@"该编码无法保存到相册")]; return; }
            [self finish:nil];
        });
    }];
}
- (float)progress { return self.exporter.progress; }
- (void)finish:(NSError *)error {
    if (self.ended) return; self.ended = YES; void (^completion)(NSError *) = self.completion;
    self.completion = nil; self.assets = nil; if (completion) completion(error);
}
- (void)cancel {
    for (AVURLAsset *a in self.assets) [a cancelLoading]; [self.exporter cancelExport];
    [self finish:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
}
@end
