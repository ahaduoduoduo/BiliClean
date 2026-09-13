#import "BLCTabManager.h"

NSString *const BLCTabConfigurationDidChangeNotification = @"BLCTabConfigurationDidChangeNotification";

static NSString *const BLCTabCachedItemsKey = @"blc.tab.cached.items";
static NSString *const BLCTabCachedResponseKey = @"blc.tab.cached.response";
static NSString *const BLCTabHiddenIDsKey = @"blc.tab.hidden.ids";
static NSString *const BLCTabKeywordsKey = @"blc.tab.keywords";
static NSString *const BLCTabUpdatedAtKey = @"blc.tab.updated.at";
static NSString *const BLCTabEndpoint = @"https://app.bilibili.com/x/resource/show/tab/v2";
static NSString *const BLCTabAlwaysHiddenName = @"新征程";

static BOOL BLCTabIsAlwaysHiddenItem(id item) {
    if (![item isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    id name = item[@"name"];
    return [name isKindOfClass:[NSString class]] && [name isEqualToString:BLCTabAlwaysHiddenName];
}

static NSString *BLCTabSearchText(id item) {
    if (![item isKindOfClass:[NSDictionary class]]) {
        return @"";
    }
    id cachedText = item[@"search_text"];
    if ([cachedText isKindOfClass:[NSString class]]) {
        return cachedText;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:item options:0 error:nil];
    NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    return text ?: [item description] ?: @"";
}

static BOOL BLCTabItemMatchesKeywords(id item, NSArray<NSString *> *keywords) {
    if (keywords.count == 0 || ![item isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    NSString *text = BLCTabSearchText(item);
    for (NSString *keyword in keywords) {
        if (keyword.length > 0 &&
            [text rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static void BLCRemoveAlwaysHiddenTabItems(id object) {
    if ([object isKindOfClass:[NSMutableArray class]]) {
        NSMutableArray *array = object;
        for (NSInteger index = (NSInteger)array.count - 1; index >= 0; index--) {
            id item = array[(NSUInteger)index];
            if (BLCTabIsAlwaysHiddenItem(item)) {
                [array removeObjectAtIndex:(NSUInteger)index];
            } else {
                BLCRemoveAlwaysHiddenTabItems(item);
            }
        }
        return;
    }
    if ([object isKindOfClass:[NSMutableDictionary class]]) {
        for (id value in [(NSMutableDictionary *)object allValues]) {
            BLCRemoveAlwaysHiddenTabItems(value);
        }
    }
}

@interface BLCTabManager ()
@property (atomic, assign) BOOL hasCapturedClientResponse;
@end

@implementation BLCTabManager

+ (instancetype)sharedManager {
    static BLCTabManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[BLCTabManager alloc] init];
    });
    return manager;
}

+ (void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        BLCTabCachedItemsKey: @[],
        BLCTabHiddenIDsKey: @[],
        BLCTabKeywordsKey: @[]
    }];
}

- (NSArray<NSString *> *)groupKeys {
    return @[@"tab", @"top", @"top_more", @"bottom"];
}

- (NSString *)groupTitle:(NSString *)group {
    NSDictionary *titles = @{
        @"tab": @"首页频道",
        @"top": @"顶部入口",
        @"top_more": @"顶部更多",
        @"bottom": @"底部导航"
    };
    return titles[group] ?: group;
}

- (void)refresh {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = 15.0;
    configuration.timeoutIntervalForResource = 15.0;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.URLCache = nil;
    configuration.HTTPCookieStorage = nil;
    configuration.HTTPShouldSetCookies = NO;
    configuration.HTTPAdditionalHeaders = @{
        @"User-Agent": @"Mozilla/5.0 BiliDroid/8.76.0 (bbcallen@gmail.com)"
    };
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSURLSessionDataTask *task = [session dataTaskWithURL:[NSURL URLWithString:BLCTabEndpoint]
                                       completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [session finishTasksAndInvalidate];
        if (error || data.length == 0) {
            return;
        }
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]]
            ? ((NSHTTPURLResponse *)response).statusCode
            : 0;
        if (status < 200 || status >= 300) {
            return;
        }
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![object isKindOfClass:[NSDictionary class]] || [object[@"code"] integerValue] != 0) {
            return;
        }
        @synchronized (self) {
            if (!self.hasCapturedClientResponse) {
                [self cacheRootDictionary:object];
            }
        }
    }];
    [task resume];
}

- (NSArray<NSDictionary<NSString *,id> *> *)cachedItems {
    id value = [[NSUserDefaults standardUserDefaults] arrayForKey:BLCTabCachedItemsKey];
    if (![value isKindOfClass:[NSArray class]]) {
        return @[];
    }
    NSArray<NSString *> *keywords = [self tabKeywords];
    return [(NSArray *)value filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id item,
                                                                                               NSDictionary *bindings) {
        return !BLCTabIsAlwaysHiddenItem(item) && !BLCTabItemMatchesKeywords(item, keywords);
    }]];
}

- (NSDate *)lastUpdatedAt {
    return [[NSUserDefaults standardUserDefaults] objectForKey:BLCTabUpdatedAtKey];
}

- (NSSet<NSString *> *)hiddenTabIDs {
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:BLCTabHiddenIDsKey];
    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    for (id value in stored) {
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
            [ids addObject:value];
        }
    }
    return ids;
}

- (BOOL)isTabVisible:(NSString *)tabID {
    return tabID.length > 0 && ![[self hiddenTabIDs] containsObject:tabID];
}

- (void)setTabID:(NSString *)tabID visible:(BOOL)visible {
    if (tabID.length == 0) {
        return;
    }
    NSMutableSet<NSString *> *hidden = [[self hiddenTabIDs] mutableCopy];
    if (visible) {
        [hidden removeObject:tabID];
    } else {
        [hidden addObject:tabID];
    }
    NSArray *stored = [[hidden allObjects] sortedArrayUsingSelector:@selector(compare:)];
    [[NSUserDefaults standardUserDefaults] setObject:stored forKey:BLCTabHiddenIDsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:BLCTabConfigurationDidChangeNotification object:self];
}

- (NSArray<NSString *> *)tabKeywords {
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:BLCTabKeywordsKey];
    if (![stored isKindOfClass:[NSArray class]]) {
        return @[];
    }
    NSMutableArray<NSString *> *keywords = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id value in stored) {
        if (![value isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *keyword = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *identity = keyword.lowercaseString;
        if (keyword.length > 0 && ![seen containsObject:identity]) {
            [seen addObject:identity];
            [keywords addObject:keyword];
        }
    }
    return keywords;
}

- (void)setTabKeywords:(NSArray<NSString *> *)keywords {
    NSMutableArray<NSString *> *cleaned = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id value in keywords) {
        if (![value isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *keyword = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *identity = keyword.lowercaseString;
        if (keyword.length > 0 && ![seen containsObject:identity]) {
            [seen addObject:identity];
            [cleaned addObject:keyword];
        }
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:cleaned forKey:BLCTabKeywordsKey];
    [defaults synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:BLCTabConfigurationDidChangeNotification object:self];
}

- (NSUInteger)totalItemCount {
    return [self cachedItems].count;
}

- (NSUInteger)visibleItemCount {
    NSUInteger count = 0;
    for (NSDictionary *item in [self cachedItems]) {
        if ([self isTabVisible:item[@"tab_id"]]) {
            count += 1;
        }
    }
    return count;
}

- (void)cacheRootDictionary:(NSDictionary *)root {
    NSDictionary *data = [root[@"data"] isKindOfClass:[NSDictionary class]] ? root[@"data"] : nil;
    if (!data) {
        return;
    }
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    BOOL hasPublishItem = NO;
    for (NSString *group in [self groupKeys]) {
        NSArray *array = [data[group] isKindOfClass:[NSArray class]] ? data[group] : nil;
        for (NSDictionary *item in array) {
            if (![item isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            if (BLCTabIsAlwaysHiddenItem(item)) {
                continue;
            }
            NSString *tabID = [item[@"tab_id"] isKindOfClass:[NSString class]] ? item[@"tab_id"] : nil;
            if (tabID.length == 0) {
                continue;
            }
            if ([group isEqualToString:@"bottom"] && [tabID isEqualToString:@"publish"]) {
                hasPublishItem = YES;
            }
            NSString *name = [item[@"name"] isKindOfClass:[NSString class]] ? item[@"name"] : tabID;
            NSNumber *position = [item[@"pos"] isKindOfClass:[NSNumber class]] ? item[@"pos"] : @0;
            [items addObject:@{
                @"group": group,
                @"group_name": [self groupTitle:group],
                @"tab_id": tabID,
                @"name": name ?: tabID,
                @"pos": position,
                @"search_text": BLCTabSearchText(item)
            }];
        }
    }
    if (!hasPublishItem) {
        [items addObject:@{
            @"group": @"bottom",
            @"group_name": [self groupTitle:@"bottom"],
            @"tab_id": @"publish",
            @"name": @"发布",
            @"pos": @3,
            @"search_text": @"{\"tab_id\":\"publish\",\"name\":\"发布\"}"
        }];
    }
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSUInteger leftGroup = [[self groupKeys] indexOfObject:left[@"group"]];
        NSUInteger rightGroup = [[self groupKeys] indexOfObject:right[@"group"]];
        if (leftGroup != rightGroup) {
            return leftGroup < rightGroup ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left[@"pos"] compare:right[@"pos"]];
    }];

    NSData *snapshot = [NSJSONSerialization dataWithJSONObject:root options:0 error:nil];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:items forKey:BLCTabCachedItemsKey];
    if (snapshot) {
        [defaults setObject:snapshot forKey:BLCTabCachedResponseKey];
    }
    [defaults setObject:[NSDate date] forKey:BLCTabUpdatedAtKey];
    [defaults synchronize];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:BLCTabConfigurationDidChangeNotification object:self];
    });
}

- (void)captureAndFilterResponseDictionary:(NSMutableDictionary *)root
                                 URLString:(NSString *)URLString {
    if (![URLString containsString:@"/x/resource/show/tab/v2"]) {
        return;
    }
    id code = root[@"code"];
    if (![code respondsToSelector:@selector(integerValue)] || [code integerValue] != 0) {
        return;
    }
    id dataValue = root[@"data"];
    if (![dataValue isKindOfClass:[NSMutableDictionary class]]) {
        return;
    }
    @synchronized (self) {
        self.hasCapturedClientResponse = YES;
        [self cacheRootDictionary:[root copy]];
    }
    NSMutableDictionary *data = dataValue;
    BLCRemoveAlwaysHiddenTabItems(data);
    NSSet<NSString *> *hidden = [self hiddenTabIDs];
    NSArray<NSString *> *keywords = [self tabKeywords];
    for (NSString *group in [self groupKeys]) {
        id arrayValue = data[group];
        if (![arrayValue isKindOfClass:[NSArray class]]) {
            continue;
        }
        NSMutableArray *kept = [NSMutableArray array];
        for (id item in (NSArray *)arrayValue) {
            if (![item isKindOfClass:[NSDictionary class]]) {
                [kept addObject:item];
                continue;
            }
            if (BLCTabItemMatchesKeywords(item, keywords)) {
                continue;
            }
            NSString *tabID = [item[@"tab_id"] isKindOfClass:[NSString class]] ? item[@"tab_id"] : nil;
            if (tabID.length == 0 || ![hidden containsObject:tabID]) {
                [kept addObject:item];
            }
        }
        if ([arrayValue isKindOfClass:[NSMutableArray class]]) {
            [(NSMutableArray *)arrayValue removeAllObjects];
            [(NSMutableArray *)arrayValue addObjectsFromArray:kept];
        } else {
            data[group] = kept;
        }
    }
}

@end
