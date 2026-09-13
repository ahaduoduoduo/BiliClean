#import "BLCCDNSpeedProbe.h"

static NSUInteger const BLCCDNProbeByteLimit = 2 * 1024 * 1024;
static NSTimeInterval const BLCCDNProbeTimeout = 8.0;

static NSError *BLCCDNSpeedProbeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"com.imlr.biliclean.cdn.probe"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"CDN 测速失败"}];
}

@interface BLCCDNSpeedProbe () <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, copy) BLCCDNSpeedProbeCompletion completion;
@property (nonatomic, assign) NSUInteger receivedBytes;
@property (nonatomic, assign) CFAbsoluteTime startedAt;
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, assign) BOOL finished;
@end

@implementation BLCCDNSpeedProbe

- (void)startWithURL:(NSURL *)URL completion:(BLCCDNSpeedProbeCompletion)completion {
    self.completion = completion;
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = BLCCDNProbeTimeout;
    configuration.timeoutIntervalForResource = BLCCDNProbeTimeout;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.URLCache = nil;
    configuration.HTTPCookieStorage = nil;
    configuration.HTTPShouldSetCookies = NO;

    NSOperationQueue *delegateQueue = [[NSOperationQueue alloc] init];
    delegateQueue.maxConcurrentOperationCount = 1;
    self.session = [NSURLSession sessionWithConfiguration:configuration
                                                 delegate:self
                                            delegateQueue:delegateQueue];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    request.timeoutInterval = BLCCDNProbeTimeout;
    [request setValue:@"bytes=0-2097151" forHTTPHeaderField:@"Range"];
    [request setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126 Safari/537.36"
   forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"https://www.bilibili.com/" forHTTPHeaderField:@"Referer"];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];

    self.startedAt = CFAbsoluteTimeGetCurrent();
    self.task = [self.session dataTaskWithRequest:request];
    [self.task resume];
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        self.statusCode = ((NSHTTPURLResponse *)response).statusCode;
    }
    if (self.statusCode < 200 || self.statusCode >= 300) {
        completionHandler(NSURLSessionResponseCancel);
        [self finishWithError:BLCCDNSpeedProbeError(
            self.statusCode,
            [NSString stringWithFormat:@"HTTP %ld", (long)self.statusCode]
        )];
        return;
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    if (self.finished) {
        return;
    }
    self.receivedBytes += data.length;
    if (self.receivedBytes >= BLCCDNProbeByteLimit) {
        [self finishWithError:nil];
        [dataTask cancel];
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (self.finished) {
        return;
    }
    if (self.receivedBytes >= 64 * 1024 &&
        self.statusCode >= 200 &&
        self.statusCode < 300) {
        [self finishWithError:nil];
        return;
    }
    [self finishWithError:error ?: BLCCDNSpeedProbeError(-3, @"未收到足够的媒体数据")];
}

- (void)finishWithError:(NSError *)error {
    if (self.finished) {
        return;
    }
    self.finished = YES;
    NSTimeInterval elapsed = MAX(CFAbsoluteTimeGetCurrent() - self.startedAt, 0.001);
    NSNumber *speed = nil;
    if (!error && self.receivedBytes > 0) {
        speed = @((double)self.receivedBytes / elapsed / 1000000.0);
    }
    BLCCDNSpeedProbeCompletion completion = self.completion;
    self.completion = nil;
    [self.session invalidateAndCancel];
    if (completion) {
        completion(speed, error);
    }
}

- (void)cancel {
    if (self.finished) {
        return;
    }
    [self.task cancel];
    [self finishWithError:BLCCDNSpeedProbeError(NSURLErrorCancelled, @"测速已取消")];
}

@end
