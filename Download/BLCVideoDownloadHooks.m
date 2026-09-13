#import "BLCVideoDownloadManager.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static NSHashTable *BLCPlaybacks;
static NSLock *BLCPlaybackLock;
static const char BLCPlaybackObserved;
void BLCDownloadObservePlayback(id playback) {
    if (!playback || objc_getAssociatedObject(playback, &BLCPlaybackObserved)) return;
    static dispatch_once_t once; dispatch_once(&once, ^{ BLCPlaybacks = [NSHashTable weakObjectsHashTable]; BLCPlaybackLock = [NSLock new]; });
    [BLCPlaybackLock lock]; [BLCPlaybacks addObject:playback]; [BLCPlaybackLock unlock];
    objc_setAssociatedObject(playback, &BLCPlaybackObserved, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static BOOL BLCDownloadEnabled(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:@"blc.master.enabled"];
    return value == nil || [value boolValue];
}
static UIViewController *BLCDownloadOwner(UICollectionView *view, id *panel) {
    UIViewController *owner = nil; *panel = nil;
    for (UIResponder *r = view; r; r = r.nextResponder) {
        if ([NSStringFromClass(r.class) isEqualToString:@"VKSwipe.SwipeViewController"]) *panel = r;
        if ([r isKindOfClass:NSClassFromString(@"BBVDDetailVC")]) owner = (UIViewController *)r;
    }
    return owner;
}
static id BLCDownloadItemForView(UIView *view) {
    [BLCPlaybackLock lock]; NSArray *players = BLCPlaybacks.allObjects; [BLCPlaybackLock unlock];
    NSMutableArray *matches = [NSMutableArray array];
    for (id playback in players) {
        id render = BLCDownloadValue(playback, @"view");
        if (![render isKindOfClass:UIView.class] || ![render isDescendantOfView:view] || ![(UIView *)render window]) continue;
        id item = BLCDownloadValue(playback, @"currentItem");
        if (![item isKindOfClass:NSClassFromString(@"BBPlayerPlayItem")]) continue;
        if ([BLCDownloadValue(playback, @"isGetFocus") boolValue]) return item;
        [matches addObject:item];
    }
    return matches.count == 1 ? matches.firstObject : nil;
}
// Keep the native channel array untouched. A missing download channel gets one
// independent third cell; native callbacks keep their original channel indices.
static const char BLCInsertedDownloadKey;
static const char BLCShareDequeueIndexKey;
@interface BLCDownloadShareCell : UICollectionViewCell
@property(nonatomic, strong) UIImageView *icon;
@property(nonatomic, strong) UILabel *label;
@end
@implementation BLCDownloadShareCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down.to.line"]];
    _icon.tintColor = UIColor.whiteColor; _icon.contentMode = UIViewContentModeCenter;
    _icon.backgroundColor = [UIColor colorWithRed:0.50 green:0.44 blue:0.92 alpha:1]; _icon.layer.cornerRadius = 22;
    _label = [UILabel new]; _label.text = @"下载视频"; _label.font = [UIFont systemFontOfSize:12];
    _label.textAlignment = NSTextAlignmentCenter; _label.textColor = UIColor.secondaryLabelColor;
    [self.contentView addSubview:_icon]; [self.contentView addSubview:_label];
    self.isAccessibilityElement = YES; self.accessibilityLabel = @"下载完整视频"; self.accessibilityTraits = UIAccessibilityTraitButton;
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat width = CGRectGetWidth(self.contentView.bounds);
    self.icon.frame = CGRectMake((width - 44) / 2, 0, 44, 44);
    self.label.frame = CGRectMake(0, 53, width, 16);
}
@end
static BOOL BLCIsInsertedDownload(UICollectionView *view, NSIndexPath *index) {
    NSNumber *position = objc_getAssociatedObject(view, &BLCInsertedDownloadKey);
    return position && index.section == 0 && index.item == position.integerValue;
}
static NSIndexPath *BLCNativeShareIndex(UICollectionView *view, NSIndexPath *index) {
    NSNumber *position = objc_getAssociatedObject(view, &BLCInsertedDownloadKey);
    if (position && index.section == 0 && index.item > position.integerValue) return [NSIndexPath indexPathForItem:index.item - 1 inSection:0];
    return index;
}
static id (*BLCOriginalDequeue)(UICollectionView *, SEL, NSString *, NSIndexPath *);
static id BLCDownloadDequeue(UICollectionView *view, SEL selector, NSString *identifier, NSIndexPath *index) {
    NSIndexPath *requested = objc_getAssociatedObject(view, &BLCShareDequeueIndexKey);
    return BLCOriginalDequeue(view, selector, identifier, requested ?: index);
}
static NSInteger (*BLCOriginalCount)(id, SEL, UICollectionView *, NSInteger);
static NSInteger BLCDownloadCount(id source, SEL selector, UICollectionView *view, NSInteger section) {
    NSInteger count = BLCOriginalCount(source, selector, view, section);
    if (section != 0) return count;
    id panel = nil; BOOL insert = BLCDownloadEnabled() && BLCDownloadOwner(view, &panel) && panel;
    for (id channel in BLCDownloadValue(source, @"channels")) if ([BLCDownloadValue(channel, @"channel") integerValue] == 71) { insert = NO; break; }
    objc_setAssociatedObject(view, &BLCInsertedDownloadKey, insert ? @(MIN(2, count)) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return count + (insert ? 1 : 0);
}
static void (*BLCOriginalSelect)(id, SEL, UICollectionView *, NSIndexPath *);
static void BLCDownloadSelectChannel(id source, SEL selector, UICollectionView *view, NSIndexPath *index) {
    BOOL inserted = BLCIsInsertedDownload(view, index);
    NSIndexPath *nativeIndex = BLCNativeShareIndex(view, index);
    NSArray *channels = BLCDownloadValue(source, @"channels"); id panel = nil;
    UIViewController *owner = BLCDownloadOwner(view, &panel);
    BOOL download = inserted || (nativeIndex.section == 0 && nativeIndex.item < channels.count && [BLCDownloadValue(channels[nativeIndex.item], @"channel") integerValue] == 71);
    if (!BLCDownloadEnabled() || !owner || !panel || !download) {
        if (!inserted) BLCOriginalSelect(source, selector, view, nativeIndex); return;
    }
    id item = BLCDownloadItemForView(owner.view);
    int64_t aid = [BLCDownloadValue(item, @"oid") longLongValue], cid = [BLCDownloadValue(item, @"cid") longLongValue];
    UIWindow *window = view.window;
    SEL dismiss = NSSelectorFromString(@"dismissPoper:");
    if (!window || ![panel respondsToSelector:dismiss]) { if (!inserted) BLCOriginalSelect(source, selector, view, nativeIndex); return; }
    ((void (*)(id, SEL, BOOL))objc_msgSend)(panel, dismiss, YES);
    [[BLCVideoDownloadManager sharedManager] startAID:aid cid:cid window:window];
}
static id (*BLCOriginalCell)(id, SEL, UICollectionView *, NSIndexPath *);
static id BLCDownloadCell(id source, SEL selector, UICollectionView *view, NSIndexPath *index) {
    if (BLCIsInsertedDownload(view, index)) {
        [view registerClass:BLCDownloadShareCell.class forCellWithReuseIdentifier:@"BiliClean.DownloadShare"];
        return [view dequeueReusableCellWithReuseIdentifier:@"BiliClean.DownloadShare" forIndexPath:index];
    }
    NSIndexPath *nativeIndex = BLCNativeShareIndex(view, index);
    id cell = nil; id panel = nil;
    // Channel lookup uses the original index, but UIKit must dequeue for the
    // actual displayed index (including iOS versions with strict dequeue checks).
    id previous = objc_getAssociatedObject(view, &BLCShareDequeueIndexKey);
    objc_setAssociatedObject(view, &BLCShareDequeueIndexKey, index, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try { cell = BLCOriginalCell(source, selector, view, nativeIndex); }
    @finally { objc_setAssociatedObject(view, &BLCShareDequeueIndexKey, previous, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    NSArray *channels = BLCDownloadValue(source, @"channels");
    if (BLCDownloadEnabled() && BLCDownloadOwner(view, &panel) && index.section == 0 && nativeIndex.item < channels.count && [BLCDownloadValue(channels[nativeIndex.item], @"channel") integerValue] == 71) {
        UILabel *label = BLCDownloadValue(cell, @"titleLabel"); if ([label isKindOfClass:UILabel.class]) label.text = @"下载视频";
        [cell setAccessibilityLabel:@"下载完整视频"];
    }
    return cell;
}
static void (*BLCOriginalWillDisplay)(id, SEL, UICollectionView *, UICollectionViewCell *, NSIndexPath *);
static void BLCDownloadWillDisplay(id source, SEL selector, UICollectionView *view, UICollectionViewCell *cell, NSIndexPath *index) {
    if (BLCIsInsertedDownload(view, index)) return;
    BLCOriginalWillDisplay(source, selector, view, cell, BLCNativeShareIndex(view, index));
}
static void BLCRefreshShareViews(UIView *view) {
    if ([view isKindOfClass:UICollectionView.class]) {
        UICollectionView *collection = (id)view;
        if ([NSStringFromClass([(id)collection.dataSource class]) isEqualToString:@"BFCShareContentViewLib.ShareContentView"]) [collection reloadData];
    }
    for (UIView *child in view.subviews) BLCRefreshShareViews(child);
}
static void (*BLCOriginalShareWindow)(UIView *, SEL);
static void BLCDownloadShareWindow(UIView *self, SEL selector) {
    BLCOriginalShareWindow(self, selector);
    if (self.window) dispatch_async(dispatch_get_main_queue(), ^{ if (self.window) BLCRefreshShareViews(self); });
}
static void (*BLCOriginalSetItem)(id, SEL, id);
static void BLCDownloadSetItem(id self, SEL selector, id item) { BLCOriginalSetItem(self, selector, item); BLCDownloadObservePlayback(self); }
void BLCInstallVideoDownloadHooks(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{
        Class source = NSClassFromString(@"BFCShareContentViewLib.ShareContentView"), playback = NSClassFromString(@"BBPlayerPlayback");
        SEL select = @selector(collectionView:didSelectItemAtIndexPath:), cell = @selector(collectionView:cellForItemAtIndexPath:), item = NSSelectorFromString(@"setCurrentItem:");
        MSHookMessageEx(UICollectionView.class, @selector(dequeueReusableCellWithReuseIdentifier:forIndexPath:), (IMP)BLCDownloadDequeue, (IMP *)&BLCOriginalDequeue);
        SEL count = @selector(collectionView:numberOfItemsInSection:), display = @selector(collectionView:willDisplayCell:forItemAtIndexPath:);
        Class content = NSClassFromString(@"BBVideoModule.ShareContent");
        if (class_getInstanceMethod(source, count)) MSHookMessageEx(source, count, (IMP)BLCDownloadCount, (IMP *)&BLCOriginalCount);
        if (class_getInstanceMethod(source, display)) MSHookMessageEx(source, display, (IMP)BLCDownloadWillDisplay, (IMP *)&BLCOriginalWillDisplay);
        if (class_getInstanceMethod(content, @selector(didMoveToWindow))) MSHookMessageEx(content, @selector(didMoveToWindow), (IMP)BLCDownloadShareWindow, (IMP *)&BLCOriginalShareWindow);
        if (class_getInstanceMethod(source, select)) MSHookMessageEx(source, select, (IMP)BLCDownloadSelectChannel, (IMP *)&BLCOriginalSelect);
        if (class_getInstanceMethod(source, cell)) MSHookMessageEx(source, cell, (IMP)BLCDownloadCell, (IMP *)&BLCOriginalCell);
        if (class_getInstanceMethod(playback, item)) MSHookMessageEx(playback, item, (IMP)BLCDownloadSetItem, (IMP *)&BLCOriginalSetItem);
    });
}
