//
//  APHLSCache.h
//  video_player
//
//  Created by wooplus on 2021/6/7.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface APHLSCache : NSObject

+ (instancetype)instance;
- (void)setup;

- (void)cleanAllPendingTask;
- (AVURLAsset*)checkIfHasOfflineAsset:(NSURL*)url;
- (AVAssetDownloadTask*)downloadWithURL:(NSURL*)url;
- (void)cancelDownloadWithURL:(NSURL*)url;

@end

NS_ASSUME_NONNULL_END
