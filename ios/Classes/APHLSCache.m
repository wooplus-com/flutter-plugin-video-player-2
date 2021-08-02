//
//  APHLSCache.m
//  video_player
//
//  Created by wooplus on 2021/6/7.
//

#import "APHLSCache.h"

#define kBackgroundIdentifier   @"APlus_Background_Video"
#define kCacheFileName          @"APlusVideoCache"

#define kCacheKeyAssets         @"Assets"
#define kCacheAssetKeyURL       @"assetURL"
#define kCacheAssetKeyLocalFile @"assetLocalFile"

@interface APHLSCache () <AVAssetDownloadDelegate>

@property (nonatomic, strong) NSOperationQueue *queue;
@property (nonatomic, strong) AVAssetDownloadURLSession *downloadSeesion;
@property (nonatomic, strong) NSURLSessionConfiguration *sessionConfiguration;
@property (nonatomic, strong) NSMutableDictionary<NSString*, AVAssetDownloadTask*> *taskMap;

@property (nonatomic, strong) NSUserDefaults *userDefaults;
@property (nonatomic, assign) NSUInteger maxCacheCount;
@property (nonatomic, strong) NSMutableArray<NSDictionary*> *downloadAssetsArray;

@end

@implementation APHLSCache

#pragma mark - Init

+ (instancetype)instance {
    
    static dispatch_once_t onceToken;
    static APHLSCache *instance;
    dispatch_once(&onceToken, ^{
        instance = [APHLSCache new];
    });
    return instance;
}

- (instancetype)init {
    
    if (self = [super init]) {
        
        _taskMap = [NSMutableDictionary dictionary];
        
        _userDefaults = [[NSUserDefaults alloc] initWithSuiteName:kCacheFileName];
        _maxCacheCount = 10;
        
        _downloadAssetsArray = [[_userDefaults objectForKey:kCacheKeyAssets] mutableCopy];
        if (!_downloadAssetsArray) {
            _downloadAssetsArray = [NSMutableArray array];
        }
    }
    return self;
}

- (void)setup {
    
    _queue = [NSOperationQueue new];
    _queue.maxConcurrentOperationCount = 4;
    
    _sessionConfiguration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:kBackgroundIdentifier];
    _downloadSeesion = [AVAssetDownloadURLSession sessionWithConfiguration:_sessionConfiguration assetDownloadDelegate:self delegateQueue:_queue];
}


#pragma mark - Data

- (void)updateAssetURL:(NSURL*)url {
    
    NSDictionary *target;
    for (int i = 0; i < _downloadAssetsArray.count; i++) {
        NSDictionary *dict = _downloadAssetsArray[i];
        // 找到要更新的资源
        if ([dict[kCacheAssetKeyURL] isEqualToString:url.absoluteString]) {
            target = dict;
            NSLog(@"[APHLSCache] update cache from %d to 0", i);
            break;
        }
    }
    
    if (target) {
        
        [_downloadAssetsArray removeObject:target];
        [_downloadAssetsArray insertObject:target atIndex:0];
        [_userDefaults setObject:_downloadAssetsArray forKey:kCacheKeyAssets];
        [_userDefaults synchronize];
    }
}

// 保存资源路径映射
- (void)saveAssetURL:(NSURL*)url localPath:(NSString*)localPath {
    
    NSString *networkPath = url.absoluteString;
    NSDictionary *dict = @{
        kCacheAssetKeyURL: networkPath,
        kCacheAssetKeyLocalFile: localPath,
    };
    [_downloadAssetsArray insertObject:dict atIndex:0];
    
    NSLog(@"[APHLSCache] save %@", dict);
    
    // 超出缓存个数，就移除最后一个
    if (_downloadAssetsArray.count > _maxCacheCount) {
        
        NSLog(@"[APHLSCache] remove last %@", _downloadAssetsArray.lastObject);
        NSURL *lastLocalURL = [NSURL fileURLWithPath:_downloadAssetsArray.lastObject[kCacheAssetKeyLocalFile]];
        [self deleteAssetInDisk:lastLocalURL];
        [_downloadAssetsArray removeLastObject];
    }
    
    [_userDefaults setObject:_downloadAssetsArray forKey:kCacheKeyAssets];
    [_userDefaults synchronize];
}

// 移除资源路径映射
- (void)removeAssetURL:(NSURL*)url {
    
    NSLog(@"[APHLSCache] want to remove %@", url);
    
    NSString *path = url.absoluteString;
    for (int i = 0; i < _downloadAssetsArray.count; i++) {
        NSDictionary *dict = _downloadAssetsArray[i];
        // 找到要删除的资源
        if ([dict[kCacheAssetKeyURL] isEqualToString:path]) {
            NSLog(@"[APHLSCache] remove %@", dict);
            [_downloadAssetsArray removeObjectAtIndex:i];
            [_userDefaults setObject:_downloadAssetsArray forKey:kCacheKeyAssets];
            [_userDefaults synchronize];
            break;
        }
    }
}

// 移除本地资源文件
- (BOOL)deleteAssetInDisk:(NSURL*)url {
    
    @try {
        
        NSError *error;
        [NSFileManager.defaultManager removeItemAtURL:url error:&error];
        if (error) {
            NSLog(@"[APHLSCache] delete %@ error %@", url, error);
            return NO;
        }
        NSLog(@"[APHLSCache] delete success %@", url);
        return YES;
        
    } @catch (NSException *exception) {
        NSLog(@"[APHLSCache] delete %@ exception: %@", url, exception);
        return NO;
    }
}

- (NSString*)findLocalAssetPathWithURL:(NSURL*)url {
    
    NSString *urlPath = url.absoluteString;
    for (NSDictionary *dict in _downloadAssetsArray) {
        if ([dict[kCacheAssetKeyURL] isEqualToString:urlPath]) {
            return dict[kCacheAssetKeyLocalFile];
        }
    }
    return nil;
}

#pragma mark - Operation

- (void)cleanAllPendingTask {
    
    [_downloadSeesion getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> * _Nonnull tasks) {
        for (NSURLSessionTask *task in tasks) {
            [task cancel];
        }
    }];
}

- (AVURLAsset*)checkIfHasOfflineAsset:(NSURL*)url {
    
    NSString *assetPath = [self findLocalAssetPathWithURL:url];
    if (!assetPath) {
        NSLog(@"[APHLSCache] %@ no cache", url);
        return nil;
    }
    
    NSURL *baseURL = [NSURL fileURLWithPath:NSHomeDirectory()];
    NSURL *assetURL = [baseURL URLByAppendingPathComponent:assetPath];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:assetURL options:nil];
    if (asset.assetCache && asset.isPlayable) {
        NSLog(@"[APHLSCache] %@ has cache %@", url, assetPath);
        [self updateAssetURL:url];
        return asset;
    }
    
    NSLog(@"[APHLSCache] %@ cache error", url);
    return nil;
}

- (AVAssetDownloadTask*)downloadWithURL:(NSURL*)url {
    
    NSString *path = url.absoluteString;
    if (_taskMap[path]) {
        return _taskMap[path];
    }
    
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:url options:nil];
//    AVAggregateAssetDownloadTask *task = [_downloadSeesion aggregateAssetDownloadTaskWithURLAsset:asset
//                                                                                  mediaSelections:@[asset.preferredMediaSelection]
//                                                                                       assetTitle:path
//                                                                                 assetArtworkData:nil
//                                                                                          options:nil];
    
    AVAssetDownloadTask *task = [_downloadSeesion assetDownloadTaskWithURLAsset:asset
                                                                     assetTitle:path
                                                               assetArtworkData:nil
                                                                        options:nil];
    
    if (!task) {
        return nil;
    }
    
    [task resume];
    _taskMap[path] = task;
    
    NSLog(@"[APHLSCache] create %@ task", path);
    return task;
}

- (void)cancelDownloadWithURL:(NSURL*)url {
    
    NSString *path = url.absoluteString;
    AVAssetDownloadTask *task = _taskMap[path];
    [task cancel];
    _taskMap[path] = nil;
    
    NSLog(@"[APHLSCache] cancel %@ task", path);
}

#pragma mark - AVAssetDownloadDelegate

//- (void)URLSession:(NSURLSession *)session aggregateAssetDownloadTask:(AVAggregateAssetDownloadTask *)aggregateAssetDownloadTask didLoadTimeRange:(CMTimeRange)timeRange totalTimeRangesLoaded:(NSArray<NSValue *> *)loadedTimeRanges timeRangeExpectedToLoad:(CMTimeRange)timeRangeExpectedToLoad forMediaSelection:(AVMediaSelection *)mediaSelection {
//
//    CGFloat progress = 0;
//    for (NSValue *value in loadedTimeRanges) {
//
//        CMTimeRange timeRange = value.CMTimeRangeValue;
//        CGFloat loadedSecond = timeRange.duration.value / timeRange.duration.timescale;
//        CGFloat totalSecond = timeRangeExpectedToLoad.duration.value / timeRangeExpectedToLoad.duration.timescale;
//        progress += loadedSecond / totalSecond;
//    }
//
//    NSLog(@"[APHLSCache] task %@, progress %f", aggregateAssetDownloadTask.URLAsset.URL.absoluteString, progress);
//}
//
//- (void)URLSession:(NSURLSession *)session aggregateAssetDownloadTask:(AVAggregateAssetDownloadTask *)aggregateAssetDownloadTask willDownloadToURL:(NSURL *)location {
//
//    NSString *path = aggregateAssetDownloadTask.URLAsset.URL.absoluteString;
//    _taskMap[path] = nil;
//    NSLog(@"[APHLSCache] task %@ will download to loacation %@", aggregateAssetDownloadTask.URLAsset.URL, location);
//    [self saveAssetURL:aggregateAssetDownloadTask.URLAsset.URL localPath:location.relativePath];
//}
//
//- (void)URLSession:(NSURLSession *)session aggregateAssetDownloadTask:(AVAggregateAssetDownloadTask *)aggregateAssetDownloadTask didCompleteForMediaSelection:(AVMediaSelection *)mediaSelection {
//
//    NSString *path = aggregateAssetDownloadTask.URLAsset.URL.absoluteString;
//    NSLog(@"[APHLSCache] task %@ finished", path);
//    if (path) {
//        _taskMap[path] = nil;
//    }
//}

// 下载中回调
- (void)URLSession:(NSURLSession *)session assetDownloadTask:(AVAssetDownloadTask *)assetDownloadTask didLoadTimeRange:(CMTimeRange)timeRange totalTimeRangesLoaded:(NSArray<NSValue *> *)loadedTimeRanges timeRangeExpectedToLoad:(CMTimeRange)timeRangeExpectedToLoad {
    
    CGFloat progress = 0;
    for (NSValue *value in loadedTimeRanges) {
        
        CMTimeRange timeRange = value.CMTimeRangeValue;
        CGFloat loadedSecond = timeRange.duration.value / timeRange.duration.timescale;
        CGFloat totalSecond = timeRangeExpectedToLoad.duration.value / timeRangeExpectedToLoad.duration.timescale;
        progress += loadedSecond / totalSecond;
    }
    
    NSLog(@"[APHLSCache] task %@, progress %f", assetDownloadTask.URLAsset.URL.absoluteString, progress);
}

// 完成回调
- (void)URLSession:(NSURLSession *)session assetDownloadTask:(AVAssetDownloadTask *)assetDownloadTask didFinishDownloadingToURL:(NSURL *)location {
    
    NSString *path = assetDownloadTask.URLAsset.URL.absoluteString;
    _taskMap[path] = nil;
    NSLog(@"[APHLSCache] task %@ will download to loacation %@", assetDownloadTask.URLAsset.URL, location);
    [self saveAssetURL:assetDownloadTask.URLAsset.URL localPath:location.relativePath];
}

// 错误
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    
    if ([task isKindOfClass:[AVAssetDownloadTask class]]) {
    
        AVAssetDownloadTask *assetTask = (AVAssetDownloadTask*)task;
        NSString *path = assetTask.URLAsset.URL.absoluteString;
        if (error) {
            NSLog(@"[APHLSCache] task %@ failed, %@", path, error);
        }
        else {
            NSLog(@"[APHLSCache] task %@ success", path);
        }
        if (path) {
            _taskMap[path] = nil;
        }
    }
}

@end
