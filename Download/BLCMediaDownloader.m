#import "BLCMediaDownloader.h"

@interface BLCMediaPart : NSObject
@property(nonatomic, strong) BLCDownloadMedia *media;
@property(nonatomic, strong) NSURLSessionDownloadTask *task;
@property(nonatomic, strong) NSURL *file;
@property(nonatomic) NSUInteger attempt;
@property(nonatomic) int64_t received;
@end
@implementation BLCMediaPart
@end
@interface BLCMediaDownloader () <NSURLSessionDownloadDelegate>
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSArray<BLCMediaPart *> *parts;
@property(nonatomic, strong) NSURL *directory;
@property(nonatomic, copy) void (^completion)(NSArray<NSURL *> *, NSError *);
@property(nonatomic) BOOL ended;
@end
@implementation BLCMediaDownloader
- (void)startPlan:(BLCDownloadPlan *)plan directory:(NSURL *)directory completion:(void (^)(NSArray<NSURL *> *, NSError *))completion {
    NSAssert(NSThread.isMainThread, @"Download state uses the main queue");
    self.directory = directory; self.completion = completion;
    BLCMediaPart *v = [BLCMediaPart new], *a = [BLCMediaPart new]; v.media = plan.video; a.media = plan.audio; self.parts = @[v,a];
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.HTTPCookieStorage = nil; config.URLCache = nil; config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 7200;
    self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:NSOperationQueue.mainQueue];
    [self startPart:v]; [self startPart:a];
}
- (void)startPart:(BLCMediaPart *)part {
    if (self.ended) return;
    if (part.attempt >= part.media.URLs.count) { [self finish:nil error:BLCDownloadError(@"下载地址不可用，请重试")]; return; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:part.media.URLs[part.attempt++]];
    [request setValue:@"bytes=0-" forHTTPHeaderField:@"Range"];
    [request setValue:@"Bilibili/8.76.0 (iPhone; iOS 16.7.12; Scale/3.00)" forHTTPHeaderField:@"User-Agent"];
    part.received = 0; part.task = [self.session downloadTaskWithRequest:request]; [part.task resume];
}
- (BLCMediaPart *)partForTask:(NSURLSessionTask *)task {
    for (BLCMediaPart *part in self.parts) if (part.task == task) return part;
    return nil;
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)bytes totalBytesWritten:(int64_t)total totalBytesExpectedToWrite:(int64_t)expected {
    BLCMediaPart *p = [self partForTask:task]; p.received = total;
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    if (self.ended) return; BLCMediaPart *part = [self partForTask:task]; if (!part) return;
    NSHTTPURLResponse *response = (id)task.response;
    int64_t size = [[[NSFileManager defaultManager] attributesOfItemAtPath:location.path error:nil] fileSize];
    if (![response isKindOfClass:NSHTTPURLResponse.class] || !BLCDownloadCompleteRange(response.statusCode, [response valueForHTTPHeaderField:@"Content-Range"], size, part.media.size)) {
        part.task = nil; [self startPart:part]; return;
    }
    NSURL *file = [self.directory URLByAppendingPathComponent:part == self.parts.firstObject ? @"video.mp4" : @"audio.m4a"];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:file error:&error]) { [self finish:nil error:error]; return; }
    part.file = file; part.received = size;
    if (self.parts.firstObject.file && self.parts.lastObject.file) [self finish:@[self.parts.firstObject.file, self.parts.lastObject.file] error:nil];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (self.ended || !error) return; BLCMediaPart *part = [self partForTask:task];
    if (part && !part.file) [self startPart:part];
}
- (int64_t)receivedBytes { int64_t result = 0; for (BLCMediaPart *p in self.parts) result += p.received; return result; }
- (int64_t)expectedBytes { int64_t result = 0; for (BLCMediaPart *p in self.parts) { if (p.media.size <= 0) return 0; result += p.media.size; } return result; }
- (void)finish:(NSArray<NSURL *> *)files error:(NSError *)error {
    if (self.ended) return; self.ended = YES;
    void (^completion)(NSArray *, NSError *) = self.completion; self.completion = nil;
    [self.session invalidateAndCancel]; self.session = nil; if (completion) completion(files, error);
}
- (void)cancel { [self finish:nil error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]]; }
@end
