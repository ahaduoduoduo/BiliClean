#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>
#import "BLCCDNManager.h"
#import "BLCTabManager.h"
#import "BLCFeatureSettingsViewControllers.h"
#import "Download/BLCVideoDownloadManager.h"

static NSString *const BLCLogPrefix = @"[BiliClean]";

static NSString *const BLCMasterEnabledKey = @"blc.master.enabled";
static NSString *const BLCSponsorSkipEnabledKey = @"blc.sponsor.enabled";
static NSString *const BLCSponsorSkipOnceEnabledKey = @"blc.sponsor.skip.once.enabled";
static NSString *const BLCSkipAdvanceKey = @"blc.sponsor.advance";
static NSString *const BLCPlaybackRateEnabledKey = @"blc.playback.enabled";
static NSString *const BLCDefaultPlaybackRateKey = @"blc.playback.default";
static NSString *const BLCAdBlockEnabledKey = @"blc.ad.enabled";
static NSString *const BLCKeywordBlockEnabledKey = @"blc.keyword.enabled";
static NSString *const BLCKeywordRulesKey = @"blc.keyword.rules";
static NSString *const BLCVerticalBlockEnabledKey = @"blc.vertical.enabled";
static NSString *const BLCPruneFeedReasonEnabledKey = @"blc.prune.feed.reason.enabled";
static NSString *const BLCPruneFeedPictureEnabledKey = @"blc.prune.feed.picture.enabled";
static NSString *const BLCPlayerAdStripBlockEnabledKey = @"blc.player.ad.strip.enabled";
static NSString *const BLCPruneMerchandiseModuleEnabledKey = @"blc.prune.merchandise.module.enabled";
static NSString *const BLCPruneCommentCommerceEnabledKey = @"blc.prune.comment.commerce.enabled";
static NSString *const BLCPlayerRelatedAdBlockEnabledKey = @"blc.player.related.ad.enabled";
static NSString *const BLCPlayerEndPageAdBlockEnabledKey = @"blc.player.endpage.ad.enabled";
static NSString *const BLCPlayerFloatingBlockEnabledKey = @"blc.player.floating.enabled";
static NSString *const BLCPruneHomeLiveEnabledKey = @"blc.prune.home.live.enabled";
static NSString *const BLCPruneDynamicUpAdEnabledKey = @"blc.prune.dynamic.up.ad.enabled";
static NSString *const BLCPruneDynamicOnlyFansEnabledKey = @"blc.prune.dynamic.onlyfans.enabled";
static NSString *const BLCPruneDynamicLiveRcmdEnabledKey = @"blc.prune.dynamic.live.rcmd.enabled";
static NSString *const BLCPruneUnusedServicesEnabledKey = @"blc.prune.mine.enabled";
static NSString *const BLCDebugEnabledKey = @"blc.debug.enabled";

static const NSUInteger BLCDebugJSONBodyLimit = 1024 * 1024;
static const NSUInteger BLCDebugModelBodyLimit = 2 * 1024 * 1024;

static NSString *const BLCRuleTextKey = @"text";
static NSString *const BLCRuleRegexKey = @"regex";
static NSString *const BLCRuleScopesKey = @"scopes";
static NSString *const BLCKeywordScopeRecommend = @"recommend";
static NSString *const BLCKeywordScopeDynamic = @"dynamic";
static NSString *const BLCKeywordScopeComment = @"comment";

static NSString *const BLCAlphabet = @"FcwAPNKTMug3GV5Lj7EJnHpWsx4tb8haYeviqBz6rkCy12mUSDQX9RdoZf";
static const long long BLCXorCode = 23442827791579LL;
static const long long BLCMaxAid = 1LL << 51;
static const int BLCEncodeMap[] = {8, 7, 0, 5, 1, 3, 2, 4, 6};

static NSArray<NSNumber *> *BLCDefaultPlaybackRateOptions(void) {
    return @[@0.5, @0.75, @1.0, @1.25, @1.5, @2.0, @3.0];
}

static NSArray<NSNumber *> *BLCPlayerPlaybackRateOptions(void) {
    return @[@0.5, @1.0, @1.25, @1.5, @2.0, @3.0];
}

@interface BLCSettings : NSObject
+ (void)registerDefaults;
+ (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;
+ (double)doubleForKey:(NSString *)key defaultValue:(double)defaultValue;
+ (void)setDouble:(double)value forKey:(NSString *)key;
+ (NSArray<NSDictionary *> *)keywordRules;
+ (void)setKeywordRules:(NSArray<NSDictionary *> *)rules;
+ (BOOL)masterEnabled;
+ (BOOL)featureEnabled:(NSString *)key defaultValue:(BOOL)defaultValue;
@end

@implementation BLCSettings

+ (void)registerDefaults {
    NSDictionary *defaults = @{
        BLCMasterEnabledKey: @YES,
        BLCSponsorSkipEnabledKey: @YES,
        BLCSponsorSkipOnceEnabledKey: @NO,
        BLCSkipAdvanceKey: @0.25,
        BLCPlaybackRateEnabledKey: @YES,
        BLCDefaultPlaybackRateKey: @1.0,
        BLCAdBlockEnabledKey: @YES,
        BLCKeywordBlockEnabledKey: @YES,
        BLCKeywordRulesKey: @[],
        BLCVerticalBlockEnabledKey: @YES,
        BLCPruneFeedReasonEnabledKey: @YES,
        BLCPruneFeedPictureEnabledKey: @YES,
        BLCPlayerAdStripBlockEnabledKey: @YES,
        BLCPruneMerchandiseModuleEnabledKey: @YES,
        BLCPruneCommentCommerceEnabledKey: @YES,
        BLCPlayerRelatedAdBlockEnabledKey: @YES,
        BLCPlayerEndPageAdBlockEnabledKey: @YES,
        BLCPlayerFloatingBlockEnabledKey: @YES,
        BLCPruneHomeLiveEnabledKey: @YES,
        BLCPruneDynamicUpAdEnabledKey: @YES,
        BLCPruneDynamicOnlyFansEnabledKey: @YES,
        BLCPruneDynamicLiveRcmdEnabledKey: @YES,
        BLCPruneUnusedServicesEnabledKey: @YES,
        BLCDebugEnabledKey: @NO
    };
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
}

+ (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (!value) {
        return defaultValue;
    }
    return [value boolValue];
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (double)doubleForKey:(NSString *)key defaultValue:(double)defaultValue {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (!value) {
        return defaultValue;
    }
    return [value doubleValue];
}

+ (void)setDouble:(double)value forKey:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setDouble:value forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSArray<NSDictionary *> *)keywordRules {
    id rules = [[NSUserDefaults standardUserDefaults] objectForKey:BLCKeywordRulesKey];
    if (![rules isKindOfClass:[NSArray class]]) {
        return @[];
    }
    return rules;
}

+ (void)setKeywordRules:(NSArray<NSDictionary *> *)rules {
    [[NSUserDefaults standardUserDefaults] setObject:rules ?: @[] forKey:BLCKeywordRulesKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)masterEnabled {
    return [self boolForKey:BLCMasterEnabledKey defaultValue:YES];
}

+ (BOOL)featureEnabled:(NSString *)key defaultValue:(BOOL)defaultValue {
    return [self masterEnabled] && [self boolForKey:key defaultValue:defaultValue];
}

@end

static NSString *BLCStringValue(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        return [value stringValue];
    }
    return nil;
}

static NSString *BLCFullPathForURL(NSURL *URL) {
    if (!URL) {
        return @"";
    }
    NSURLComponents *components = [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO];
    components.query = nil;
    components.fragment = nil;
    return components.URL.absoluteString ?: URL.absoluteString ?: @"";
}

static BOOL BLCTextContains(NSString *text, NSString *needle) {
    if (text.length == 0 || needle.length == 0) {
        return NO;
    }
    return [text rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static NSString *BLCTextFromObject(id object, NSUInteger depth) {
    if (!object || depth > 8) {
        return @"";
    }
    if ([object isKindOfClass:[NSString class]]) {
        return object;
    }
    if ([object isKindOfClass:[NSNumber class]]) {
        return [object stringValue];
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = object;
        for (id key in dict) {
            NSString *keyText = [key isKindOfClass:[NSString class]] ? key : nil;
            if ([keyText hasSuffix:@"url"] || [keyText hasSuffix:@"URL"] || [keyText isEqualToString:@"uri"]) {
                continue;
            }
            NSString *text = BLCTextFromObject(dict[key], depth + 1);
            if (text.length > 0) {
                [parts addObject:text];
            }
        }
    } else if ([object isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)object) {
            NSString *text = BLCTextFromObject(item, depth + 1);
            if (text.length > 0) {
                [parts addObject:text];
            }
        }
    } else if ([object respondsToSelector:@selector(description)]) {
        return [object description] ?: @"";
    }
    return [parts componentsJoinedByString:@" "];
}

static NSArray<NSString *> *BLCKeywordScopeIDs(void) {
    return @[BLCKeywordScopeRecommend, BLCKeywordScopeDynamic, BLCKeywordScopeComment];
}

static NSArray<NSString *> *BLCKeywordScopeTitles(void) {
    return @[@"推荐", @"动态", @"评论区"];
}

static NSArray<NSString *> *BLCKeywordScopesForRule(NSDictionary *rule) {
    id scopes = rule[BLCRuleScopesKey];
    if ([scopes isKindOfClass:[NSArray class]]) {
        return scopes;
    }
    return BLCKeywordScopeIDs();
}

static BOOL BLCKeywordRuleAppliesToScope(NSDictionary *rule, NSString *scope) {
    if (scope.length == 0) {
        return YES;
    }
    NSArray<NSString *> *scopes = BLCKeywordScopesForRule(rule);
    return [scopes containsObject:scope];
}

static NSArray<NSDictionary *> *BLCKeywordRulesForScope(NSArray<NSDictionary *> *rules, NSString *scope) {
    if (scope.length == 0) {
        return rules ?: @[];
    }
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (NSDictionary *rule in rules) {
        if (![rule isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        if (BLCKeywordRuleAppliesToScope(rule, scope)) {
            [items addObject:rule];
        }
    }
    return items;
}

static NSString *BLCKeywordScopeSummaryForRule(NSDictionary *rule) {
    NSArray<NSString *> *ids = BLCKeywordScopeIDs();
    NSArray<NSString *> *titles = BLCKeywordScopeTitles();
    NSArray<NSString *> *scopes = BLCKeywordScopesForRule(rule);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSUInteger i = 0; i < ids.count; i++) {
        if ([scopes containsObject:ids[i]]) {
            [names addObject:titles[i]];
        }
    }
    return names.count > 0 ? [names componentsJoinedByString:@"、"] : @"未启用";
}

static BOOL BLCTextMatchesKeywordRuleList(NSString *text, NSArray<NSDictionary *> *rules) {
    if (text.length == 0) {
        return NO;
    }
    for (NSDictionary *rule in rules) {
        if (![rule isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *pattern = BLCStringValue(rule[BLCRuleTextKey]);
        if (pattern.length == 0) {
            continue;
        }
        BOOL isRegex = [rule[BLCRuleRegexKey] boolValue];
        if (isRegex) {
            NSError *error = nil;
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
            if (!error && [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) {
                return YES;
            }
        } else if ([text rangeOfString:pattern options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static BOOL BLCTextMatchesKeywordRulesForScope(NSString *text, NSString *scope) {
    if (![BLCSettings featureEnabled:BLCKeywordBlockEnabledKey defaultValue:YES]) {
        return NO;
    }
    NSArray<NSDictionary *> *rules = BLCKeywordRulesForScope([BLCSettings keywordRules], scope);
    return BLCTextMatchesKeywordRuleList(text, rules);
}

@interface BLCDebugServer : NSObject
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) int serverSocket;
@property (nonatomic, assign) NSUInteger port;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *clients;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *propertySummaries;
+ (instancetype)sharedServer;
- (void)start;
- (void)stop;
- (NSString *)addressString;
- (void)emitJSONData:(NSData *)data URL:(NSURL *)URL;
- (void)emitModel:(id)model;
@end

@implementation BLCDebugServer

+ (instancetype)sharedServer {
    static BLCDebugServer *server = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        server = [[BLCDebugServer alloc] init];
    });
    return server;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _serverSocket = -1;
        _port = 8765;
        _clients = [NSMutableArray array];
        _queue = dispatch_queue_create("com.biliclean.debug.server", DISPATCH_QUEUE_SERIAL);
        _propertySummaries = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)localIPAddress {
    struct ifaddrs *interfaces = NULL;
    NSString *address = @"127.0.0.1";
    if (getifaddrs(&interfaces) == 0) {
        for (struct ifaddrs *cursor = interfaces; cursor != NULL; cursor = cursor->ifa_next) {
            if (!cursor->ifa_addr || cursor->ifa_addr->sa_family != AF_INET) {
                continue;
            }
            NSString *name = [NSString stringWithUTF8String:cursor->ifa_name];
            if (![name isEqualToString:@"en0"]) {
                continue;
            }
            char buffer[INET_ADDRSTRLEN] = {0};
            struct sockaddr_in *addr = (struct sockaddr_in *)cursor->ifa_addr;
            if (inet_ntop(AF_INET, &(addr->sin_addr), buffer, sizeof(buffer))) {
                address = [NSString stringWithUTF8String:buffer];
                break;
            }
        }
    }
    if (interfaces) {
        freeifaddrs(interfaces);
    }
    return address;
}

- (NSString *)addressString {
    if (!self.running) {
        return @"未启动";
    }
    return [NSString stringWithFormat:@"http://%@:%lu", [self localIPAddress], (unsigned long)self.port];
}

- (BOOL)bindServerSocket {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        return NO;
    }
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    for (NSUInteger port = 8765; port <= 8799; port++) {
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_len = sizeof(addr);
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_ANY);
        addr.sin_port = htons((uint16_t)port);
        if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0 && listen(fd, 8) == 0) {
            self.serverSocket = fd;
            self.port = port;
            return YES;
        }
    }
    close(fd);
    return NO;
}

- (void)start {
    if (self.running) {
        return;
    }
    if (![self bindServerSocket]) {
        NSLog(@"%@ debug server bind failed", BLCLogPrefix);
        return;
    }
    self.running = YES;
    __weak typeof(self) weakSelf = self;
    [NSThread detachNewThreadWithBlock:^{
        [weakSelf acceptLoop];
    }];
    NSLog(@"%@ debug server started %@", BLCLogPrefix, [self addressString]);
}

- (void)stop {
    if (!self.running) {
        return;
    }
    self.running = NO;
    if (self.serverSocket >= 0) {
        close(self.serverSocket);
        self.serverSocket = -1;
    }
    dispatch_sync(self.queue, ^{
        for (NSNumber *client in self.clients) {
            close(client.intValue);
        }
        [self.clients removeAllObjects];
    });
}

- (void)acceptLoop {
    while (self.running && self.serverSocket >= 0) {
        int client = accept(self.serverSocket, NULL, NULL);
        if (client < 0) {
            if (errno == EBADF || errno == EINVAL) {
                break;
            }
            continue;
        }
        [self handleClient:client];
    }
}

- (NSString *)htmlPage {
    return @"<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
    "<title>BiliClean Debug</title><style>"
    ":root{color-scheme:dark;--bg:#0f1115;--panel:#171a21;--line:#2a2f3a;--text:#e8ecf3;--muted:#8c95a6;--accent:#67d4ff;}"
    "*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px -apple-system,BlinkMacSystemFont,'SF Pro Text',sans-serif;}"
    "button{background:#202632;color:var(--text);border:1px solid var(--line);border-radius:7px;padding:7px 10px;cursor:pointer}button:hover{border-color:#3b4658}"
    "header{min-height:56px;display:flex;gap:10px;align-items:center;padding:8px 14px;border-bottom:1px solid var(--line);background:#11141a;position:sticky;top:0;z-index:2}"
    "h1{font-size:16px;margin:0;font-weight:700;white-space:nowrap}input{flex:1;background:#0b0d11;color:var(--text);border:1px solid var(--line);border-radius:8px;padding:10px 12px;outline:none}"
    "main{display:grid;grid-template-columns:360px 1fr;height:calc(100vh - 56px)}#list{border-right:1px solid var(--line);overflow:auto;background:#11141a}"
    ".item{padding:12px 14px;border-bottom:1px solid var(--line);cursor:pointer}.item:hover,.item.active{background:#1c2330}.meta{display:flex;gap:8px;color:var(--muted);font-size:12px;margin-bottom:6px}.type{color:var(--accent);font-weight:700}.title{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}"
    "#detail{overflow:auto;padding:18px}.empty{color:var(--muted);padding:24px}.toolbar{display:flex;gap:8px;align-items:center;margin-bottom:12px;flex-wrap:wrap}.pill{color:var(--muted);font-size:12px}"
    "pre,.tree{margin:0;white-space:pre-wrap;word-break:break-word;line-height:1.45;background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:14px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:13px}.props{margin-bottom:12px;color:#c8d3e4}.node{display:block;margin-left:22px}.key{color:#9cdcfe}.str{color:#ce9178}.num{color:#b5cea8}.bool{color:#569cd6}.fold{font-size:11px;padding:2px 6px;margin-left:8px}.collapsed{color:var(--muted)}.protoRoot{color:#c8d3e4;margin-bottom:6px}.actions{display:inline-flex;gap:4px;margin-left:8px;vertical-align:middle}.actions button,.valueToggle{font-size:11px;padding:2px 6px}.path{color:#6f7b8e;font-size:11px;margin-left:8px}.valueMeta{color:#6f7b8e;font-size:11px;margin-left:6px}.valueToggle{margin-left:8px}"
    "@media(max-width:800px){main{grid-template-columns:1fr}#list{height:42vh;border-right:0;border-bottom:1px solid var(--line)}#detail{height:calc(58vh - 56px)}}"
    "</style></head><body><header><h1>BiliClean Debug</h1><input id='q' placeholder='搜索 URL、model、JSON / Protobuf 内容'><button id='clearHidden'>清除隐藏</button><button id='clearFields'>清除折叠</button><span id='stat' class='pill'></span></header>"
    "<main><section id='list'></section><section id='detail'><div class='empty'>等待 JSON / Protobuf 数据</div></section></main>"
    "<script>"
    "const list=document.getElementById('list'),detail=document.getElementById('detail'),q=document.getElementById('q'),stat=document.getElementById('stat');"
    "let rows=[],active=-1,hidden=new Set(JSON.parse(localStorage.blcHidden||'[]')),folds=new Set(JSON.parse(localStorage.blcFolds||'[]')),pathFolds=new Set(JSON.parse(localStorage.blcPathFolds||'[]')),autoFoldEmpty=localStorage.blcAutoFoldEmpty==='1';const longValueLimit=240;"
    "function save(){localStorage.blcHidden=JSON.stringify([...hidden]);localStorage.blcFolds=JSON.stringify([...folds]);localStorage.blcPathFolds=JSON.stringify([...pathFolds]);localStorage.blcAutoFoldEmpty=autoFoldEmpty?'1':'0'}"
    "function text(r){return [r.type,r.title,r.properties,r.body].join(' ').toLowerCase()}"
    "function render(){const f=q.value.toLowerCase();list.innerHTML='';stat.textContent=`隐藏 ${hidden.size} / 字段 ${folds.size} / 路径 ${pathFolds.size}${autoFoldEmpty?' / 空字段':''}`;rows.forEach((r,i)=>{if(hidden.has(r.title))return;if(f&&!text(r).includes(f))return;const el=document.createElement('div');el.className='item'+(i===active?' active':'');el.innerHTML=`<div class='meta'><span class='type'>${r.type}</span><span>${r.time}</span><span>${r.size||''}</span></div><div class='title'></div>`;el.querySelector('.title').textContent=r.title;el.onclick=()=>{active=i;show(i);render()};list.appendChild(el)})}"
    "function show(i){const r=rows[i];if(!r)return;const parsed=parseBody(r.body,r.type);detail.innerHTML='';const bar=document.createElement('div');bar.className='toolbar';bar.innerHTML=`<button id='hideThis'>隐藏此 URL/model</button><button id='autoEmpty'>${autoFoldEmpty?'显示空字段':'折叠空字段'}</button><span class='pill'></span>`;bar.querySelector('.pill').textContent=r.title;detail.appendChild(bar);bar.querySelector('#hideThis').onclick=()=>{hidden.add(r.title);rows=rows.filter(x=>x.title!==r.title);active=-1;save();detail.innerHTML='<div class=empty>已隐藏，后续同名事件不再显示</div>';render()};bar.querySelector('#autoEmpty').onclick=()=>{autoFoldEmpty=!autoFoldEmpty;save();show(active);render()};if(r.properties){const props=document.createElement('pre');props.className='props';props.textContent=r.properties;detail.appendChild(props)}if(parsed.ok){const wrap=document.createElement('div');wrap.className='tree';wrap.appendChild(parsed.type==='proto'?protoNode(parsed.value):node(parsed.value,null,''));detail.appendChild(wrap)}else{const pre=document.createElement('pre');pre.textContent=r.body||'';detail.appendChild(pre)}}"
    "function parseBody(s,t){const j=parseJsonText(s);if(j.ok)return {ok:true,type:'json',value:j.value};if(String(t||'').toLowerCase()==='json')return {ok:false,value:null};const proto=parseProtoText(s);return proto?{ok:true,type:'proto',value:proto}:{ok:false,value:null}}"
    "function parseJsonText(s){const text=String(s||'');try{return {ok:true,value:JSON.parse(text)}}catch(e){}const ps=[text.indexOf('{'),text.indexOf('[')].filter(x=>x>=0).sort((a,b)=>a-b);if(ps.length){try{return {ok:true,value:JSON.parse(text.slice(ps[0]))}}catch(e){}}return {ok:false,value:null}}"
    "function parseProtoText(s){const text=String(s||'');const trimmed=text.trimStart();if(!text||trimmed[0]==='{'||trimmed[0]==='['||/^\\s*\"[^\"\\n]+\"\\s*:/m.test(text))return null;if(!/[\\w.]+\\s*\\{|[\\w.]+\\s*:/.test(text))return null;const lines=text.split(/\\r?\\n/);let root={name:'protobuf',children:[]},start=0;const first=(lines[0]||'').trim();const m=first.match(/^<([^>]+)>:\\s*\\{\\s*$/);if(m){root.name=m[1].split(/\\s+/)[0];start=1}else if(first==='{'){start=1}const stack=[root];for(let i=start;i<lines.length;i++){let line=lines[i].trim();if(!line)continue;if(line==='}'||line==='};'){if(stack.length>1)stack.pop();continue}let open=line.match(/^([^:{}][^{}:]*)\\{\\s*$/);if(open){const name=open[1].trim();const child={name,children:[]};stack[stack.length-1].children.push(child);stack.push(child);continue}let scalar=line.match(/^([^:{}][^:]*):\\s*(.*)$/);if(scalar){stack[stack.length-1].children.push({name:scalar[1].trim(),value:scalar[2]});continue}if(line==='... truncated'||line==='... truncated…'){stack[stack.length-1].children.push({name:'truncated',value:line});continue}if(line[0]==='#'){stack[stack.length-1].children.push({name:'comment',value:line});continue}}return root.children.length?root:null}"
    "function node(v,k,path){const root=document.createElement('div');const hasKey=k!==null&&k!==undefined;const cur=path||(hasKey?k:'');const isObj=v&&typeof v==='object';const isArr=Array.isArray(v);const empty=isObj&&Object.keys(v).length===0;const fieldFold=hasKey&&folds.has(k),pathFold=hasKey&&pathFolds.has(cur),emptyFold=hasKey&&autoFoldEmpty&&empty;if(hasKey&&(fieldFold||pathFold||emptyFold)){root.innerHTML=`<span class='key'>${esc(k)}</span>: <span class='collapsed'>${summary(v)}</span><span class='path'>${esc(cur)}</span>`;root.appendChild(actions(k,cur,fieldFold,pathFold,emptyFold));return root}if(isObj){const head=document.createElement('div');head.innerHTML=(hasKey?`<span class='key'>${esc(k)}</span>: `:'')+(isArr?'[':'{')+(hasKey?`<span class='path'>${esc(cur)}</span>`:'');if(hasKey)head.appendChild(actions(k,cur,false,false,false));root.appendChild(head);Object.keys(v).forEach(key=>{const childPath=isArr?(cur?cur+'[]':'[]'):(cur?cur+'.'+key:key);const child=node(v[key],isArr?null:key,childPath);child.className='node';root.appendChild(child)});const tail=document.createElement('div');tail.textContent=isArr?']':'}';root.appendChild(tail)}else{if(hasKey){root.appendChild(keySpan(k));root.append(': ')}root.appendChild(valueNode(v,true));if(hasKey){root.appendChild(pathSpan(cur));root.appendChild(actions(k,cur,false,false,false))}}return root}"
    "function protoNode(n,path){const root=document.createElement('div');const isRoot=path===undefined;const nextPath=isRoot?'':(path?path+'.'+n.name:n.name);if(isRoot){const title=document.createElement('div');title.className='protoRoot';title.textContent=n.name;root.appendChild(title);(n.children||[]).forEach(c=>{const child=protoNode(c,'');child.className='node';root.appendChild(child)});return root}const hasChildren=Array.isArray(n.children);const empty=hasChildren&&n.children.length===0;const fieldFold=folds.has(n.name),pathFold=pathFolds.has(nextPath),emptyFold=autoFoldEmpty&&empty;if(fieldFold||pathFold||emptyFold){root.innerHTML=`<span class='key'>${esc(n.name)}</span> <span class='collapsed'>{ ${empty?'empty':'...'} }</span><span class='path'>${esc(nextPath)}</span>`;const a=actions(n.name,nextPath,fieldFold,pathFold,emptyFold);root.appendChild(a);return root}if(hasChildren){const head=document.createElement('div');head.innerHTML=`<span class='key'>${esc(n.name)}</span> {<span class='path'>${esc(nextPath)}</span>`;head.appendChild(actions(n.name,nextPath,false,false,false));root.appendChild(head);n.children.forEach(c=>{const child=protoNode(c,nextPath);child.className='node';root.appendChild(child)});const tail=document.createElement('div');tail.textContent='}';root.appendChild(tail)}else{root.appendChild(keySpan(n.name));root.append(': ');root.appendChild(valueNode(n.value,false));root.appendChild(pathSpan(nextPath));root.appendChild(actions(n.name,nextPath,false,false,false))}return root}"
    "function actions(name,path,fieldFold,pathFold,emptyFold){const span=document.createElement('span');span.className='actions';const f=document.createElement('button');f.textContent=fieldFold?'取消字段':'折叠字段';f.onclick=()=>{fieldFold?folds.delete(name):folds.add(name);save();show(active);render()};span.appendChild(f);if(path){const p=document.createElement('button');p.textContent=pathFold?'取消路径':'折叠路径';p.onclick=()=>{pathFold?pathFolds.delete(path):pathFolds.add(path);save();show(active);render()};span.appendChild(p)}if(emptyFold){const e=document.createElement('button');e.textContent='显示空字段';e.onclick=()=>{autoFoldEmpty=false;save();show(active);render()};span.appendChild(e)}return span}"
    "function keySpan(s){const el=document.createElement('span');el.className='key';el.textContent=s;return el}"
    "function pathSpan(s){const el=document.createElement('span');el.className='path';el.textContent=s;return el}"
    "function valueNode(v,jsonString){if(typeof v==='number')return textSpan('num',String(v));if(typeof v==='boolean')return textSpan('bool',String(v));if(v===null)return textSpan('collapsed','null');const raw=String(v);if(!jsonString&&(raw==='true'||raw==='false'))return textSpan('bool',raw);if(!jsonString&&/^-?\\d+(\\.\\d+)?$/.test(raw))return textSpan('num',raw);return longStringNode(raw,jsonString)}"
    "function textSpan(cls,text){const el=document.createElement('span');el.className=cls;el.textContent=text;return el}"
    "function longStringNode(raw,quoted){const wrap=document.createElement('span');const text=document.createElement('span');text.className='str';wrap.appendChild(text);if(raw.length<=longValueLimit){text.textContent=quoted?'\"'+raw+'\"':raw;return wrap}const btn=document.createElement('button');btn.className='valueToggle';const meta=document.createElement('span');meta.className='valueMeta';let open=false;function preview(){const head=Math.max(80,longValueLimit-60);return raw.slice(0,head)+' ... '+raw.slice(-40)}function draw(){text.textContent=quoted?'\"'+(open?raw:preview())+'\"':(open?raw:preview());btn.textContent=open?'折叠值':'展开值';meta.textContent=`${raw.length} chars`}btn.onclick=()=>{open=!open;draw()};draw();wrap.appendChild(btn);wrap.appendChild(meta);return wrap}"
    "function summary(v){if(Array.isArray(v))return `[${v.length} items]`;if(v&&typeof v==='object')return '{...}';if(typeof v==='string')return '\"...\"';return String(v)}"
    "function esc(s){return String(s).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]))}"
    "q.oninput=render;document.getElementById('clearHidden').onclick=()=>{hidden.clear();save();render()};document.getElementById('clearFields').onclick=()=>{folds.clear();pathFolds.clear();autoFoldEmpty=false;save();if(active>=0)show(active);render()};"
    "const es=new EventSource('/events');es.onmessage=e=>{const r=JSON.parse(e.data);if(hidden.has(r.title)){render();return}rows.unshift(r);if(rows.length>600)rows.pop();if(active>=0)active++;render();};"
    "</script></body></html>";
}

- (void)sendString:(NSString *)string toClient:(int)client {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    while (length > 0) {
        ssize_t sent = send(client, bytes, length, 0);
        if (sent <= 0) {
            break;
        }
        bytes += sent;
        length -= (NSUInteger)sent;
    }
}

- (void)handleClient:(int)client {
    char buffer[2048] = {0};
    ssize_t readSize = recv(client, buffer, sizeof(buffer) - 1, 0);
    if (readSize <= 0) {
        close(client);
        return;
    }
    NSString *request = [[NSString alloc] initWithBytes:buffer length:(NSUInteger)readSize encoding:NSUTF8StringEncoding] ?: @"";
    if ([request hasPrefix:@"GET /events"]) {
        NSString *headers = @"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream; charset=utf-8\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\n\r\n";
        [self sendString:headers toClient:client];
        dispatch_async(self.queue, ^{
            [self.clients addObject:@(client)];
        });
        return;
    }
    NSString *html = [self htmlPage];
    NSData *htmlData = [html dataUsingEncoding:NSUTF8StringEncoding];
    NSString *headers = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n", (unsigned long)htmlData.length];
    [self sendString:headers toClient:client];
    [self sendString:html toClient:client];
    close(client);
}

- (void)emitEventType:(NSString *)type title:(NSString *)title body:(NSString *)body size:(NSUInteger)size properties:(NSString *)properties {
    if (!self.running) {
        return;
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    NSString *time = [formatter stringFromDate:[NSDate date]];
    NSDictionary *event = @{
        @"type": type ?: @"event",
        @"title": title ?: @"",
        @"body": body ?: @"",
        @"properties": properties ?: @"",
        @"time": time ?: @"",
        @"size": size > 0 ? [NSString stringWithFormat:@"%lu B", (unsigned long)size] : @""
    };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
    if (!jsonData) {
        return;
    }
    NSString *jsonLine = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSString *payload = [NSString stringWithFormat:@"data: %@\n\n", jsonLine];
    dispatch_async(self.queue, ^{
        NSMutableArray<NSNumber *> *deadClients = [NSMutableArray array];
        for (NSNumber *clientNumber in self.clients) {
            int client = clientNumber.intValue;
            NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
            ssize_t sent = send(client, data.bytes, data.length, 0);
            if (sent <= 0) {
                close(client);
                [deadClients addObject:clientNumber];
            }
        }
        [self.clients removeObjectsInArray:deadClients];
    });
}

- (void)emitEventType:(NSString *)type title:(NSString *)title body:(NSString *)body size:(NSUInteger)size {
    [self emitEventType:type title:title body:body size:size properties:nil];
}

- (void)emitJSONData:(NSData *)data URL:(NSURL *)URL {
    if (!self.running || !data) {
        return;
    }
    NSString *body = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (object) {
        NSData *prettyData = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
        body = [[NSString alloc] initWithData:prettyData encoding:NSUTF8StringEncoding];
    }
    if (!body) {
        body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    if (!body) {
        body = [NSString stringWithFormat:@"<%lu bytes non UTF-8 data>", (unsigned long)data.length];
    }
    if (body.length > BLCDebugJSONBodyLimit) {
        body = [[body substringToIndex:BLCDebugJSONBodyLimit] stringByAppendingString:@"\n... truncated"];
    }
    [self emitEventType:@"JSON" title:BLCFullPathForURL(URL) body:body size:data.length];
}

- (NSString *)propertySummaryForModel:(id)model {
    if (!model) {
        return @"";
    }
    NSString *className = NSStringFromClass([model class]);
    @synchronized (self) {
        NSString *cached = self.propertySummaries[className];
        if (cached) {
            return cached;
        }
    }

    Class cls = [model class];
    NSMutableString *summary = [NSMutableString stringWithFormat:@"Runtime properties: %@\n", className];
    unsigned int propertyCount = 0;
    objc_property_t *properties = class_copyPropertyList(cls, &propertyCount);
    if (propertyCount == 0) {
        [summary appendString:@"(none)\n"];
    } else {
        for (unsigned int i = 0; i < propertyCount; i++) {
            const char *name = property_getName(properties[i]);
            const char *attrs = property_getAttributes(properties[i]);
            [summary appendFormat:@"%s", name ?: ""];
            if (attrs && strlen(attrs) > 0) {
                [summary appendFormat:@"  %s", attrs];
            }
            [summary appendString:@"\n"];
        }
    }
    if (properties) {
        free(properties);
    }

    NSString *result = [summary copy];
    @synchronized (self) {
        self.propertySummaries[className] = result;
    }
    return result;
}

- (void)emitModel:(id)model {
    if (!self.running || !model) {
        return;
    }
    NSString *className = NSStringFromClass([model class]);
    if (![className containsString:@"BAPI"] && ![className containsString:@"Reply"]) {
        return;
    }
    NSString *body = nil;
    if ([model respondsToSelector:@selector(dictionaryRepresentation)]) {
        SEL selector = @selector(dictionaryRepresentation);
        id dict = ((id (*)(id, SEL))objc_msgSend)(model, selector);
        if ([dict isKindOfClass:[NSDictionary class]] || [dict isKindOfClass:[NSArray class]]) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:nil];
            body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
    }
    if (!body) {
        body = [model description] ?: @"";
    }
    if (body.length > BLCDebugModelBodyLimit) {
        body = [[body substringToIndex:BLCDebugModelBodyLimit] stringByAppendingString:@"\n... truncated"];
    }
    [self emitEventType:@"Protobuf" title:className body:body size:[body lengthOfBytesUsingEncoding:NSUTF8StringEncoding] properties:[self propertySummaryForModel:model]];
}

@end

static BOOL BLCIsAdDictionary(NSDictionary *dict) {
    if (![BLCSettings featureEnabled:BLCAdBlockEnabledKey defaultValue:YES]) {
        return NO;
    }
    id adInfo = dict[@"ad_info"] ?: dict[@"adInfo"] ?: dict[@"cm"] ?: dict[@"cm_mark"] ?: dict[@"ad_cb"];
    if (adInfo && adInfo != (id)kCFNull) {
        return YES;
    }
    if ([dict[@"is_ad"] boolValue] || [dict[@"isAd"] boolValue] || [dict[@"has_ad"] boolValue]) {
        return YES;
    }
    NSArray<NSString *> *values = @[
        BLCStringValue(dict[@"card_type"]) ?: @"",
        BLCStringValue(dict[@"card_goto"]) ?: @"",
        BLCStringValue(dict[@"goto"]) ?: @"",
        BLCStringValue(dict[@"type"]) ?: @"",
        BLCStringValue(dict[@"item_type"]) ?: @"",
        BLCStringValue(dict[@"from_type"]) ?: @""
    ];
    NSArray<NSString *> *blocked = @[
        @"cm_v1", @"cm_v2", @"cm_double_v7", @"cm_double_v9",
        @"banner_v1", @"banner_v2", @"banner_v8", @"banner_ipad_v8",
        @"activity_card_v1", @"vertical_ad_av", @"vertical_ad_live",
        @"video_ad", @"picture_ad", @"brand_ad_giant", @"special_s",
        @"focus_img", @"operation"
    ];
    for (NSString *value in values) {
        for (NSString *needle in blocked) {
            if ([value rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) {
                return YES;
            }
        }
    }
    return NO;
}

static BOOL BLCShouldRemoveHomeLiveItem(NSDictionary *dict, NSString *url) {
    if (![BLCSettings featureEnabled:BLCPruneHomeLiveEnabledKey defaultValue:YES]) {
        return NO;
    }
    if (![url hasSuffix:@"/x/v2/feed/index"]) {
        return NO;
    }
    NSString *description = BLCStringValue(dict[@"cover_right_content_description"]) ?: @"";
    return [description isEqualToString:@"直播"];
}

static BOOL BLCShouldRemoveMineItem(NSDictionary *dict) {
    if (![BLCSettings featureEnabled:BLCPruneUnusedServicesEnabledKey defaultValue:YES]) {
        return NO;
    }
    id itemIdValue = dict[@"id"] ?: dict[@"item_id"] ?: dict[@"itemId"] ?: dict[@"tab_id"];
    NSString *title = BLCStringValue(dict[@"title"]) ?: BLCStringValue(dict[@"name"]);
    if (!itemIdValue && title.length == 0) {
        return NO;
    }
    NSInteger itemId = [itemIdValue integerValue];
    NSSet<NSNumber *> *allowedIds = [NSSet setWithArray:@[@396, @397, @3072, @2830, @407, @410]];
    if (itemId > 0 && [allowedIds containsObject:@(itemId)]) {
        return NO;
    }
    NSArray<NSString *> *allowedTitles = @[@"离线缓存", @"历史记录", @"我的收藏", @"稍后再看", @"联系客服", @"设置"];
    for (NSString *allowed in allowedTitles) {
        if ([title isEqualToString:allowed]) {
            return NO;
        }
    }
    return YES;
}

static BOOL BLCShouldRemoveDictionary(NSDictionary *dict, NSString *url) {
    if ([url containsString:@"/x/resource/show/tab/v2"]) {
        return NO;
    }
    if (BLCIsAdDictionary(dict)) {
        return YES;
    }
    if (BLCShouldRemoveHomeLiveItem(dict, url)) {
        return YES;
    }
    if ([url containsString:@"/x/v2/account/mine"] && BLCShouldRemoveMineItem(dict)) {
        return YES;
    }
    if ([url containsString:@"/x/v2/search/square"]) {
        NSString *type = BLCStringValue(dict[@"type"]) ?: @"";
        if ([type isEqualToString:@"recommend"]) {
            return YES;
        }
    }
    if ([url containsString:@"/x/v2/feed/index"]) {
        NSString *title = BLCStringValue(dict[@"title"]) ?: @"";
        return BLCTextMatchesKeywordRulesForScope(title, BLCKeywordScopeRecommend);
    }
    NSString *text = BLCTextFromObject(dict, 0);
    return BLCTextMatchesKeywordRulesForScope(text, BLCKeywordScopeRecommend);
}

static void BLCProcessJSONObject(id object, NSString *url);

static void BLCFilterArray(NSMutableArray *array, NSString *url) {
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:array.count];
    for (id item in array) {
        if ([item isKindOfClass:[NSMutableDictionary class]]) {
            NSMutableDictionary *dict = item;
            BLCProcessJSONObject(dict, url);
            if (!BLCShouldRemoveDictionary(dict, url)) {
                [kept addObject:dict];
            }
        } else if ([item isKindOfClass:[NSMutableArray class]]) {
            BLCFilterArray(item, url);
            [kept addObject:item];
        } else {
            [kept addObject:item];
        }
    }
    [array removeAllObjects];
    [array addObjectsFromArray:kept];
}

static void BLCEnsureFeedAuthorMetadata(NSMutableDictionary *item) {
    id args = item[@"args"];
    if (![args isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *argsDict = args;
    NSString *upName = BLCStringValue(argsDict[@"up_name"]) ?: @"";
    NSString *upId = BLCStringValue(argsDict[@"up_id"]) ?: @"";
    if (upName.length > 0 && ![item[@"desc_button"] isKindOfClass:[NSDictionary class]]) {
        NSString *uri = upId.length > 0 ? [@"bilibili://space/" stringByAppendingString:upId] : @"";
        item[@"desc_button"] = @{
            @"type": @1,
            @"event": @"nickname",
            @"uri": uri,
            @"text": upName
        };
    }
    if (![item[@"goto_icon"] isKindOfClass:[NSDictionary class]]) {
        item[@"goto_icon"] = @{
            @"icon_url": @"https://i0.hdslb.com/bfs/activity-plat/static/20230227/0977767b2e79d8ad0a36a731068a83d7/077GOeHOfO.png",
            @"icon_night_url": @"https://i0.hdslb.com/bfs/activity-plat/static/20230227/0977767b2e79d8ad0a36a731068a83d7/ldbCXtkoK2.png",
            @"icon_width": @16,
            @"icon_height": @16
        };
    }
}

static BOOL BLCFeedItemIsPicture(NSDictionary *item) {
    NSString *gotoValue = BLCStringValue(item[@"goto"]) ?: @"";
    NSString *cardGoto = BLCStringValue(item[@"card_goto"]) ?: @"";
    return [gotoValue isEqualToString:@"picture"] || [cardGoto isEqualToString:@"picture"];
}

static void BLCNormalizeFeedStoryURI(NSMutableDictionary *item) {
    NSString *uri = BLCStringValue(item[@"uri"]);
    NSString *storyPrefix = @"bilibili://story/";
    if (![uri hasPrefix:storyPrefix]) {
        return;
    }
    NSString *suffix = [uri substringFromIndex:storyPrefix.length];
    item[@"uri"] = [@"bilibili://video/" stringByAppendingString:suffix];
}

static void BLCApplyFeedIndexItemMutations(NSMutableDictionary *dict, NSString *url) {
    if (![url containsString:@"/x/v2/feed/index"]) {
        return;
    }
    BOOL normalizeVerticalMode = [BLCSettings featureEnabled:BLCVerticalBlockEnabledKey defaultValue:YES];
    BOOL removeRecommendReason = [BLCSettings featureEnabled:BLCPruneFeedReasonEnabledKey defaultValue:YES];
    BOOL removePictureItems = [BLCSettings featureEnabled:BLCPruneFeedPictureEnabledKey defaultValue:YES];
    if (!normalizeVerticalMode && !removeRecommendReason && !removePictureItems) {
        return;
    }
    id data = dict[@"data"];
    if (![data isKindOfClass:[NSMutableDictionary class]]) {
        return;
    }
    id items = ((NSMutableDictionary *)data)[@"items"];
    if (![items isKindOfClass:[NSArray class]]) {
        return;
    }
    NSMutableArray *keptItems = removePictureItems ? [NSMutableArray arrayWithCapacity:[(NSArray *)items count]] : nil;
    for (id item in (NSArray *)items) {
        if (![item isKindOfClass:[NSMutableDictionary class]]) {
            if (keptItems) {
                [keptItems addObject:item];
            }
            continue;
        }
        NSMutableDictionary *itemDict = item;
        if (removePictureItems && BLCFeedItemIsPicture(itemDict)) {
            continue;
        }
        if (normalizeVerticalMode) {
            itemDict[@"goto"] = @"av";
            itemDict[@"card_goto"] = @"av";
            BLCNormalizeFeedStoryURI(itemDict);
            id playerArgs = itemDict[@"player_args"];
            if ([playerArgs isKindOfClass:[NSMutableDictionary class]]) {
                ((NSMutableDictionary *)playerArgs)[@"type"] = @"av";
            }
        }
        if (removeRecommendReason) {
            [itemDict removeObjectForKey:@"rcmd_reason"];
            [itemDict removeObjectForKey:@"rcmd_reason_style"];
            BLCEnsureFeedAuthorMetadata(itemDict);
        }
        if (keptItems) {
            [keptItems addObject:itemDict];
        }
    }
    if (keptItems) {
        if ([items isKindOfClass:[NSMutableArray class]]) {
            [(NSMutableArray *)items removeAllObjects];
            [(NSMutableArray *)items addObjectsFromArray:keptItems];
        } else {
            ((NSMutableDictionary *)data)[@"items"] = keptItems;
        }
    }
}

static void BLCApplyEndpointMutations(NSMutableDictionary *dict, NSString *url) {
    [[BLCTabManager sharedManager] captureAndFilterResponseDictionary:dict URLString:url];
    BLCApplyFeedIndexItemMutations(dict, url);
    if ([url containsString:@"/x/v2/splash/list"] && [BLCSettings featureEnabled:BLCAdBlockEnabledKey defaultValue:YES]) {
        id data = dict[@"data"];
        if ([data isKindOfClass:[NSMutableDictionary class]]) {
            ((NSMutableDictionary *)data)[@"show"] = [NSMutableArray array];
            ((NSMutableDictionary *)data)[@"list"] = [NSMutableArray array];
            ((NSMutableDictionary *)data)[@"brand_show"] = [NSMutableArray array];
        }
    }
    if ([url containsString:@"/xlive/app-interface/v2/second/getList"] && [BLCSettings featureEnabled:BLCAdBlockEnabledKey defaultValue:YES]) {
        id data = dict[@"data"];
        if ([data isKindOfClass:[NSMutableDictionary class]]) {
            ((NSMutableDictionary *)data)[@"banner"] = [NSMutableArray array];
            ((NSMutableDictionary *)data)[@"new_tags"] = [NSMutableArray array];
        }
    }
    if ([url containsString:@"/x/v2/view/upper/recmd"] && [BLCSettings featureEnabled:BLCAdBlockEnabledKey defaultValue:YES]) {
        dict[@"data"] = [NSNull null];
    }
    if ([url containsString:@"/x/resource/show/skin"] && [BLCSettings featureEnabled:BLCAdBlockEnabledKey defaultValue:YES]) {
        id data = dict[@"data"];
        if ([data isKindOfClass:[NSMutableDictionary class]]) {
            [(NSMutableDictionary *)data removeObjectForKey:@"common_equip"];
        }
    }
    if ([BLCSettings featureEnabled:BLCVerticalBlockEnabledKey defaultValue:YES]) {
        [dict removeObjectForKey:@"creative_entrance"];
        [dict removeObjectForKey:@"scroll_guide"];
    }
}

static void BLCProcessJSONObject(id object, NSString *url) {
    if ([object isKindOfClass:[NSMutableDictionary class]]) {
        NSMutableDictionary *dict = object;
        BLCApplyEndpointMutations(dict, url);
        for (id key in [dict allKeys]) {
            id value = dict[key];
            if ([value isKindOfClass:[NSMutableArray class]]) {
                BLCFilterArray(value, url);
            } else if ([value isKindOfClass:[NSMutableDictionary class]]) {
                BLCProcessJSONObject(value, url);
            }
        }
    } else if ([object isKindOfClass:[NSMutableArray class]]) {
        BLCFilterArray(object, url);
    }
}

static NSData *BLCFilteredJSONData(NSData *data, NSURLResponse *response) {
    if (![BLCSettings masterEnabled] || data.length == 0) {
        return data;
    }
    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
    if (error || !object) {
        return data;
    }
    NSString *url = BLCFullPathForURL(response.URL);
    BLCProcessJSONObject(object, url);
    NSData *filteredData = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    return filteredData ?: data;
}

static id BLCValueForKeyIfAvailable(id object, NSString *key) {
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void BLCSetValueForKeyIfAvailable(id object, NSString *key, id value) {
    @try {
        [object setValue:value forKey:key];
    } @catch (__unused NSException *exception) {
    }
}

static BOOL BLCBoolValueForModelKey(id object, NSString *key) {
    id value = BLCValueForKeyIfAvailable(object, key);
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

static BOOL BLCBoolValueForAnyModelKey(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        if (BLCBoolValueForModelKey(object, key)) {
            return YES;
        }
    }
    return NO;
}

static NSInteger BLCIntegerValueForModelKey(id object, NSString *key) {
    id value = BLCValueForKeyIfAvailable(object, key);
    if (![value respondsToSelector:@selector(integerValue)]) {
        return 0;
    }
    return [value integerValue];
}

static NSString *BLCDescriptionEnumValueForField(id object, NSString *fieldName);

static BOOL BLCShouldRemoveMerchandiseModule(id module) {
    NSInteger type = BLCIntegerValueForModelKey(module, @"type");
    if (type == 55) {
        return YES;
    }
    NSString *typeName = BLCDescriptionEnumValueForField(module, @"type") ?: @"";
    return [typeName isEqualToString:@"MERCHANDISE"];
}

static BOOL BLCShouldRemoveDetailModule(id module) {
    NSInteger type = BLCIntegerValueForModelKey(module, @"type");
    static NSSet<NSNumber *> *filterTypes;
    if (!filterTypes) {
        filterTypes = [NSSet setWithArray:@[
            @55, // MERCHANDISE, 旧版视频下方商品模块
            @29, // PAY_BAR, 大会员
            @34, // LIKE_COMMENT, 鼓励 UP 主继续创作
            @36, // COVENANTER, 成为 UP 主老粉
            @12, // LIVE_ORDER, 预约直播
            @23  // OGV_LIVE_RESERVE, OGV 预约直播
        ]];
    }
    return [filterTypes containsObject:@(type)];
}

static NSString *BLCDescriptionEnumValueForField(id object, NSString *fieldName) {
    NSString *text = [object description] ?: @"";
    NSString *prefix = [fieldName stringByAppendingString:@":"];
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSCharacterSet *trimSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:trimSet];
        if (![trimmed hasPrefix:prefix]) {
            continue;
        }
        NSString *value = [[trimmed substringFromIndex:prefix.length] stringByTrimmingCharactersInSet:trimSet];
        NSRange end = [value rangeOfCharacterFromSet:trimSet];
        if (end.location != NSNotFound) {
            value = [value substringToIndex:end.location];
        }
        return value;
    }
    return nil;
}

static BOOL BLCShouldRemoveDetailRelateCard(id card) {
    NSInteger type = BLCIntegerValueForModelKey(card, @"relateCardType");
    static NSSet<NSNumber *> *filterTypes;
    static NSSet<NSString *> *filterNames;
    if (!filterTypes) {
        filterTypes = [NSSet setWithArray:@[
            @3,  // RESOURCE, 商品卡片
            @4,  // GAME, 游戏卡片
            @5,  // CM, 广告卡片
            @6,  // LIVE, 直播卡片
            @10  // SPECIAL, 特殊活动卡片
        ]];
        filterNames = [NSSet setWithArray:@[
            @"RESOURCE",
            @"GAME",
            @"CM",
            @"LIVE",
            @"SPECIAL"
        ]];
    }
    if ([filterTypes containsObject:@(type)] || BLCBoolValueForModelKey(card, @"hasCmStock")) {
        return YES;
    }
    if (BLCBoolValueForAnyModelKey(card, @[@"hasResource", @"hasGame", @"hasCm", @"hasCM", @"hasLive", @"hasSpecial"])) {
        return YES;
    }
    NSString *snakeType = BLCDescriptionEnumValueForField(card, @"relate_card_type");
    if (snakeType.length > 0 && [filterNames containsObject:snakeType]) {
        return YES;
    }
    NSString *camelType = BLCDescriptionEnumValueForField(card, @"relateCardType");
    if (camelType.length > 0 && ([filterNames containsObject:camelType] || [filterTypes containsObject:@(camelType.integerValue)])) {
        return YES;
    }
    if (!BLCBoolValueForModelKey(card, @"hasBasicInfo")) {
        return NO;
    }
    id basicInfo = BLCValueForKeyIfAvailable(card, @"basicInfo");
    NSString *from = BLCStringValue(BLCValueForKeyIfAvailable(basicInfo, @"from")) ?: @"";
    return [from isEqualToString:@"operation"];
}

static id BLCValueForAnyKey(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = BLCValueForKeyIfAvailable(object, key);
        if (value) {
            return value;
        }
    }
    return nil;
}

static NSArray *BLCArrayForAnyKey(id object, NSArray<NSString *> *keys) {
    id value = BLCValueForAnyKey(object, keys);
    return [value isKindOfClass:[NSArray class]] ? value : nil;
}

static BOOL BLCModuleIsRelatedRecommend(id module) {
    if (!module) {
        return NO;
    }
    if (BLCBoolValueForModelKey(module, @"hasRelates")) {
        return YES;
    }
    NSString *typeName = BLCDescriptionEnumValueForField(module, @"type") ?: @"";
    return [typeName isEqualToString:@"RELATED_RECOMMEND"];
}

static void BLCFilterModelArray(id model, NSString *key, BOOL (^shouldRemove)(id item)) {
    id value = BLCValueForKeyIfAvailable(model, key);
    if (![value isKindOfClass:[NSArray class]] || !shouldRemove) {
        return;
    }
    NSArray *array = value;
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:array.count];
    for (id item in array) {
        if (!shouldRemove(item)) {
            [kept addObject:item];
        }
    }
    if ([value isKindOfClass:[NSMutableArray class]]) {
        [(NSMutableArray *)value removeAllObjects];
        [(NSMutableArray *)value addObjectsFromArray:kept];
        BLCSetValueForKeyIfAvailable(model, key, value);
    } else {
        BLCSetValueForKeyIfAvailable(model, key, kept);
    }
}

static void BLCFilterRelatesCards(id relates) {
    BLCFilterModelArray(relates, @"cardsArray", ^BOOL(id item) {
        return BLCShouldRemoveDetailRelateCard(item);
    });
}

static NSMutableArray *BLCFilteredIntroductionModulesArray(NSArray *modules, BOOL removeMerchandise, BOOL removeDetailModules) {
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:modules.count];
    for (id item in modules) {
        if (removeMerchandise && BLCShouldRemoveMerchandiseModule(item)) {
            continue;
        }
        if (removeDetailModules && BLCShouldRemoveDetailModule(item)) {
            continue;
        }
        [kept addObject:item];
    }
    return kept;
}

static void BLCFilterIntroductionModules(id introduction, BOOL removeMerchandise, BOOL removeDetailModules) {
    if (!removeMerchandise && !removeDetailModules) {
        return;
    }
    id value = BLCValueForKeyIfAvailable(introduction, @"modulesArray");
    if (![value isKindOfClass:[NSArray class]]) {
        return;
    }
    NSMutableArray *kept = BLCFilteredIntroductionModulesArray((NSArray *)value, removeMerchandise, removeDetailModules);
    if ([value isKindOfClass:[NSMutableArray class]]) {
        [(NSMutableArray *)value removeAllObjects];
        [(NSMutableArray *)value addObjectsFromArray:kept];
        BLCSetValueForKeyIfAvailable(introduction, @"modulesArray", value);
    } else {
        BLCSetValueForKeyIfAvailable(introduction, @"modulesArray", kept);
    }
}

static void BLCFilterViewReplyMerchandiseModules(id model) {
    id tab = BLCValueForKeyIfAvailable(model, @"tab");
    NSArray *tabModules = BLCArrayForAnyKey(tab, @[@"tabModuleArray"]);
    for (id tabModule in tabModules) {
        id introduction = BLCValueForKeyIfAvailable(tabModule, @"introduction");
        BLCFilterIntroductionModules(introduction, YES, NO);
    }
}

static void BLCFilterViewReplyEmbeddedRelates(id model) {
    id tab = BLCValueForKeyIfAvailable(model, @"tab");
    NSArray *tabModules = BLCArrayForAnyKey(tab, @[@"tabModuleArray"]);
    for (id tabModule in tabModules) {
        id introduction = BLCValueForKeyIfAvailable(tabModule, @"introduction");
        NSArray *modules = BLCArrayForAnyKey(introduction, @[@"modulesArray"]);
        for (id module in modules) {
            if (!BLCModuleIsRelatedRecommend(module)) {
                continue;
            }
            id relates = BLCValueForKeyIfAvailable(module, @"relates");
            BLCFilterRelatesCards(relates);
        }
    }
}

static void BLCFilterViewEndPageReply(id model) {
    BLCFilterModelArray(model, @"relatesArray", ^BOOL(id item) {
        id relate = BLCValueForKeyIfAvailable(item, @"relate");
        return BLCShouldRemoveDetailRelateCard(relate) || BLCShouldRemoveDetailRelateCard(item);
    });
}

static void BLCClearNestedMutableArray(id model, NSString *containerKey, NSString *arrayKey) {
    id container = BLCValueForKeyIfAvailable(model, containerKey);
    id array = BLCValueForKeyIfAvailable(container, arrayKey);
    if ([array isKindOfClass:[NSMutableArray class]]) {
        [(NSMutableArray *)array removeAllObjects];
    }
}

static void BLCFilterPlayerFloatingPrompts(id model) {
    if (![BLCSettings featureEnabled:BLCPlayerFloatingBlockEnabledKey defaultValue:YES]) {
        return;
    }
    NSString *className = NSStringFromClass([model class]);
    if ([className containsString:@"BAPICommunityServiceDmV1DmViewReply"]) {
        BLCClearNestedMutableArray(model, @"command", @"commandDmsArray");
        id activityMetaArray = BLCValueForKeyIfAvailable(model, @"activityMetaArray");
        if ([activityMetaArray isKindOfClass:[NSMutableArray class]]) {
            [(NSMutableArray *)activityMetaArray removeAllObjects];
        }
    }
    if ([className containsString:@"BAPIAppViewuniteV1ViewProgressReply"]) {
        BLCClearNestedMutableArray(model, @"dm", @"commandDmsArray");
        BLCClearNestedMutableArray(model, @"dm", @"cardsArray");
    }
}

static BOOL BLCModelTextLooksDynamicUpAdItem(NSString *text) {
    return BLCTextContains(text, @"module_opus_summary") &&
           BLCTextContains(text, @"goods_item") &&
           BLCTextContains(text, @"ad_mark");
}

static BOOL BLCModelTextLooksDynamicOnlyFansItem(NSString *text) {
    return BLCTextContains(text, @"only_fans_property") &&
           BLCTextContains(text, @"is_only_fans: true");
}

static BOOL BLCModelTextLooksDynamicLiveRcmdItem(NSString *text) {
    return BLCTextContains(text, @"card_type") &&
           BLCTextContains(text, @"live_rcmd");
}

static NSString *BLCDescriptionValueForFieldLine(NSString *trimmedLine, NSString *fieldName) {
    NSString *prefix = [fieldName stringByAppendingString:@":"];
    if (![trimmedLine hasPrefix:prefix]) {
        return nil;
    }
    NSString *value = [[trimmedLine substringFromIndex:prefix.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([value hasPrefix:@"\""]) {
        NSRange closingQuote = [value rangeOfString:@"\"" options:NSBackwardsSearch range:NSMakeRange(1, value.length - 1)];
        if (closingQuote.location != NSNotFound && closingQuote.location > 0) {
            return [value substringWithRange:NSMakeRange(1, closingQuote.location - 1)];
        }
        return [value substringFromIndex:1];
    }
    return value;
}

static BOOL BLCModelTextMatchesDynamicKeywordRules(NSString *text, NSArray<NSDictionary *> *rules) {
    if (text.length == 0 || rules.count == 0) {
        return NO;
    }
    NSArray<NSString *> *targetFields = @[@"raw_text", @"orig_text"];
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        for (NSString *field in targetFields) {
            NSString *value = BLCDescriptionValueForFieldLine(trimmed, field);
            if (value.length > 0 && BLCTextMatchesKeywordRuleList(value, rules)) {
                return YES;
            }
        }
    }
    return NO;
}

static BOOL BLCShouldRemoveDynamicListItemText(NSString *text, BOOL checkUpAd, BOOL checkOnlyFans, BOOL checkLiveRcmd, NSArray<NSDictionary *> *keywordRules) {
    if (checkUpAd && BLCModelTextLooksDynamicUpAdItem(text)) {
        return YES;
    }
    if (checkOnlyFans && BLCModelTextLooksDynamicOnlyFansItem(text)) {
        return YES;
    }
    if (checkLiveRcmd && BLCModelTextLooksDynamicLiveRcmdItem(text)) {
        return YES;
    }
    return BLCModelTextMatchesDynamicKeywordRules(text, keywordRules);
}

static void BLCFilterDynamicUpAdListArray(NSMutableArray *array, BOOL checkUpAd, BOOL checkOnlyFans, BOOL checkLiveRcmd, NSArray<NSDictionary *> *keywordRules) {
    if (!checkUpAd && !checkOnlyFans && !checkLiveRcmd && keywordRules.count == 0) {
        return;
    }
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:array.count];
    for (id item in array) {
        NSString *text = [item description] ?: @"";
        if (!BLCShouldRemoveDynamicListItemText(text, checkUpAd, checkOnlyFans, checkLiveRcmd, keywordRules)) {
            [kept addObject:item];
        }
    }
    [array removeAllObjects];
    [array addObjectsFromArray:kept];
}

static void BLCFilterDynamicUpAds(id model) {
    BOOL checkUpAd = [BLCSettings featureEnabled:BLCPruneDynamicUpAdEnabledKey defaultValue:YES];
    BOOL checkOnlyFans = [BLCSettings featureEnabled:BLCPruneDynamicOnlyFansEnabledKey defaultValue:YES];
    BOOL checkLiveRcmd = [BLCSettings featureEnabled:BLCPruneDynamicLiveRcmdEnabledKey defaultValue:YES];
    NSArray<NSDictionary *> *keywordRules = @[];
    if ([BLCSettings featureEnabled:BLCKeywordBlockEnabledKey defaultValue:YES]) {
        keywordRules = BLCKeywordRulesForScope([BLCSettings keywordRules], BLCKeywordScopeDynamic);
    }
    if (!checkUpAd && !checkOnlyFans && !checkLiveRcmd && keywordRules.count == 0) {
        return;
    }
    NSString *className = NSStringFromClass([model class]);
    if (![className containsString:@"BAPIAppDynamicV2"] &&
        ![className containsString:@"DynAllReply"]) {
        return;
    }
    id dynamicList = BLCValueForKeyIfAvailable(model, @"dynamicList");
    id nestedListArray = BLCValueForKeyIfAvailable(dynamicList, @"listArray");
    if ([nestedListArray isKindOfClass:[NSMutableArray class]]) {
        BLCFilterDynamicUpAdListArray(nestedListArray, checkUpAd, checkOnlyFans, checkLiveRcmd, keywordRules);
    }
    id directListArray = BLCValueForKeyIfAvailable(model, @"listArray");
    if ([directListArray isKindOfClass:[NSMutableArray class]]) {
        BLCFilterDynamicUpAdListArray(directListArray, checkUpAd, checkOnlyFans, checkLiveRcmd, keywordRules);
    }
}

static BOOL BLCObjectHasAnyFieldValue(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = BLCValueForKeyIfAvailable(object, key);
        if (value && ![value isKindOfClass:[NSNull class]]) {
            return YES;
        }
    }
    return NO;
}

static BOOL BLCReplyURLMapHasGoodsItemID(id urls) {
    if (![urls isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    for (id value in [(NSDictionary *)urls allValues]) {
        id extra = BLCValueForKeyIfAvailable(value, @"extra");
        if (BLCObjectHasAnyFieldValue(extra, @[@"goodsItemId", @"goods_item_id"])) {
            return YES;
        }
    }
    return NO;
}

static BOOL BLCReplyHasCommerceURL(id reply) {
    id content = BLCValueForKeyIfAvailable(reply, @"content");
    id urls = BLCValueForAnyKey(content, @[@"urls", @"urlsDictionary", @"urlsMap"]);
    if (BLCReplyURLMapHasGoodsItemID(urls)) {
        return YES;
    }
    NSString *text = [reply description] ?: @"";
    return BLCTextContains(text, @"goods_item_id");
}

static BOOL BLCMainCommunityReplyHasTopCommerce(id model) {
    NSArray *topReplies = BLCArrayForAnyKey(model, @[@"topRepliesArray"]);
    for (id reply in topReplies) {
        if (BLCReplyHasCommerceURL(reply)) {
            return YES;
        }
    }
    return NO;
}

static NSString *BLCFieldNameWithInitialCapital(NSString *key) {
    if (key.length == 0) {
        return @"";
    }
    NSString *first = [[key substringToIndex:1] uppercaseString];
    return key.length == 1 ? first : [first stringByAppendingString:[key substringFromIndex:1]];
}

static void BLCClearModelMessageField(id model, NSString *key) {
    NSString *capitalized = BLCFieldNameWithInitialCapital(key);
    SEL clearSelector = NSSelectorFromString([@"clear" stringByAppendingString:capitalized]);
    if ([model respondsToSelector:clearSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(model, clearSelector);
        return;
    }
    SEL hasSetter = NSSelectorFromString([NSString stringWithFormat:@"setHas%@:", capitalized]);
    if ([model respondsToSelector:hasSetter]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(model, hasSetter, NO);
    }
    SEL valueSetter = NSSelectorFromString([NSString stringWithFormat:@"set%@:", capitalized]);
    if ([model respondsToSelector:valueSetter]) {
        ((void (*)(id, SEL, id))objc_msgSend)(model, valueSetter, nil);
        return;
    }
    BLCSetValueForKeyIfAvailable(model, key, nil);
}

static void BLCClearModelRepeatedArray(id model, NSString *key) {
    id value = BLCValueForKeyIfAvailable(model, key);
    if ([value isKindOfClass:[NSMutableArray class]]) {
        [(NSMutableArray *)value removeAllObjects];
        BLCSetValueForKeyIfAvailable(model, key, value);
    } else if ([value isKindOfClass:[NSArray class]]) {
        BLCSetValueForKeyIfAvailable(model, key, [NSMutableArray array]);
    }
}

static void BLCRemoveMainCommunityTopCommerce(id model) {
    if (![BLCSettings featureEnabled:BLCPruneCommentCommerceEnabledKey defaultValue:YES]) {
        return;
    }
    if (!BLCMainCommunityReplyHasTopCommerce(model)) {
        return;
    }
    BLCClearModelMessageField(model, @"upTop");
    BLCClearModelMessageField(model, @"cm");
    BLCClearModelRepeatedArray(model, @"topRepliesArray");
    BLCClearModelRepeatedArray(model, @"subjectTopCardsArray");
}

static NSString *BLCReplyMessage(id reply) {
    id content = BLCValueForKeyIfAvailable(reply, @"content");
    return BLCStringValue(BLCValueForKeyIfAvailable(content, @"message")) ?: @"";
}

static void BLCFilterMainCommunityRepliesByKeyword(id model) {
    if (![BLCSettings featureEnabled:BLCKeywordBlockEnabledKey defaultValue:YES]) {
        return;
    }
    NSArray<NSDictionary *> *rules = BLCKeywordRulesForScope([BLCSettings keywordRules], BLCKeywordScopeComment);
    if (rules.count == 0) {
        return;
    }
    id value = BLCValueForKeyIfAvailable(model, @"repliesArray");
    if (![value isKindOfClass:[NSArray class]]) {
        return;
    }
    NSArray *array = value;
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:array.count];
    for (id reply in array) {
        NSString *message = BLCReplyMessage(reply);
        if (!BLCTextMatchesKeywordRuleList(message, rules)) {
            [kept addObject:reply];
        }
    }
    if ([value isKindOfClass:[NSMutableArray class]]) {
        [(NSMutableArray *)value removeAllObjects];
        [(NSMutableArray *)value addObjectsFromArray:kept];
        BLCSetValueForKeyIfAvailable(model, @"repliesArray", value);
    } else {
        BLCSetValueForKeyIfAvailable(model, @"repliesArray", kept);
    }
}

static void BLCFilterMainCommunityReply(id model) {
    NSString *className = NSStringFromClass([model class]);
    if (![className containsString:@"CommunityReply"] || ![className containsString:@"MainListReply"]) {
        return;
    }
    BLCRemoveMainCommunityTopCommerce(model);
    BLCFilterMainCommunityRepliesByKeyword(model);
}

static BOOL BLCModelTextLooksBlocked(NSString *text, NSString *keywordScope) {
    if (text.length == 0) {
        return NO;
    }
    if (keywordScope.length > 0 && BLCTextMatchesKeywordRulesForScope(text, keywordScope)) {
        return YES;
    }
    if ([BLCSettings featureEnabled:BLCAdBlockEnabledKey defaultValue:YES]) {
        NSArray<NSString *> *needles = @[@"adInfo", @"ad_info", @"cmStock", @"vertical_ad", @"video_ad", @"picture_ad", @"brand_ad", @"operation", @"activityMeta", @"commandDms", @"diversionEntrance"];
        for (NSString *needle in needles) {
            if (BLCTextContains(text, needle)) {
                return YES;
            }
        }
    }
    if ([BLCSettings featureEnabled:BLCVerticalBlockEnabledKey defaultValue:YES]) {
        if (BLCTextContains(text, @"vertical") || BLCTextContains(text, @"story")) {
            return YES;
        }
    }
    return NO;
}

static void BLCFilterModelObject(id model) {
    if (![BLCSettings masterEnabled] || !model) {
        return;
    }
    NSString *className = NSStringFromClass([model class]);
    if (![className containsString:@"BAPI"] && ![className containsString:@"Reply"]) {
        return;
    }
    BLCDownloadCaptureReply(model);
    [[BLCCDNManager sharedManager] rewritePlayViewReply:model];
    BLCFilterMainCommunityReply(model);
    BLCFilterPlayerFloatingPrompts(model);
    BLCFilterDynamicUpAds(model);
    NSArray<NSString *> *arrayKeys = @[
        @"itemsArray", @"cardsArray", @"modulesArray", @"listArray",
        @"dynamicListArray", @"relatesArray", @"commandDmsArray",
        @"activityMetaArray", @"diversionEntranceListArray"
    ];
    for (NSString *key in arrayKeys) {
        id value = BLCValueForKeyIfAvailable(model, key);
        if (![value isKindOfClass:[NSMutableArray class]]) {
            continue;
        }
        NSMutableArray *array = value;
        if (([key isEqualToString:@"commandDmsArray"] || [key isEqualToString:@"activityMetaArray"] || [key isEqualToString:@"diversionEntranceListArray"]) &&
            [BLCSettings featureEnabled:BLCAdBlockEnabledKey defaultValue:YES]) {
            [array removeAllObjects];
            continue;
        }
        NSMutableArray *kept = [NSMutableArray arrayWithCapacity:array.count];
        for (id item in array) {
            NSString *text = [item description] ?: @"";
            NSString *keywordScope = [className containsString:@"BAPIAppDynamicV2"] ? nil : BLCKeywordScopeRecommend;
            if (!BLCModelTextLooksBlocked(text, keywordScope)) {
                [kept addObject:item];
            }
        }
        [array removeAllObjects];
        [array addObjectsFromArray:kept];
    }
}

@interface BLCSponsorState : NSObject
@property (nonatomic, assign) long long cid;
@property (nonatomic, assign) long long oid;
@property (nonatomic, copy) NSString *bvid;
@property (nonatomic, copy) NSString *videoKey;
@property (nonatomic, strong) NSArray<NSDictionary *> *segments;
@property (nonatomic, strong) NSMutableSet<NSString *> *skippedSegments;
@property (nonatomic, strong) NSMutableSet<NSString *> *requestedKeys;
+ (instancetype)sharedState;
- (void)updateCID:(long long)cid oid:(long long)oid;
- (void)fetchIfNeeded;
- (void)checkTime:(double)time player:(id)player;
@end

@implementation BLCSponsorState

+ (instancetype)sharedState {
    static BLCSponsorState *state = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        state = [[BLCSponsorState alloc] init];
    });
    return state;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _skippedSegments = [NSMutableSet set];
        _requestedKeys = [NSMutableSet set];
    }
    return self;
}

- (NSString *)av2bv:(long long)aid {
    if (aid <= 0) {
        return nil;
    }
    NSMutableArray<NSString *> *bvid = [NSMutableArray arrayWithCapacity:9];
    for (NSUInteger i = 0; i < 9; i++) {
        [bvid addObject:@""];
    }
    long long value = (BLCMaxAid | aid) ^ BLCXorCode;
    NSInteger base = BLCAlphabet.length;
    for (NSUInteger i = 0; i < 9; i++) {
        NSInteger index = BLCEncodeMap[i];
        NSInteger charIndex = (NSInteger)(value % base);
        bvid[index] = [BLCAlphabet substringWithRange:NSMakeRange((NSUInteger)charIndex, 1)];
        value /= base;
    }
    return [@"BV1" stringByAppendingString:[bvid componentsJoinedByString:@""]];
}

- (void)updateCID:(long long)cid oid:(long long)oid {
    if (cid <= 0 && oid <= 0) {
        return;
    }
    @synchronized (self) {
        long long nextCID = cid > 0 ? cid : self.cid;
        long long nextOID = oid > 0 ? oid : self.oid;
        if ((nextCID > 0 && nextCID != self.cid) || (nextOID > 0 && nextOID != self.oid)) {
            NSLog(@"%@ sponsor identity cid=%lld oid=%lld", BLCLogPrefix, nextCID, nextOID);
        }
        NSString *nextKey = (nextCID > 0 && nextOID > 0) ? [NSString stringWithFormat:@"%lld:%lld", nextOID, nextCID] : nil;
        if (nextKey.length > 0 && ![nextKey isEqualToString:self.videoKey]) {
            self.cid = nextCID;
            self.oid = nextOID;
            self.videoKey = nextKey;
            self.bvid = [self av2bv:nextOID];
            self.segments = nil;
            [self.skippedSegments removeAllObjects];
            [self.requestedKeys removeAllObjects];
            NSLog(@"%@ sponsor video changed bvid=%@ oid=%lld cid=%lld", BLCLogPrefix, self.bvid, self.oid, self.cid);
        } else {
            self.cid = nextCID;
            self.oid = nextOID;
        }
    }
}

- (void)fetchIfNeeded {
    if (![BLCSettings featureEnabled:BLCSponsorSkipEnabledKey defaultValue:YES]) {
        return;
    }
    NSString *key = nil;
    NSString *bvid = nil;
    long long cid = 0;
    @synchronized (self) {
        key = self.videoKey;
        bvid = self.bvid;
        cid = self.cid;
        if (key.length == 0 || bvid.length == 0 || cid <= 0 || [self.requestedKeys containsObject:key]) {
            return;
        }
        [self.requestedKeys addObject:key];
    }
    NSString *urlString = [NSString stringWithFormat:@"https://bsbsb.top/api/skipSegments?videoID=%@&cid=%lld", bvid, cid];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSLog(@"%@ sponsor invalid url %@", BLCLogPrefix, urlString);
        return;
    }
    NSLog(@"%@ sponsor request start key=%@ url=%@", BLCLogPrefix, key, urlString);
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:15.0];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0) {
            NSLog(@"%@ sponsor request failed key=%@ error=%@ bytes=%lu", BLCLogPrefix, key, error.localizedDescription ?: @"nil", (unsigned long)data.length);
            return;
        }
        NSInteger statusCode = 0;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            statusCode = ((NSHTTPURLResponse *)response).statusCode;
            if (statusCode == 404) {
                NSLog(@"%@ sponsor request empty key=%@ status=404", BLCLogPrefix, key);
                return;
            }
        }
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![object isKindOfClass:[NSArray class]]) {
            NSLog(@"%@ sponsor parse ignored key=%@ status=%ld bytes=%lu", BLCLogPrefix, key, (long)statusCode, (unsigned long)data.length);
            return;
        }
        NSMutableArray *segments = [NSMutableArray array];
        for (NSDictionary *item in (NSArray *)object) {
            if (![item isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSString *category = BLCStringValue(item[@"category"]);
            if (category.length > 0 && ![category isEqualToString:@"sponsor"]) {
                continue;
            }
            NSArray *range = item[@"segment"];
            if (![range isKindOfClass:[NSArray class]] || range.count < 2) {
                continue;
            }
            double start = [range[0] doubleValue];
            double end = [range[1] doubleValue];
            if (start >= 0 && end > start) {
                [segments addObject:@{@"start": @(start), @"end": @(end)}];
            }
        }
        @synchronized (self) {
            if ([self.videoKey isEqualToString:key]) {
                self.segments = [segments copy];
                NSLog(@"%@ sponsor request done key=%@ status=%ld segments=%lu", BLCLogPrefix, key, (long)statusCode, (unsigned long)segments.count);
            } else {
                NSLog(@"%@ sponsor stale response key=%@ current=%@", BLCLogPrefix, key, self.videoKey);
            }
        }
    }];
    [task resume];
}

- (void)checkTime:(double)time player:(id)player {
    if (![BLCSettings featureEnabled:BLCSponsorSkipEnabledKey defaultValue:YES] || !player || time <= 0) {
        return;
    }
    NSArray<NSDictionary *> *segments = nil;
    @synchronized (self) {
        segments = self.segments;
    }
    if (segments.count == 0) {
        return;
    }
    double advance = [BLCSettings doubleForKey:BLCSkipAdvanceKey defaultValue:0.25];
    BOOL skipOnce = [BLCSettings boolForKey:BLCSponsorSkipOnceEnabledKey defaultValue:NO];
    for (NSDictionary *segment in segments) {
        double start = [segment[@"start"] doubleValue];
        double end = [segment[@"end"] doubleValue];
        NSString *segmentKey = [NSString stringWithFormat:@"%.3f:%.3f", start, end];
        if (time >= MAX(0, start - advance) && time < end) {
            if (skipOnce) {
                @synchronized (self) {
                    if ([self.skippedSegments containsObject:segmentKey]) {
                        return;
                    }
                    [self.skippedSegments addObject:segmentKey];
                }
            }
            @try {
                SEL selector = @selector(seekTo:withAccurate:);
                if ([player respondsToSelector:selector]) {
                    NSLog(@"%@ sponsor skip current=%.3f start=%.3f end=%.3f advance=%.3f", BLCLogPrefix, time, start, end, advance);
                    ((void (*)(id, SEL, double, BOOL))objc_msgSend)(player, selector, end, YES);
                    NSLog(@"%@ sponsor skip sent end=%.3f", BLCLogPrefix, end);
                } else {
                    NSLog(@"%@ sponsor skip unavailable selector seekTo:withAccurate:", BLCLogPrefix);
                }
            } @catch (NSException *exception) {
                NSLog(@"%@ sponsor seek failed %@", BLCLogPrefix, exception.reason);
            }
            return;
        }
    }
}

@end

@interface BLCSettingsViewController : UITableViewController
@property (nonatomic, assign) NSInteger versionTapCount;
@property (nonatomic, assign) BOOL debugSectionVisible;
@end

@interface BLCKeywordViewController : UITableViewController
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *rules;
@end

@interface BLCKeywordScopeViewController : UITableViewController
@property (nonatomic, assign) NSInteger ruleIndex;
@end

@interface BLCEntryTarget : NSObject
+ (instancetype)sharedTarget;
- (void)openSettings:(id)sender;
@end

@implementation BLCEntryTarget

+ (instancetype)sharedTarget {
    static BLCEntryTarget *target = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        target = [[BLCEntryTarget alloc] init];
    });
    return target;
}

- (UIViewController *)topViewController {
    UIWindow *window = nil;
    for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
        if (candidate.isKeyWindow) {
            window = candidate;
            break;
        }
    }
    if (!window) {
        window = UIApplication.sharedApplication.windows.firstObject;
    }
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController) {
        controller = controller.presentedViewController;
    }
    if ([controller isKindOfClass:[UINavigationController class]]) {
        controller = ((UINavigationController *)controller).topViewController;
    }
    if ([controller isKindOfClass:[UITabBarController class]]) {
        UIViewController *selected = ((UITabBarController *)controller).selectedViewController;
        if ([selected isKindOfClass:[UINavigationController class]]) {
            controller = ((UINavigationController *)selected).topViewController;
        } else {
            controller = selected;
        }
    }
    return controller;
}

- (void)openSettings:(id)sender {
    BLCSettingsViewController *settings = [[BLCSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    settings.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:settings action:@selector(blc_close)];
    [[self topViewController] presentViewController:navigation animated:YES completion:nil];
}

@end

static UIColor *BLCAccentColor(void) {
    return [UIColor colorWithRed:1.0 green:(102.0 / 255.0) blue:(153.0 / 255.0) alpha:1.0];
}

static UISwitch *BLCSwitch(BOOL on, id target, SEL action, NSString *key) {
    UISwitch *aSwitch = [[UISwitch alloc] init];
    aSwitch.on = on;
    aSwitch.onTintColor = BLCAccentColor();
    aSwitch.accessibilityIdentifier = key;
    [aSwitch addTarget:target action:action forControlEvents:UIControlEventValueChanged];
    return aSwitch;
}

@implementation BLCSettingsViewController

- (void)blc_close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"BiliClean";
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationController.navigationBar.prefersLargeTitles = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.debugSectionVisible ? 6 : 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return 6;
    if (section == 2) return 11;
    if (section == 3) return 4;
    if (section == 4) return 3;
    if (section == 5) return 2;
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"总览";
    if (section == 1) return @"播放";
    if (section == 2) return @"屏蔽";
    if (section == 3) return @"首页";
    if (section == 4) return @"界面";
    if (section == 5) return @"调试";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    if (indexPath.section == 0) {
        cell.textLabel.text = @"总开关";
        cell.accessoryView = BLCSwitch([BLCSettings boolForKey:BLCMasterEnabledKey defaultValue:YES], self, @selector(switchChanged:), BLCMasterEnabledKey);
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"跳过赞助片段";
            cell.accessoryView = BLCSwitch([BLCSettings boolForKey:BLCSponsorSkipEnabledKey defaultValue:YES], self, @selector(switchChanged:), BLCSponsorSkipEnabledKey);
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"跳过提前量";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2fs", [BLCSettings doubleForKey:BLCSkipAdvanceKey defaultValue:0.25]];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"不重复跳过已跳片段";
            cell.accessoryView = BLCSwitch([BLCSettings boolForKey:BLCSponsorSkipOnceEnabledKey defaultValue:NO], self, @selector(switchChanged:), BLCSponsorSkipOnceEnabledKey);
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"默认播放速度";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2fx", [BLCSettings doubleForKey:BLCDefaultPlaybackRateKey defaultValue:1.0]];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"CDN 加速";
            cell.detailTextLabel.text = [[BLCCDNManager sharedManager] selectedSummary];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"启用 3 倍速";
            cell.accessoryView = BLCSwitch([BLCSettings boolForKey:BLCPlaybackRateEnabledKey defaultValue:YES], self, @selector(switchChanged:), BLCPlaybackRateEnabledKey);
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    } else if (indexPath.section == 2) {
        NSArray *titles = @[
            @"移除开屏和其他广告",
            @"关键词屏蔽",
            @"关键词规则",
            @"移除播放器下广告",
            @"移除UP主分享好物",
            @"移除UP主带货评论",
            @"移除相关推荐广告",
            @"移除片尾推荐广告",
            @"移除商品带货动态",
            @"移除充电专属动态",
            @"移除直播推荐动态"
        ];
        cell.textLabel.text = titles[indexPath.row];
        NSArray *keys = @[
            BLCAdBlockEnabledKey,
            BLCKeywordBlockEnabledKey,
            [NSNull null],
            BLCPlayerAdStripBlockEnabledKey,
            BLCPruneMerchandiseModuleEnabledKey,
            BLCPruneCommentCommerceEnabledKey,
            BLCPlayerRelatedAdBlockEnabledKey,
            BLCPlayerEndPageAdBlockEnabledKey,
            BLCPruneDynamicUpAdEnabledKey,
            BLCPruneDynamicOnlyFansEnabledKey,
            BLCPruneDynamicLiveRcmdEnabledKey
        ];
        if (indexPath.row == 2) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu 条", (unsigned long)[BLCSettings keywordRules].count];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            NSString *key = keys[indexPath.row];
            cell.accessoryView = BLCSwitch([BLCSettings boolForKey:key defaultValue:YES], self, @selector(switchChanged:), key);
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    } else if (indexPath.section == 3) {
        NSArray *titles = @[
            @"移除视频推荐理由",
            @"移除首页图文推荐",
            @"移除首页直播推荐",
            @"屏蔽竖屏模式"
        ];
        NSArray *keys = @[
            BLCPruneFeedReasonEnabledKey,
            BLCPruneFeedPictureEnabledKey,
            BLCPruneHomeLiveEnabledKey,
            BLCVerticalBlockEnabledKey
        ];
        NSString *key = keys[indexPath.row];
        cell.textLabel.text = titles[indexPath.row];
        cell.accessoryView = BLCSwitch([BLCSettings boolForKey:key defaultValue:YES], self, @selector(switchChanged:), key);
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 4) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"移除互动弹幕";
            cell.accessoryView = BLCSwitch([BLCSettings boolForKey:BLCPlayerFloatingBlockEnabledKey defaultValue:YES], self, @selector(switchChanged:), BLCPlayerFloatingBlockEnabledKey);
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            BLCTabManager *tabManager = [BLCTabManager sharedManager];
            cell.textLabel.text = @"TAB 板块";
            cell.detailTextLabel.text = tabManager.totalItemCount > 0
                ? [NSString stringWithFormat:@"%lu/%lu 显示", (unsigned long)tabManager.visibleItemCount, (unsigned long)tabManager.totalItemCount]
                : @"等待配置";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"移除不常用服务";
            cell.accessoryView = BLCSwitch([BLCSettings boolForKey:BLCPruneUnusedServicesEnabledKey defaultValue:YES], self, @selector(switchChanged:), BLCPruneUnusedServicesEnabledKey);
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    } else if (indexPath.section == 5) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"调试服务";
            cell.accessoryView = BLCSwitch([BLCSettings boolForKey:BLCDebugEnabledKey defaultValue:NO], self, @selector(debugSwitchChanged:), BLCDebugEnabledKey);
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.textLabel.text = @"浏览器地址";
            cell.detailTextLabel.text = [[BLCDebugServer sharedServer] addressString];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    }
    return cell;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section != 4) {
        return nil;
    }
    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = @"BiliClean 1.0.28\nahaduoduoduo";
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    label.textColor = [UIColor secondaryLabelColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 2;
    label.userInteractionEnabled = YES;
    [label addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleVersionFooterTap:)]];
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:16.0],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-16.0]
    ]];
    return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (section == 4) {
        return 64.0;
    }
    return 0.01;
}

- (void)switchChanged:(UISwitch *)sender {
    [BLCSettings setBool:sender.isOn forKey:sender.accessibilityIdentifier];
}

- (void)debugSwitchChanged:(UISwitch *)sender {
    [BLCSettings setBool:sender.isOn forKey:BLCDebugEnabledKey];
    if (sender.isOn) {
        [[BLCDebugServer sharedServer] start];
    } else {
        [[BLCDebugServer sharedServer] stop];
    }
    [self.tableView reloadData];
}

- (void)handleVersionFooterTap:(UITapGestureRecognizer *)gesture {
    if (self.debugSectionVisible) {
        return;
    }
    self.versionTapCount += 1;
    if (self.versionTapCount < 5) {
        return;
    }
    self.versionTapCount = 0;
    self.debugSectionVisible = YES;
    [self.tableView insertSections:[NSIndexSet indexSetWithIndex:5] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && indexPath.row == 1) {
        [self editSkipAdvance];
    } else if (indexPath.section == 1 && indexPath.row == 3) {
        [self chooseDefaultRate];
    } else if (indexPath.section == 1 && indexPath.row == 4) {
        BLCCDNSettingsViewController *controller = [[BLCCDNSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        [self.navigationController pushViewController:controller animated:YES];
    } else if (indexPath.section == 2 && indexPath.row == 2) {
        BLCKeywordViewController *controller = [[BLCKeywordViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        [self.navigationController pushViewController:controller animated:YES];
    } else if (indexPath.section == 4 && indexPath.row == 1) {
        BLCTabSettingsViewController *controller = [[BLCTabSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        [self.navigationController pushViewController:controller animated:YES];
    }
}

- (void)editSkipAdvance {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"跳过提前量" message:@"单位：秒" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.keyboardType = UIKeyboardTypeDecimalPad;
        textField.text = [NSString stringWithFormat:@"%.2f", [BLCSettings doubleForKey:BLCSkipAdvanceKey defaultValue:0.25]];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        double value = alert.textFields.firstObject.text.doubleValue;
        value = MIN(MAX(value, 0.0), 10.0);
        [BLCSettings setDouble:value forKey:BLCSkipAdvanceKey];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)chooseDefaultRate {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"默认播放速度" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSNumber *> *rates = BLCDefaultPlaybackRateOptions();
    for (NSNumber *rate in rates) {
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%.2fx", rate.doubleValue] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [BLCSettings setDouble:rate.doubleValue forKey:BLCDefaultPlaybackRateKey];
            [self.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

@implementation BLCKeywordViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"关键词规则";
    self.rules = [[BLCSettings keywordRules] mutableCopy];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addRule)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.rules = [[BLCSettings keywordRules] mutableCopy];
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.rules.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSDictionary *rule = self.rules[indexPath.row];
    cell.textLabel.text = BLCStringValue(rule[BLCRuleTextKey]);
    NSString *type = [rule[BLCRuleRegexKey] boolValue] ? @"正则" : @"普通关键词";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", type, BLCKeywordScopeSummaryForRule(rule)];
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"每条规则可单独选择应用于推荐、动态和评论区";
}

- (void)addRule {
    UIAlertController *typeSheet = [UIAlertController alertControllerWithTitle:@"添加规则" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [typeSheet addAction:[UIAlertAction actionWithTitle:@"普通关键词" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self showRuleInputRegex:NO];
    }]];
    [typeSheet addAction:[UIAlertAction actionWithTitle:@"正则" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self showRuleInputRegex:YES];
    }]];
    [typeSheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    typeSheet.popoverPresentationController.sourceView = self.view;
    typeSheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:typeSheet animated:YES completion:nil];
}

- (void)showRuleInputRegex:(BOOL)isRegex {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:isRegex ? @"正则" : @"普通关键词" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = isRegex ? @"例如：抽奖|带货" : @"例如：不想看的词";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *text = alert.textFields.firstObject.text;
        if (text.length == 0) {
            return;
        }
        [self.rules addObject:@{BLCRuleTextKey: text, BLCRuleRegexKey: @(isRegex), BLCRuleScopesKey: BLCKeywordScopeIDs()}];
        [BLCSettings setKeywordRules:self.rules];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BLCKeywordScopeViewController *controller = [[BLCKeywordScopeViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    controller.ruleIndex = indexPath.row;
    [self.navigationController pushViewController:controller animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self.rules removeObjectAtIndex:indexPath.row];
        [BLCSettings setKeywordRules:self.rules];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

@end

@implementation BLCKeywordScopeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"应用范围";
}

- (NSDictionary *)rule {
    NSArray<NSDictionary *> *rules = [BLCSettings keywordRules];
    if (self.ruleIndex < 0 || self.ruleIndex >= (NSInteger)rules.count) {
        return nil;
    }
    id rule = rules[(NSUInteger)self.ruleIndex];
    return [rule isKindOfClass:[NSDictionary class]] ? rule : nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return BLCKeywordScopeIDs().count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    NSArray<NSString *> *ids = BLCKeywordScopeIDs();
    NSArray<NSString *> *titles = BLCKeywordScopeTitles();
    NSDictionary *rule = [self rule];
    NSArray<NSString *> *scopes = rule ? BLCKeywordScopesForRule(rule) : @[];
    NSString *scope = ids[indexPath.row];
    cell.textLabel.text = titles[indexPath.row];
    cell.accessoryType = [scopes containsObject:scope] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSDictionary *rule = [self rule];
    NSString *text = BLCStringValue(rule[BLCRuleTextKey]) ?: @"";
    return text.length > 0 ? [NSString stringWithFormat:@"当前规则：%@", text] : nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSMutableArray<NSDictionary *> *rules = [[BLCSettings keywordRules] mutableCopy];
    if (self.ruleIndex < 0 || self.ruleIndex >= (NSInteger)rules.count) {
        return;
    }
    NSDictionary *rule = rules[(NSUInteger)self.ruleIndex];
    if (![rule isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSMutableArray<NSString *> *scopes = [BLCKeywordScopesForRule(rule) mutableCopy];
    NSString *scope = BLCKeywordScopeIDs()[indexPath.row];
    if ([scopes containsObject:scope]) {
        [scopes removeObject:scope];
    } else {
        [scopes addObject:scope];
    }
    NSMutableDictionary *updated = [rule mutableCopy];
    updated[BLCRuleScopesKey] = scopes;
    rules[(NSUInteger)self.ruleIndex] = updated;
    [BLCSettings setKeywordRules:rules];
    [tableView reloadData];
}

@end

static void BLCInstallSettingsEntry(UIViewController *controller) {
    if (![controller isKindOfClass:[UIViewController class]] || !controller.navigationItem) {
        return;
    }
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:@"BiliClean" style:UIBarButtonItemStylePlain target:[BLCEntryTarget sharedTarget] action:@selector(openSettings:)];
    NSMutableArray<UIBarButtonItem *> *items = [controller.navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
    for (UIBarButtonItem *existing in items) {
        if ([existing.title isEqualToString:@"BiliClean"]) {
            return;
        }
    }
    [items insertObject:item atIndex:0];
    controller.navigationItem.rightBarButtonItems = items;
}

@protocol BFCApiMetrics <NSObject>
@end

%group BLCNetworkHooks

%hook BFCRequest

- (id)initWithRequest:(NSURLRequest *)request
             taskType:(unsigned long long)type
             priority:(long long)priority
      progressHandler:(void (^)(long long param1, long long param2, long long param3))progressHandler
       metricsHandler:(void (^)(id<BFCApiMetrics> metrics))metricsHandler
    completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    void (^hookCompletionHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            [[BLCDebugServer sharedServer] emitJSONData:[data copy] URL:response.URL];
            data = BLCFilteredJSONData(data, response);
        }
        if (completionHandler) {
            completionHandler(data, response, error);
        }
    };
    return %orig(request, type, priority, progressHandler, metricsHandler, hookCompletionHandler);
}

%end

%end

%group BLCSplashHooks

%hook BFCSplashLaunchInfo

+ (id)infoWith:(_Bool)with linkAwake:(_Bool)awake inHot:(_Bool)hot {
    if ([BLCSettings featureEnabled:BLCAdBlockEnabledKey defaultValue:YES]) {
        NSLog(@"%@ splash blocked launchFlag=%d linkAwake=%d inHot=%d", BLCLogPrefix, with, awake, hot);
        return %orig(YES, awake, hot);
    }
    return %orig(with, awake, hot);
}

%end

%end

%group BLCPlayerNetworkToastHooks

%hook BBPlayerNetworkPlayerItemRecorder

- (long long)isCellularNetworkToastShowed {
    if ([BLCSettings featureEnabled:BLCPlayerAdStripBlockEnabledKey defaultValue:YES]) {
        return NSIntegerMax;
    }
    return %orig;
}

%end

%end

%group BLCBBAdUGCContextHooks

@interface BBAdUGCContext : NSObject
@end

%hook BBAdUGCContext

- (id)initWithResovler:(id)resovler {
    if ([BLCSettings featureEnabled:BLCPlayerAdStripBlockEnabledKey defaultValue:YES]) {
        return nil;
    }
    return %orig;
}

%end

%end

%group BLCBBAdCommonBaseModelHooks

@interface BBAdCommonBaseModel : NSObject
@end

%hook BBAdCommonBaseModel

+ (id)modelWithMossMessage:(id)message {
    if ([BLCSettings featureEnabled:BLCPlayerAdStripBlockEnabledKey defaultValue:YES]) {
        return nil;
    }
    return %orig;
}

%end

%end

%group BLCPlayerOperationTagHooks

%hook BBPlayerOperationTagService

- (NSArray *)tagModels {
    NSArray *origTagModels = %orig;
    if (![BLCSettings featureEnabled:BLCPlayerAdStripBlockEnabledKey defaultValue:YES]) {
        return origTagModels;
    }
    NSMutableArray *items = [NSMutableArray array];
    for (id item in origTagModels) {
        if (BLCIntegerValueForModelKey(item, @"type") == 1) {
            continue;
        }
        [items addObject:item];
    }
    BLCSetValueForKeyIfAvailable(self, @"_tagModels", items);
    return items;
}

%end

%end

%group BLCViewuniteIntroductionHooks

%hook BAPIAppViewuniteV1IntroductionTab

- (NSMutableArray *)modulesArray {
    NSMutableArray *origModules = %orig;
    if (![origModules isKindOfClass:[NSArray class]]) {
        return origModules;
    }
    BOOL removeDetailModules = [BLCSettings featureEnabled:BLCPlayerAdStripBlockEnabledKey defaultValue:YES];
    if (!removeDetailModules) {
        return origModules;
    }
    NSMutableArray *items = BLCFilteredIntroductionModulesArray(origModules, NO, YES);
    BLCSetValueForKeyIfAvailable(self, @"modulesArray", items);
    return items;
}

%end

%end

%group BLCViewuniteRelatesHooks

%hook BAPIAppViewuniteV1ViewReply

- (id)initWithData:(id)data extensionRegistry:(id)registry error:(id *)error {
    id ret = %orig(data, registry, error);
    if ([BLCSettings featureEnabled:BLCPruneMerchandiseModuleEnabledKey defaultValue:YES]) {
        BLCFilterViewReplyMerchandiseModules(ret);
    }
    if ([BLCSettings featureEnabled:BLCPlayerRelatedAdBlockEnabledKey defaultValue:YES]) {
        BLCFilterViewReplyEmbeddedRelates(ret);
    }
    return ret;
}

%end

%hook BAPIAppViewuniteCommonRelates

- (NSMutableArray *)cardsArray {
    NSMutableArray *origCards = %orig;
    if (![BLCSettings featureEnabled:BLCPlayerRelatedAdBlockEnabledKey defaultValue:YES]) {
        return origCards;
    }
    NSMutableArray *items = [NSMutableArray array];
    for (id item in origCards) {
        if (!BLCShouldRemoveDetailRelateCard(item)) {
            [items addObject:item];
        }
    }
    BLCSetValueForKeyIfAvailable(self, @"cardsArray", items);
    return items;
}

%end

%end

%group BLCViewuniteRelatesFeedHooks

%hook BAPIAppViewuniteV1RelatesFeedReply

- (id)initWithData:(id)data extensionRegistry:(id)registry error:(id *)error {
    id ret = %orig(data, registry, error);
    if ([BLCSettings featureEnabled:BLCPlayerRelatedAdBlockEnabledKey defaultValue:YES]) {
        BLCFilterModelArray(ret, @"relatesArray", ^BOOL(id item) {
            return BLCShouldRemoveDetailRelateCard(item);
        });
    }
    return ret;
}

%end

%end

%group BLCViewuniteEndPageHooks

%hook BAPIAppViewuniteV1ViewEndPageReply

- (id)initWithData:(id)data extensionRegistry:(id)registry error:(id *)error {
    id ret = %orig(data, registry, error);
    if ([BLCSettings featureEnabled:BLCPlayerEndPageAdBlockEnabledKey defaultValue:YES]) {
        BLCFilterViewEndPageReply(ret);
    }
    return ret;
}

%end

%end

%group BLCPlayItemHooks

%hook BBPlayerPlayItem

- (long long)cid {
    long long cid = %orig;
    [[BLCSponsorState sharedState] updateCID:cid oid:0];
    return cid;
}

- (long long)oid {
    long long oid = %orig;
    [[BLCSponsorState sharedState] updateCID:0 oid:oid];
    return oid;
}

%end

%end

%group BLCPlaybackHooks

%hook BBPlayerPlayback

- (double)currentTime {
    double time = %orig;
    BLCDownloadObservePlayback(self);
    if (time > 1.0) {
        [[BLCSponsorState sharedState] fetchIfNeeded];
    }
    [[BLCSponsorState sharedState] checkTime:time player:self];
    return time;
}

- (void)setPlaybackRate:(double)rate {
    if ([BLCSettings featureEnabled:BLCPlaybackRateEnabledKey defaultValue:YES]) {
        double defaultRate = [BLCSettings doubleForKey:BLCDefaultPlaybackRateKey defaultValue:1.0];
        if (fabs(rate - 1.0) < DBL_EPSILON && defaultRate > 0.0 && fabs(defaultRate - 1.0) > DBL_EPSILON) {
            rate = defaultRate;
        }
    }
    %orig(rate);
}

%end

%end

%group BLCInlineOptionsHooks

%hook BPInlinePlayableOptions

- (id)init {
    id ret = %orig;
    if ([BLCSettings featureEnabled:BLCPlaybackRateEnabledKey defaultValue:YES]) {
        double defaultRate = [BLCSettings doubleForKey:BLCDefaultPlaybackRateKey defaultValue:1.0];
        SEL selector = @selector(setRate:);
        if (defaultRate > 0.0 && [ret respondsToSelector:selector]) {
            ((void (*)(id, SEL, double))objc_msgSend)(ret, selector, defaultRate);
        }
    }
    return ret;
}

%end

%end

%group BLCArrayHooks

%hook NSArray

+ (instancetype)arrayWithObjects:(const id *)objects count:(NSUInteger)cnt {
    NSArray *array = %orig(objects, cnt);
    if (![BLCSettings featureEnabled:BLCPlaybackRateEnabledKey defaultValue:YES]) {
        return array;
    }
    if (cnt != 6) {
        return array;
    }
    NSArray<NSNumber *> *expected = @[@0.5, @0.75, @1.0, @1.25, @1.5, @2.0];
    for (NSUInteger index = 0; index < expected.count; index++) {
        id value = array[index];
        if (![value respondsToSelector:@selector(doubleValue)] || fabs([value doubleValue] - expected[index].doubleValue) > 0.001) {
            return array;
        }
    }
    return BLCPlayerPlaybackRateOptions();
}

%end

%end

%group BLCMainCommunityReplyHooks

@interface BAPIMainCommunityReplyV1MainListReply : NSObject
@end

%hook BAPIMainCommunityReplyV1MainListReply

- (id)initWithData:(id)data error:(id *)error {
    id ret = %orig(data, error);
    BLCFilterMainCommunityReply(ret);
    return ret;
}

- (id)initWithData:(id)data extensionRegistry:(id)registry error:(id *)error {
    id ret = %orig(data, registry, error);
    BLCFilterMainCommunityReply(ret);
    return ret;
}

- (id)initWithCodedInputStream:(id)stream extensionRegistry:(id)registry error:(id *)error {
    id ret = %orig(stream, registry, error);
    BLCFilterMainCommunityReply(ret);
    return ret;
}

%end

%end

%group BLCProtobufHooks

%hook GPBMessage

- (id)initWithData:(id)data error:(id *)error {
    id ret = %orig(data, error);
    [[BLCDebugServer sharedServer] emitModel:ret];
    BLCFilterModelObject(ret);
    return ret;
}

- (id)initWithData:(id)data extensionRegistry:(id)registry error:(id *)error {
    id ret = %orig(data, registry, error);
    [[BLCDebugServer sharedServer] emitModel:ret];
    BLCFilterModelObject(ret);
    return ret;
}

- (id)initWithCodedInputStream:(id)stream extensionRegistry:(id)registry error:(id *)error {
    id ret = %orig(stream, registry, error);
    [[BLCDebugServer sharedServer] emitModel:ret];
    BLCFilterModelObject(ret);
    return ret;
}

%end

%end

%group BLCPhoneSettingsHooks

%hook BBPhoneSettingMainVC

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    BLCInstallSettingsEntry((UIViewController *)self);
}

%end

%end

%group BLCHDSettingsHooks

%hook BBHD2PhoneSettingMainVC

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    BLCInstallSettingsEntry((UIViewController *)self);
}

%end

%end

%ctor {
    BLCInstallVideoDownloadHooks();
    [BLCSettings registerDefaults];
    [BLCCDNManager registerDefaults];
    [BLCTabManager registerDefaults];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[BLCTabManager sharedManager] refresh];
    });
    if ([BLCSettings boolForKey:BLCDebugEnabledKey defaultValue:NO]) {
        [[BLCDebugServer sharedServer] start];
    }
    if (objc_getClass("BFCRequest")) {
        %init(BLCNetworkHooks);
    }
    if (objc_getClass("BFCSplashLaunchInfo")) {
        %init(BLCSplashHooks);
    }
    if (objc_getClass("BBPlayerNetworkPlayerItemRecorder")) {
        %init(BLCPlayerNetworkToastHooks);
    }
    if (objc_getClass("BBAdUGCContext")) {
        %init(BLCBBAdUGCContextHooks);
    }
    if (objc_getClass("BBAdCommonBaseModel")) {
        %init(BLCBBAdCommonBaseModelHooks);
    }
    if (objc_getClass("BBPlayerOperationTagService")) {
        %init(BLCPlayerOperationTagHooks);
    }
    if (objc_getClass("BAPIAppViewuniteV1IntroductionTab")) {
        %init(BLCViewuniteIntroductionHooks);
    }
    if (objc_getClass("BAPIAppViewuniteCommonRelates")) {
        %init(BLCViewuniteRelatesHooks);
    }
    if (objc_getClass("BAPIAppViewuniteV1RelatesFeedReply")) {
        %init(BLCViewuniteRelatesFeedHooks);
    }
    if (objc_getClass("BAPIAppViewuniteV1ViewEndPageReply")) {
        %init(BLCViewuniteEndPageHooks);
    }
    if (objc_getClass("BAPIMainCommunityReplyV1MainListReply")) {
        %init(BLCMainCommunityReplyHooks);
    }
    if (objc_getClass("BBPlayerPlayItem")) {
        %init(BLCPlayItemHooks);
    }
    if (objc_getClass("BBPlayerPlayback")) {
        %init(BLCPlaybackHooks);
    }
    if (objc_getClass("BPInlinePlayableOptions")) {
        %init(BLCInlineOptionsHooks);
    }
    %init(BLCArrayHooks);
    if (objc_getClass("GPBMessage")) {
        %init(BLCProtobufHooks);
    }
    if (objc_getClass("BBPhoneSettingMainVC")) {
        %init(BLCPhoneSettingsHooks);
    }
    if (objc_getClass("BBHD2PhoneSettingMainVC")) {
        %init(BLCHDSettingsHooks);
    }
    NSLog(@"%@ loaded", BLCLogPrefix);
}
