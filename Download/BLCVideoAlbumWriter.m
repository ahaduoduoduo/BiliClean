#import "BLCVideoAlbumWriter.h"
#import "BLCDownloadModel.h"
#import <Photos/Photos.h>

@implementation BLCVideoAlbumWriter
+ (void)authorize:(void (^)(NSError *))completion {
    PHAuthorizationStatus read = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    PHAuthorizationStatus add = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
    if (read == PHAuthorizationStatusAuthorized || read == PHAuthorizationStatusLimited || add == PHAuthorizationStatusAuthorized) { completion(nil); return; }
    if (add != PHAuthorizationStatusNotDetermined) { completion(BLCDownloadError(@"请在设置中允许添加照片")); return; }
    if (![[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSPhotoLibraryAddUsageDescription"]) {
        completion(BLCDownloadError(@"IPA 缺少添加照片权限说明")); return;
    }
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus result) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result == PHAuthorizationStatusAuthorized ? nil : BLCDownloadError(@"请在设置中允许添加照片")); });
    }];
}
+ (void)saveVideo:(NSURL *)file completion:(void (^)(NSString *, NSError *))completion {
    // Commit the asset first. Album organization must never block a successful save
    // or cause a retry to create a duplicate video.
    __block NSString *assetID = nil;
    [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
        PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:file];
        assetID = request.placeholderForCreatedAsset.localIdentifier;
    } completionHandler:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!success || !assetID.length) { completion(nil, error ?: BLCDownloadError(@"保存视频失败")); return; }
            PHAuthorizationStatus read = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
            BOOL canUseAlbums = read == PHAuthorizationStatusAuthorized;
            if (@available(iOS 15, *)) canUseAlbums |= read == PHAuthorizationStatusLimited;
            if (!canUseAlbums) { completion(@"照片库", nil); return; }
            [self organizeAsset:assetID completion:completion];
        });
    }];
}
+ (void)organizeAsset:(NSString *)assetID completion:(void (^)(NSString *, NSError *))completion {
    PHAsset *asset = [PHAsset fetchAssetsWithLocalIdentifiers:@[assetID] options:nil].firstObject;
    if (!asset) { completion(@"照片库", nil); return; }
    NSString *key = @"blc.download.album.identifier";
    NSString *savedID = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    PHAssetCollection *album = savedID.length ? [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[savedID] options:nil].firstObject : nil;
    if (![album.localizedTitle isEqualToString:@"BiliBili"] || ![album canPerformEditOperation:PHCollectionEditOperationAddContent]) album = nil;
    if (!album) {
        PHFetchOptions *options = [PHFetchOptions new]; options.predicate = [NSPredicate predicateWithFormat:@"title == %@", @"BiliBili"];
        for (PHAssetCollection *candidate in [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAlbumRegular options:options]) {
            if ([candidate canPerformEditOperation:PHCollectionEditOperationAddContent]) { album = candidate; break; }
        }
    }
    __block NSString *identifier = album.localIdentifier;
    __block BOOL requested = NO;
    [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
        PHAssetCollectionChangeRequest *collection = album ? [PHAssetCollectionChangeRequest changeRequestForAssetCollection:album] : [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:@"BiliBili"];
        if (!collection) return;
        if (!album) identifier = collection.placeholderForCreatedAssetCollection.localIdentifier;
        [collection addAssets:@[asset]];
        requested = YES;
    } completionHandler:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL organized = success && requested;
            if (organized && identifier.length) [[NSUserDefaults standardUserDefaults] setObject:identifier forKey:key];
            completion(organized ? @"BiliBili" : @"照片库", nil);
        });
    }];
}
@end
