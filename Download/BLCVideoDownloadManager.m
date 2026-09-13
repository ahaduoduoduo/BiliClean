#import "BLCVideoDownloadManager.h"
#import "BLCMediaDownloader.h"
#import "BLCVideoMuxer.h"
#import "BLCVideoAlbumWriter.h"
#import "BLCDownloadProgressView.h"
#import <objc/message.h>

typedef NS_ENUM(NSInteger, BLCDownloadStage) { BLCResolving, BLCDownloading, BLCMerging, BLCAuthorizing, BLCSaving, BLCFinished, BLCFailed, BLCCancelled };
@interface BLCDownloadJob : NSObject
@property(nonatomic) int64_t aid;
@property(nonatomic) int64_t cid;
@property(nonatomic) BLCDownloadStage stage;
@property(nonatomic) BOOL ended;
@property(nonatomic) BOOL merged;
@property(nonatomic, strong) NSURL *directory;
@property(nonatomic, strong) NSURL *output;
@property(nonatomic, strong) BLCDownloadPlan *plan;
@property(nonatomic, strong) BLCMediaDownloader *downloader;
@property(nonatomic, strong) BLCVideoMuxer *muxer;
@property(nonatomic, strong) BLCDownloadProgressView *capsule;
@end
@implementation BLCDownloadJob
@end
@interface BLCVideoDownloadManager ()
@property(nonatomic, strong) BLCDownloadJob *job;
@property(nonatomic, strong) NSTimer *timer;
@end
@implementation BLCVideoDownloadManager
+ (instancetype)sharedManager { static id manager; static dispatch_once_t once; dispatch_once(&once, ^{ manager = [self new]; }); return manager; }
- (BOOL)active:(BLCDownloadJob *)job { return self.job == job && !job.ended; }
- (void)clean:(BLCDownloadJob *)job { if (job.directory) [[NSFileManager defaultManager] removeItemAtURL:job.directory error:nil]; }
- (void)startProgressTimer {
    __weak typeof(self) weakSelf = self;
    [self.timer invalidate]; self.timer = [NSTimer scheduledTimerWithTimeInterval:0.33 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf tick]; }];
}
- (void)startAID:(int64_t)aid cid:(int64_t)cid window:(UIWindow *)window {
    NSAssert(NSThread.isMainThread, @"UI entry requires main thread");
    if (self.job && !self.job.ended) { [self.job.capsule keepVisible]; return; }
    if (self.job) { [self.job.capsule dismiss]; [self clean:self.job]; }
    BLCDownloadJob *job = [BLCDownloadJob new]; job.aid = aid; job.cid = cid; self.job = job;
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"BiliCleanDownload-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    job.directory = [NSURL fileURLWithPath:directory isDirectory:YES]; job.output = [job.directory URLByAppendingPathComponent:@"merged.mp4"];
    job.capsule = [BLCDownloadProgressView new]; [job.capsule presentInWindow:window];
    __weak typeof(self) weakSelf = self; __weak BLCDownloadJob *weakJob = job;
    job.capsule.cancelAction = ^{ [weakSelf cancel:weakJob]; };
    [self startProgressTimer];
    NSError *error = nil;
    if (aid <= 0 || cid <= 0) { [self fail:job error:BLCDownloadError(@"无法确定当前视频，请重新打开播放页")]; return; }
    if (![[NSFileManager defaultManager] createDirectoryAtURL:job.directory withIntermediateDirectories:YES attributes:nil error:&error]) { [self fail:job error:error]; return; }
    [self resolve:job];
}
- (void)resolve:(BLCDownloadJob *)job {
    job.stage = BLCResolving; [job.capsule updateTitle:@"正在获取视频" detail:@"选择最高普通画质" progress:-1 cancellable:YES];
    Class requestClass = NSClassFromString(@"BAPIAppPlayeruniteV1PlayViewUniteReq"), vodClass = NSClassFromString(@"BAPIPlayersharedVideoVod"), service = NSClassFromString(@"BAPIAppPlayeruniteV1Player");
    SEL selector = NSSelectorFromString(@"playViewUniteWithRequest:handler:");
    if (!requestClass || !vodClass || ![service respondsToSelector:selector]) { [self fail:job error:BLCDownloadError(@"当前 B站版本不支持完整下载")]; return; }
    id request = [requestClass new], vod = [vodClass new];
    NSDictionary *fields = @{@"aid":@(job.aid), @"cid":@(job.cid), @"qn":@127, @"fnver":@0, @"fnval":@3472, @"fourk":@YES, @"forceHost":@2, @"download":@0, @"isNeedTrial":@NO};
    for (NSString *key in fields) if (!BLCDownloadSet(vod, key, fields[key])) { [self fail:job error:BLCDownloadError(@"播放接口字段不兼容")]; return; }
    if (!BLCDownloadSet(request, @"vod", vod)) { [self fail:job error:BLCDownloadError(@"无法构造播放请求")]; return; }
    void (^handler)(id, NSError *) = ^(id reply, NSError *error) {
        BLCDownloadPlan *plan = reply ? BLCDownloadReplyPlan(reply) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self active:job] || job.stage != BLCResolving) return;
            if (error) { [self fail:job error:error]; return; }
            if (!plan) { [self fail:job error:BLCDownloadError(@"没有可下载的完整普通 SDR 视频")]; return; }
            if (plan.aid != job.aid || plan.cid != job.cid) { [self fail:job error:BLCDownloadError(@"播放接口返回了不同视频")]; return; }
            job.plan = plan; [self download:job];
        });
    };
    ((void (*)(id, SEL, id, id))objc_msgSend)(service, selector, request, handler);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([self active:job] && job.stage == BLCResolving) [self fail:job error:BLCDownloadError(@"获取播放地址超时")];
    });
}
- (void)download:(BLCDownloadJob *)job {
    job.stage = BLCDownloading; job.downloader = [BLCMediaDownloader new];
    [job.downloader startPlan:job.plan directory:job.directory completion:^(NSArray<NSURL *> *files, NSError *error) {
        if (![self active:job]) return;
        if (error) { [self fail:job error:error]; return; }
        job.stage = BLCMerging; job.muxer = [BLCVideoMuxer new];
        [job.capsule updateTitle:@"正在合并音视频" detail:[job.plan.quality stringByAppendingString:@" · 无损合并"] progress:-1 cancellable:YES];
        [job.muxer mergeVideo:files.firstObject audio:files.lastObject output:job.output duration:job.plan.duration completion:^(NSError *muxError) {
            if (![self active:job]) return;
            if (muxError) { [self fail:job error:muxError]; return; }
            job.merged = YES; [self authorize:job];
        }];
    }]; [self tick];
}
- (void)authorize:(BLCDownloadJob *)job {
    if (![self active:job]) return; job.stage = BLCAuthorizing;
    [job.capsule updateTitle:@"准备保存视频" detail:@"正在检查照片权限" progress:-1 cancellable:YES];
    [BLCVideoAlbumWriter authorize:^(NSError *error) {
        if (![self active:job] || job.stage != BLCAuthorizing) return;
        if (error) { [self fail:job error:error]; return; }
        job.stage = BLCSaving; [job.capsule updateTitle:@"正在保存视频" detail:@"即将完成" progress:-1 cancellable:NO];
        [BLCVideoAlbumWriter saveVideo:job.output completion:^(NSString *destination, NSError *saveError) {
            if (![self active:job]) return;
            if (saveError) { [self fail:job error:saveError]; return; }
            job.stage = BLCFinished; job.ended = YES; [self.timer invalidate]; self.timer = nil;
            [self clean:job]; [job.capsule completeWithQuality:job.plan.quality destination:destination];
            NSLog(@"[BiliClean] download saved aid=%lld cid=%lld quality=%@", job.aid, job.cid, job.plan.quality);
        }];
    }];
}
- (void)tick {
    BLCDownloadJob *job = self.job; if (!job || job.ended) return; [job.capsule keepVisible];
    if (job.stage != BLCDownloading) return;
    int64_t received = job.downloader.receivedBytes, total = job.downloader.expectedBytes;
    double progress = total > 0 ? MIN(0.999, (double)received / total) : -1;
    NSString *title = progress < 0 ? @"正在下载" : [NSString stringWithFormat:@"正在下载 %.0f%%", floor(progress * 100)];
    NSString *size = total > 0 ? [NSString stringWithFormat:@"%.1f / %.1f MB", received / 1048576.0, total / 1048576.0] : [NSString stringWithFormat:@"%.1f MB", received / 1048576.0];
    [job.capsule updateTitle:title detail:[NSString stringWithFormat:@"%@ · %@", job.plan.quality, size] progress:progress cancellable:YES];
}
- (void)fail:(BLCDownloadJob *)job error:(NSError *)error {
    if (![self active:job]) return; job.ended = YES; job.stage = BLCFailed;
    [job.downloader cancel]; [job.muxer cancel]; [self.timer invalidate]; self.timer = nil;
    if (!job.merged) [self clean:job];
    [job.capsule updateTitle:job.merged ? @"保存失败 · 轻点重试" : @"下载失败" detail:error.localizedDescription ?: @"请重试" progress:-1 cancellable:YES];
    if (job.merged) {
        __weak typeof(self) weakSelf = self; __weak BLCDownloadJob *weakJob = job;
        job.capsule.retryAction = ^{
            typeof(self) self = weakSelf; BLCDownloadJob *retry = weakJob;
            if (self.job != retry || retry.stage != BLCFailed) return;
            retry.ended = NO; retry.capsule.retryAction = nil; [self startProgressTimer]; [self authorize:retry];
        };
    }
    NSLog(@"[BiliClean] download failed aid=%lld cid=%lld: %@", job.aid, job.cid, error.localizedDescription);
}
- (void)cancel:(BLCDownloadJob *)job {
    if (!job || job.stage == BLCSaving) return;
    job.ended = YES; job.stage = BLCCancelled; [job.downloader cancel]; [job.muxer cancel];
    [self.timer invalidate]; self.timer = nil; [self clean:job]; [job.capsule dismiss];
}
@end
