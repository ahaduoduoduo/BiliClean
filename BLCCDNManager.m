#import "BLCCDNManager.h"
#import "BLCCDNSpeedProbe.h"
#import <objc/message.h>

NSString *const BLCCDNConfigurationDidChangeNotification = @"BLCCDNConfigurationDidChangeNotification";
NSString *const BLCCDNSpeedTestDidUpdateNotification = @"BLCCDNSpeedTestDidUpdateNotification";

static NSString *const BLCCDNEnabledKey = @"blc.cdn.enabled";
static NSString *const BLCCDNSampleBVIDKey = @"blc.cdn.sample.bvid";
static NSString *const BLCCDNSelectedHostsKey = @"blc.cdn.selected.hosts";
static NSString *const BLCCDNSpeedsKey = @"blc.cdn.last.speeds";
static NSString *const BLCCDNDefaultBVID = @"BV1fK4y1t7hj";

static NSError *BLCCDNError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"com.imlr.biliclean.cdn"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"CDN 测速失败"}];
}

static id BLCGetModelValue(id object, NSString *key) {
    if (!object || key.length == 0) {
        return nil;
    }
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL BLCSetModelValue(id object, NSString *key, id value) {
    if (!object || key.length == 0) {
        return NO;
    }
    @try {
        [object setValue:value forKey:key];
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static BOOL BLCModelHasMessage(id object, NSString *propertyName) {
    if (!object || propertyName.length == 0) {
        return NO;
    }
    NSString *first = [[propertyName substringToIndex:1] uppercaseString];
    NSString *suffix = propertyName.length == 1
        ? first
        : [first stringByAppendingString:[propertyName substringFromIndex:1]];
    SEL selector = NSSelectorFromString([@"has" stringByAppendingString:suffix]);
    if ([object respondsToSelector:selector]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
    }
    return BLCGetModelValue(object, propertyName) != nil;
}

static NSString *BLCReplaceURLAuthority(NSString *urlString, NSString *authority) {
    if (urlString.length == 0 || authority.length == 0) {
        return urlString;
    }
    NSRange schemeRange = [urlString rangeOfString:@"://"];
    if (schemeRange.location == NSNotFound) {
        return urlString;
    }
    NSString *scheme = [[urlString substringToIndex:schemeRange.location] lowercaseString];
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return urlString;
    }
    NSUInteger authorityStart = NSMaxRange(schemeRange);
    if (authorityStart >= urlString.length) {
        return urlString;
    }
    NSCharacterSet *terminators = [NSCharacterSet characterSetWithCharactersInString:@"/?#"];
    NSRange suffixRange = [urlString rangeOfCharacterFromSet:terminators
                                                    options:0
                                                      range:NSMakeRange(authorityStart, urlString.length - authorityStart)];
    NSUInteger authorityEnd = suffixRange.location == NSNotFound ? urlString.length : suffixRange.location;
    if (authorityEnd <= authorityStart) {
        return urlString;
    }
    NSString *prefix = [urlString substringToIndex:authorityStart];
    NSString *suffix = [urlString substringFromIndex:authorityEnd];
    return [NSString stringWithFormat:@"%@%@%@", prefix, authority, suffix];
}

@interface BLCCDNManager ()
@property (nonatomic, assign, getter=isTesting) BOOL testing;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSUUID *testToken;
@property (nonatomic, strong) BLCCDNSpeedProbe *currentProbe;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *workingSpeeds;
@property (nonatomic, copy) BLCCDNSpeedProgressBlock progressBlock;
@property (nonatomic, copy) BLCCDNSpeedCompletionBlock completionBlock;
@property (nonatomic, copy) NSString *workingSampleURL;
@property (nonatomic, assign) NSUInteger workingIndex;
@end

@implementation BLCCDNManager

+ (instancetype)sharedManager {
    static BLCCDNManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[BLCCDNManager alloc] init];
    });
    return manager;
}

+ (void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        BLCCDNEnabledKey: @YES,
        BLCCDNSampleBVIDKey: BLCCDNDefaultBVID,
        BLCCDNSelectedHostsKey: @[
            @"upos-sz-mirrorcos.bilivideo.com",
            @"upos-sz-mirrorali.bilivideo.com",
            @"upos-sz-mirrorhw.bilivideo.com"
        ],
        BLCCDNSpeedsKey: @{}
    }];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.imlr.biliclean.cdn", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSArray<NSDictionary<NSString *,NSString *> *> *)candidates {
    static NSArray<NSDictionary<NSString *, NSString *> *> *items = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        items = @[
            @{@"name": @"ali（阿里云）", @"host": @"upos-sz-mirrorali.bilivideo.com"},
            @{@"name": @"alib（阿里云）", @"host": @"upos-sz-mirroralib.bilivideo.com"},
            @{@"name": @"alio1（阿里云）", @"host": @"upos-sz-mirroralio1.bilivideo.com"},
            @{@"name": @"cos（腾讯云）", @"host": @"upos-sz-mirrorcos.bilivideo.com"},
            @{@"name": @"cosb（腾讯云 VOD）", @"host": @"upos-sz-mirrorcosb.bilivideo.com"},
            @{@"name": @"coso1（腾讯云）", @"host": @"upos-sz-mirrorcoso1.bilivideo.com"},
            @{@"name": @"hw（华为云）", @"host": @"upos-sz-mirrorhw.bilivideo.com"},
            @{@"name": @"hwb（华为云）", @"host": @"upos-sz-mirrorhwb.bilivideo.com"},
            @{@"name": @"hwo1（华为云）", @"host": @"upos-sz-mirrorhwo1.bilivideo.com"},
            @{@"name": @"08c（华为云）", @"host": @"upos-sz-mirror08c.bilivideo.com"},
            @{@"name": @"08h（华为云）", @"host": @"upos-sz-mirror08h.bilivideo.com"},
            @{@"name": @"08ct（华为云）", @"host": @"upos-sz-mirror08ct.bilivideo.com"},
            @{@"name": @"tf_hw（华为云）", @"host": @"upos-tf-all-hw.bilivideo.com"},
            @{@"name": @"tf_tx（腾讯云）", @"host": @"upos-tf-all-tx.bilivideo.com"},
            @{@"name": @"akamai（海外）", @"host": @"upos-hz-mirrorakam.akamaized.net"},
            @{@"name": @"aliov（阿里云海外）", @"host": @"upos-sz-mirroraliov.bilivideo.com"},
            @{@"name": @"cosov（腾讯云海外）", @"host": @"upos-sz-mirrorcosov.bilivideo.com"},
            @{@"name": @"hwov（华为云海外）", @"host": @"upos-sz-mirrorhwov.bilivideo.com"},
            @{@"name": @"香港 BCache", @"host": @"cn-hk-eq-bcache-01.bilivideo.com"}
        ];
    });
    return items;
}

- (NSSet<NSString *> *)candidateHostSet {
    NSMutableSet<NSString *> *hosts = [NSMutableSet set];
    for (NSDictionary *item in [self candidates]) {
        [hosts addObject:item[@"host"]];
    }
    return hosts;
}

- (NSString *)displayNameForHost:(NSString *)host {
    for (NSDictionary *item in [self candidates]) {
        if ([item[@"host"] isEqualToString:host]) {
            return item[@"name"];
        }
    }
    return host ?: @"";
}

- (BOOL)isEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:BLCCDNEnabledKey];
}

- (void)setEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:BLCCDNEnabledKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:BLCCDNConfigurationDidChangeNotification object:self];
}

- (NSString *)sampleBVID {
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:BLCCDNSampleBVIDKey];
    return value.length > 0 ? value : BLCCDNDefaultBVID;
}

- (BOOL)setSampleBVID:(NSString *)bvid error:(NSError **)error {
    NSString *value = [bvid stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (value.length >= 2 && [[[value substringToIndex:2] lowercaseString] isEqualToString:@"bv"]) {
        value = [@"BV" stringByAppendingString:[value substringFromIndex:2]];
    }
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^BV[0-9A-Za-z]{10}$" options:0 error:nil];
    if ([regex numberOfMatchesInString:value options:0 range:NSMakeRange(0, value.length)] != 1) {
        if (error) {
            *error = BLCCDNError(-10, @"BV 号格式无效");
        }
        return NO;
    }
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:BLCCDNSampleBVIDKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:BLCCDNConfigurationDidChangeNotification object:self];
    return YES;
}

- (NSArray<NSString *> *)selectedHosts {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:BLCCDNSelectedHostsKey];
    if (![stored isKindOfClass:[NSArray class]]) {
        return @[];
    }
    NSSet *allowed = [self candidateHostSet];
    NSMutableArray<NSString *> *hosts = [NSMutableArray arrayWithCapacity:3];
    for (id value in (NSArray *)stored) {
        if ([value isKindOfClass:[NSString class]] && [allowed containsObject:value] && ![hosts containsObject:value]) {
            [hosts addObject:value];
            if (hosts.count == 3) {
                break;
            }
        }
    }
    return hosts;
}

- (void)setSelectedHosts:(NSArray<NSString *> *)hosts {
    NSSet *allowed = [self candidateHostSet];
    NSMutableArray<NSString *> *cleaned = [NSMutableArray arrayWithCapacity:3];
    for (id value in hosts) {
        if ([value isKindOfClass:[NSString class]] && [allowed containsObject:value] && ![cleaned containsObject:value]) {
            [cleaned addObject:value];
            if (cleaned.count == 3) {
                break;
            }
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:cleaned forKey:BLCCDNSelectedHostsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:BLCCDNConfigurationDidChangeNotification object:self];
    });
}

- (NSDictionary<NSString *,NSNumber *> *)lastSpeeds {
    id value = [[NSUserDefaults standardUserDefaults] dictionaryForKey:BLCCDNSpeedsKey];
    return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

- (NSString *)selectedSummary {
    NSArray<NSString *> *hosts = [self selectedHosts];
    if (hosts.count == 0) {
        return @"未选择";
    }
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:hosts.count];
    for (NSString *host in hosts) {
        NSString *name = [self displayNameForHost:host];
        NSArray *parts = [name componentsSeparatedByString:@"（"];
        [names addObject:parts.firstObject ?: name];
    }
    return [names componentsJoinedByString:@" > "];
}

- (NSURLSession *)anonymousSession {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = 15.0;
    configuration.timeoutIntervalForResource = 15.0;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.URLCache = nil;
    configuration.HTTPCookieStorage = nil;
    configuration.HTTPShouldSetCookies = NO;
    configuration.HTTPAdditionalHeaders = @{
        @"User-Agent": @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126 Safari/537.36",
        @"Referer": @"https://www.bilibili.com/"
    };
    return [NSURLSession sessionWithConfiguration:configuration];
}

- (void)fetchJSONAtURL:(NSURL *)URL completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    NSURLSession *session = [self anonymousSession];
    NSURLSessionDataTask *task = [session dataTaskWithURL:URL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [session finishTasksAndInvalidate];
        if (error) {
            completion(nil, error);
            return;
        }
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]]
            ? ((NSHTTPURLResponse *)response).statusCode
            : 0;
        if (status < 200 || status >= 300 || data.length == 0) {
            completion(nil, BLCCDNError(status, [NSString stringWithFormat:@"HTTP %ld", (long)status]));
            return;
        }
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (![object isKindOfClass:[NSDictionary class]]) {
            completion(nil, error ?: BLCCDNError(-11, @"接口返回不是 JSON 对象"));
            return;
        }
        NSDictionary *dict = object;
        if ([dict[@"code"] integerValue] != 0) {
            completion(nil, BLCCDNError([dict[@"code"] integerValue], dict[@"message"] ?: @"Bilibili 接口返回错误"));
            return;
        }
        completion(dict, nil);
    }];
    [task resume];
}

- (void)startSpeedTestWithProgress:(BLCCDNSpeedProgressBlock)progress
                        completion:(BLCCDNSpeedCompletionBlock)completion {
    dispatch_async(self.queue, ^{
        if (self.testing) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion([self selectedHosts], [self lastSpeeds], BLCCDNError(-20, @"测速正在进行"));
                }
            });
            return;
        }
        self.testing = YES;
        self.testToken = [NSUUID UUID];
        self.progressBlock = progress;
        self.completionBlock = completion;
        self.workingSpeeds = [NSMutableDictionary dictionary];
        self.workingIndex = 0;
        NSUUID *token = self.testToken;
        [self fetchSampleURLForBVID:[self sampleBVID] token:token];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:BLCCDNSpeedTestDidUpdateNotification object:self];
        });
    });
}

- (void)fetchSampleURLForBVID:(NSString *)bvid token:(NSUUID *)token {
    NSString *viewString = [NSString stringWithFormat:@"https://api.bilibili.com/x/web-interface/view?bvid=%@", bvid];
    [self fetchJSONAtURL:[NSURL URLWithString:viewString] completion:^(NSDictionary *viewJSON, NSError *error) {
        dispatch_async(self.queue, ^{
            if (![self.testToken isEqual:token]) {
                return;
            }
            if (error) {
                [self finishTestWithError:error token:token];
                return;
            }
            NSArray *pages = viewJSON[@"data"][@"pages"];
            NSNumber *cid = [pages isKindOfClass:[NSArray class]] ? [pages.firstObject objectForKey:@"cid"] : nil;
            if (![cid isKindOfClass:[NSNumber class]] || cid.longLongValue <= 0) {
                [self finishTestWithError:BLCCDNError(-21, @"无法从 BV 号获取 cid") token:token];
                return;
            }
            NSString *playString = [NSString stringWithFormat:
                @"https://api.bilibili.com/x/player/playurl?bvid=%@&cid=%@&qn=64&fnval=4048&fourk=1",
                bvid, cid];
            [self fetchJSONAtURL:[NSURL URLWithString:playString] completion:^(NSDictionary *playJSON, NSError *playError) {
                dispatch_async(self.queue, ^{
                    if (![self.testToken isEqual:token]) {
                        return;
                    }
                    if (playError) {
                        [self finishTestWithError:playError token:token];
                        return;
                    }
                    NSString *sampleURL = [self mediaURLFromPlayJSON:playJSON];
                    if (sampleURL.length == 0) {
                        [self finishTestWithError:BLCCDNError(-22, @"播放接口未返回可用媒体 URL") token:token];
                        return;
                    }
                    self.workingSampleURL = sampleURL;
                    [self probeNextCandidateWithToken:token];
                });
            }];
        });
    }];
}

- (NSString *)mediaURLFromPlayJSON:(NSDictionary *)JSON {
    NSDictionary *data = JSON[@"data"];
    NSDictionary *dash = [data[@"dash"] isKindOfClass:[NSDictionary class]] ? data[@"dash"] : nil;
    NSArray *videos = [dash[@"video"] isKindOfClass:[NSArray class]] ? dash[@"video"] : nil;
    for (NSDictionary *video in videos) {
        NSString *url = video[@"baseUrl"] ?: video[@"base_url"];
        if ([url isKindOfClass:[NSString class]] && url.length > 0) {
            return url;
        }
    }
    NSArray *durl = [data[@"durl"] isKindOfClass:[NSArray class]] ? data[@"durl"] : nil;
    NSString *url = [durl.firstObject objectForKey:@"url"];
    return [url isKindOfClass:[NSString class]] ? url : nil;
}

- (void)probeNextCandidateWithToken:(NSUUID *)token {
    if (![self.testToken isEqual:token]) {
        return;
    }
    NSArray *candidates = [self candidates];
    if (self.workingIndex >= candidates.count) {
        [self finishTestWithError:nil token:token];
        return;
    }
    NSDictionary *candidate = candidates[self.workingIndex];
    NSString *host = candidate[@"host"];
    NSString *testURLString = BLCReplaceURLAuthority(self.workingSampleURL, host);
    NSURL *testURL = [NSURL URLWithString:testURLString];
    if (!testURL) {
        self.workingIndex += 1;
        [self emitProgressForHost:host speed:nil error:@"测试 URL 无效"];
        [self probeNextCandidateWithToken:token];
        return;
    }

    BLCCDNSpeedProbe *probe = [[BLCCDNSpeedProbe alloc] init];
    self.currentProbe = probe;
    [probe startWithURL:testURL completion:^(NSNumber *speed, NSError *error) {
        dispatch_async(self.queue, ^{
            if (![self.testToken isEqual:token]) {
                return;
            }
            self.currentProbe = nil;
            if (speed.doubleValue > 0) {
                self.workingSpeeds[host] = speed;
            }
            self.workingIndex += 1;
            [self emitProgressForHost:host speed:speed error:error.localizedDescription];
            [self probeNextCandidateWithToken:token];
        });
    }];
}

- (void)emitProgressForHost:(NSString *)host speed:(NSNumber *)speed error:(NSString *)error {
    NSUInteger completed = self.workingIndex;
    NSUInteger total = [self candidates].count;
    BLCCDNSpeedProgressBlock progress = self.progressBlock;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (progress) {
            progress(completed, total, host, speed, error);
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:BLCCDNSpeedTestDidUpdateNotification object:self];
    });
}

- (void)finishTestWithError:(NSError *)error token:(NSUUID *)token {
    if (![self.testToken isEqual:token]) {
        return;
    }
    NSDictionary<NSString *, NSNumber *> *speeds = [self.workingSpeeds copy] ?: @{};
    NSArray<NSString *> *ranked = [speeds.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        NSComparisonResult result = [speeds[right] compare:speeds[left]];
        return result == NSOrderedSame ? [left compare:right] : result;
    }];
    NSArray<NSString *> *selected = [self selectedHosts];
    if (ranked.count > 0) {
        selected = [ranked subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)3, ranked.count))];
        [[NSUserDefaults standardUserDefaults] setObject:speeds forKey:BLCCDNSpeedsKey];
        [self setSelectedHosts:selected];
    } else if (!error) {
        error = BLCCDNError(-23, @"全部 CDN 测速失败");
    }
    [[NSUserDefaults standardUserDefaults] synchronize];

    BLCCDNSpeedCompletionBlock completion = self.completionBlock;
    self.testing = NO;
    self.testToken = nil;
    self.currentProbe = nil;
    self.workingSpeeds = nil;
    self.workingSampleURL = nil;
    self.progressBlock = nil;
    self.completionBlock = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:BLCCDNSpeedTestDidUpdateNotification object:self];
        if (completion) {
            completion(selected, speeds, error);
        }
    });
}

- (void)cancelSpeedTest {
    dispatch_async(self.queue, ^{
        if (!self.testing) {
            return;
        }
        NSUUID *token = self.testToken;
        [self.currentProbe cancel];
        self.testToken = nil;
        self.testing = NO;
        self.progressBlock = nil;
        BLCCDNSpeedCompletionBlock completion = self.completionBlock;
        self.completionBlock = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:BLCCDNSpeedTestDidUpdateNotification object:self];
            if (completion) {
                completion([self selectedHosts], [self lastSpeeds], BLCCDNError(NSURLErrorCancelled, @"测速已取消"));
            }
        });
        (void)token;
    });
}

- (NSString *)stringValueForKeys:(NSArray<NSString *> *)keys object:(id)object selectedKey:(NSString **)selectedKey {
    for (NSString *key in keys) {
        id value = BLCGetModelValue(object, key);
        if ([value isKindOfClass:[NSString class]]) {
            if (selectedKey) {
                *selectedKey = key;
            }
            return value;
        }
    }
    return nil;
}

- (NSArray *)arrayValueForKeys:(NSArray<NSString *> *)keys object:(id)object selectedKey:(NSString **)selectedKey {
    for (NSString *key in keys) {
        id value = BLCGetModelValue(object, key);
        if ([value isKindOfClass:[NSArray class]]) {
            if (selectedKey) {
                *selectedKey = key;
            }
            return value;
        }
    }
    return nil;
}

- (void)rewriteMediaItem:(id)item hosts:(NSArray<NSString *> *)hosts {
    if (!item || hosts.count == 0) {
        return;
    }
    NSString *baseKey = nil;
    NSString *baseURL = [self stringValueForKeys:@[@"baseURL", @"baseUrl"] object:item selectedKey:&baseKey];
    if (baseURL.length > 0 && baseKey.length > 0) {
        BLCSetModelValue(item, baseKey, BLCReplaceURLAuthority(baseURL, hosts[0]));
    }

    NSString *backupKey = nil;
    NSArray *backupURLs = [self arrayValueForKeys:@[@"backupURLArray", @"backupUrlArray", @"backupURLsArray"]
                                           object:item
                                      selectedKey:&backupKey];
    if (backupURLs.count == 0 || backupKey.length == 0) {
        return;
    }
    NSMutableArray<NSString *> *rewritten = [NSMutableArray arrayWithCapacity:backupURLs.count];
    for (NSUInteger index = 0; index < backupURLs.count; index++) {
        id value = backupURLs[index];
        if (![value isKindOfClass:[NSString class]]) {
            [rewritten addObject:value];
            continue;
        }
        NSString *host = hosts[(index + 1) % hosts.count];
        [rewritten addObject:BLCReplaceURLAuthority(value, host)];
    }
    if ([backupURLs isKindOfClass:[NSMutableArray class]]) {
        NSMutableArray *mutable = (NSMutableArray *)backupURLs;
        [mutable removeAllObjects];
        [mutable addObjectsFromArray:rewritten];
        BLCSetModelValue(item, backupKey, mutable);
    } else {
        BLCSetModelValue(item, backupKey, rewritten);
    }
}

- (void)rewritePlayViewReply:(id)reply {
    if (![self isEnabled] || !reply) {
        return;
    }
    NSString *className = NSStringFromClass([reply class]);
    if (![className containsString:@"PlayeruniteV1PlayViewUniteReply"]) {
        return;
    }
    if (!BLCModelHasMessage(reply, @"vodInfo")) {
        return;
    }
    id vodInfo = BLCGetModelValue(reply, @"vodInfo");
    NSArray<NSString *> *hosts = [self selectedHosts];
    if (!vodInfo || hosts.count == 0) {
        return;
    }

    NSArray *streamList = [self arrayValueForKeys:@[@"streamListArray", @"streamList"]
                                           object:vodInfo
                                      selectedKey:nil];
    for (id stream in streamList) {
        if (BLCModelHasMessage(stream, @"dashVideo")) {
            [self rewriteMediaItem:BLCGetModelValue(stream, @"dashVideo") hosts:hosts];
        }
        if (BLCModelHasMessage(stream, @"dashAudio")) {
            [self rewriteMediaItem:BLCGetModelValue(stream, @"dashAudio") hosts:hosts];
        }
        NSArray *streamAudio = [self arrayValueForKeys:@[@"dashAudioArray"] object:stream selectedKey:nil];
        for (id audio in streamAudio) {
            [self rewriteMediaItem:audio hosts:hosts];
        }
    }

    NSArray *dashAudio = [self arrayValueForKeys:@[@"dashAudioArray", @"dashAudio"]
                                          object:vodInfo
                                     selectedKey:nil];
    for (id audio in dashAudio) {
        [self rewriteMediaItem:audio hosts:hosts];
    }
}

@end
