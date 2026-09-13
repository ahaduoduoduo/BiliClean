#import "BLCDownloadModel.h"
#import <objc/runtime.h>
#import <objc/message.h>

@implementation BLCDownloadMedia
- (instancetype)init { if ((self = [super init])) _URLs = @[]; return self; }
@end
@implementation BLCDownloadPlan
@end

id BLCDownloadValue(id object, NSString *key) {
    if (!object) return nil;
    @try { return [object valueForKey:key]; } @catch (__unused NSException *e) { return nil; }
}
BOOL BLCDownloadSet(id object, NSString *key, id value) {
    @try { [object setValue:value forKey:key]; return YES; } @catch (__unused NSException *e) { return NO; }
}
BOOL BLCDownloadHas(id object, NSString *key) {
    NSString *has = [@"has" stringByAppendingString:[key stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:[[key substringToIndex:1] uppercaseString]]];
    SEL selector = NSSelectorFromString(has);
    return [object respondsToSelector:selector] && ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
}
NSError *BLCDownloadError(NSString *message) {
    return [NSError errorWithDomain:@"com.imlr.biliclean.download" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}
static NSString *BLCQuality(NSInteger q) {
    return @{@16:@"360P", @32:@"480P", @64:@"720P", @74:@"720P60", @80:@"1080P", @112:@"1080P+", @116:@"1080P60", @120:@"4K", @127:@"8K"}[@(q)] ?: @"SDR";
}
BLCDownloadPlan *BLCDownloadSelect(NSArray<BLCDownloadMedia *> *videos, NSArray<BLCDownloadMedia *> *audios) {
    NSMutableArray<BLCDownloadMedia *> *valid = [NSMutableArray array];
    for (BLCDownloadMedia *v in videos) {
        // Request flags also exclude HDR/DV; only known ordinary quality tiers are eligible.
        if (![@[@16,@32,@64,@74,@80,@112,@116,@120,@127] containsObject:@(v.identifier)]) continue;
        if (!v.intact || v.encrypted || !v.URLs.count || ![@[@7,@12] containsObject:@(v.codec)]) continue;
        [valid addObject:v];
    }
    [valid sortUsingComparator:^NSComparisonResult(BLCDownloadMedia *a, BLCDownloadMedia *b) {
        int64_t aa = (int64_t)a.width * a.height, ba = (int64_t)b.width * b.height;
        if (aa != ba) return aa > ba ? NSOrderedAscending : NSOrderedDescending;
        if (a.fps != b.fps) return a.fps > b.fps ? NSOrderedAscending : NSOrderedDescending;
        if (a.identifier != b.identifier) return a.identifier > b.identifier ? NSOrderedAscending : NSOrderedDescending;
        if (a.codec != b.codec) return a.codec == 7 ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];
    BLCDownloadMedia *video = valid.firstObject, *audio = nil;
    if (!video) return nil;
    for (BLCDownloadMedia *a in audios) {
        if (a.encrypted || !a.URLs.count || ![@[@30216,@30232,@30280] containsObject:@(a.identifier)]) continue;
        if (!audio || a.identifier == video.audioID || (audio.identifier != video.audioID && a.bandwidth > audio.bandwidth)) audio = a;
    }
    if (!audio) return nil;
    BLCDownloadPlan *plan = [BLCDownloadPlan new]; plan.video = video; plan.audio = audio; plan.quality = BLCQuality(video.identifier);
    return plan;
}
BOOL BLCDownloadCompleteRange(NSInteger status, NSString *range, int64_t actual, int64_t expected) {
    if (actual <= 0 || (expected > 0 && actual != expected)) return NO;
    if (status == 200) return YES;
    if (status != 206 || !range.length) return NO;
    NSScanner *scanner = [NSScanner scannerWithString:range];
    long long start = -1, end = -1, total = -1;
    return [scanner scanString:@"bytes" intoString:NULL] && [scanner scanLongLong:&start] &&
        [scanner scanString:@"-" intoString:NULL] && [scanner scanLongLong:&end] &&
        [scanner scanString:@"/" intoString:NULL] && [scanner scanLongLong:&total] && scanner.isAtEnd &&
        start == 0 && end >= 0 && end < LLONG_MAX && end + 1 == actual && total == actual;
}
static BLCDownloadMedia *BLCReadMedia(id object) {
    BLCDownloadMedia *m = [BLCDownloadMedia new];
    NSMutableOrderedSet *URLs = [NSMutableOrderedSet orderedSet];
    NSMutableArray *strings = [NSMutableArray array];
    id base = BLCDownloadValue(object, @"baseURL"); if ([base isKindOfClass:NSString.class]) [strings addObject:base];
    id backups = BLCDownloadValue(object, @"backupURLArray"); if ([backups isKindOfClass:NSArray.class]) [strings addObjectsFromArray:backups];
    for (id value in strings) {
        if (![value isKindOfClass:NSString.class]) continue;
        NSURL *url = [NSURL URLWithString:value];
        if (url.host.length && [@[@"http",@"https"] containsObject:url.scheme.lowercaseString]) [URLs addObject:url];
    }
    m.URLs = URLs.array; m.size = [BLCDownloadValue(object, @"size") longLongValue];
    m.codec = [BLCDownloadValue(object, @"codecid") integerValue];
    m.audioID = [BLCDownloadValue(object, @"audioId") integerValue];
    m.width = [BLCDownloadValue(object, @"width") integerValue]; m.height = [BLCDownloadValue(object, @"height") integerValue];
    m.bandwidth = [BLCDownloadValue(object, @"bandwidth") integerValue];
    NSString *rate = BLCDownloadValue(object, @"frameRate");
    NSArray *ratio = [rate isKindOfClass:NSString.class] ? [rate componentsSeparatedByString:@"/"] : @[];
    m.fps = [ratio.firstObject doubleValue]; if (ratio.count == 2 && [ratio[1] doubleValue] > 0) m.fps /= [ratio[1] doubleValue];
    m.encrypted = [BLCDownloadValue(object, @"widevinePssh") length] > 0 || [BLCDownloadValue(object, @"bilidrmUri") length] > 0;
    return m;
}
static const char BLCPlanKey;
static BLCDownloadPlan *BLCReadReply(id reply) {
    if (![NSStringFromClass([reply class]) isEqualToString:@"BAPIAppPlayeruniteV1PlayViewUniteReply"] || !BLCDownloadHas(reply, @"vodInfo") || !BLCDownloadHas(reply, @"playArc")) return nil;
    id arc = BLCDownloadValue(reply, @"playArc");
    if ([BLCDownloadValue(arc, @"isPreview") boolValue] || [BLCDownloadValue(arc, @"drmTechType") integerValue] != 0 || [BLCDownloadValue(arc, @"videoType") integerValue] != 1) return nil;
    id vod = BLCDownloadValue(reply, @"vodInfo"); NSMutableArray *videos = [NSMutableArray array], *audios = [NSMutableArray array];
    for (id stream in BLCDownloadValue(vod, @"streamListArray")) {
        // oneof has no hasDashVideo getter. Reading another member creates it.
        if ([BLCDownloadValue(stream, @"contentOneOfCase") integerValue] != 2 || !BLCDownloadHas(stream, @"streamInfo")) continue;
        id info = BLCDownloadValue(stream, @"streamInfo");
        BLCDownloadMedia *m = BLCReadMedia(BLCDownloadValue(stream, @"dashVideo"));
        m.identifier = [BLCDownloadValue(info, @"quality") integerValue]; m.intact = [BLCDownloadValue(info, @"intact") boolValue]; [videos addObject:m];
    }
    for (id audio in BLCDownloadValue(vod, @"dashAudioArray")) {
        BLCDownloadMedia *m = BLCReadMedia(audio); m.identifier = [BLCDownloadValue(audio, @"id_p") integerValue]; [audios addObject:m];
    }
    BLCDownloadPlan *p = BLCDownloadSelect(videos, audios);
    p.aid = [BLCDownloadValue(arc, @"aid") longLongValue]; p.cid = [BLCDownloadValue(arc, @"cid") longLongValue];
    p.duration = [BLCDownloadValue(vod, @"timelength") doubleValue] / 1000;
    return p.duration > 0 && p.aid > 0 && p.cid > 0 ? p : nil;
}
void BLCDownloadCaptureReply(id reply) {
    if (!reply || objc_getAssociatedObject(reply, &BLCPlanKey)) return;
    if (![NSStringFromClass([reply class]) isEqualToString:@"BAPIAppPlayeruniteV1PlayViewUniteReply"]) return;
    objc_setAssociatedObject(reply, &BLCPlanKey, BLCReadReply(reply) ?: NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
BLCDownloadPlan *BLCDownloadReplyPlan(id reply) {
    id plan = objc_getAssociatedObject(reply, &BLCPlanKey);
    return plan ? (plan == NSNull.null ? nil : plan) : BLCReadReply(reply);
}
