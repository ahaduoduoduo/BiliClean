#import <Foundation/Foundation.h>
@interface BLCVideoAlbumWriter : NSObject
// Calls back on main. A completed authorization can be ignored by the caller
// when its task was cancelled, before any Photos mutation begins.
+ (void)authorize:(void (^)(NSError *))completion;
// Returns the actual destination after the video is saved. Album failure falls back to the library.
+ (void)saveVideo:(NSURL *)file completion:(void (^)(NSString *destination, NSError *error))completion;
@end
