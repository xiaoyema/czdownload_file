//
//  WMDownloadManager.m
//  CoreAnimationDemo
//
//  Created by iwm on 2018/5/28.
//  Copyright © 2018年 Mr.Chen. All rights reserved.
//

#import "WMDownloadManager.h"
#import "WMFileDownloader.h"
#import "WMFileManager.h"

NSString * safeString(NSString *str) {
    if (!str || !str.length) {
        return @"";
    }
    return str;
}

NSString *dirDiskLocalPath(NSString *str) {
    if (!str) {
        return @"";
    }
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSLocalDomainMask, YES);
    NSString *documentsDir = [paths firstObject];
    return [documentsDir stringByAppendingString:str];
}


@interface WMDownloadManager()
@property (nonatomic, strong) WMFileDownloader *fileDownloader;
@end

@implementation WMDownloadManager {
    NSLock *_lock;
}

+ (instancetype)manager {
    static WMDownloadManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[WMDownloadManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    if (self = [super init]) {
        [self initilizer];
    }
    return self;
}

- (void)initilizer {
    _lock = [[NSLock alloc] init];
    _fileDownloader = [WMFileDownloader shareFileDownloader];
    [WMFileManager initializeFileManager];
}

- (WMDownloadOperation *)downLoadFileWithURL:(NSString *)url
                    options:(WMDownloaderOptions)options
               processBlock:(WMDownloaderProcessBlock)processBlock
                  completed:(nullable WMDownloaderCompletedBlock)completedBlock {
    
  return [self downLoadFileWithURL:url
            removeOldDownloadedFile:NO
                            options:options
                       processBlock:processBlock
                          completed:completedBlock];
}

- (WMDownloadOperation *)downLoadFileWithURL:(NSString *)url
                     removeOldDownloadedFile:(BOOL)canRemoveFile
                                     options:(WMDownloaderOptions)options
                                processBlock:(WMDownloaderProcessBlock)processBlock
                                   completed:(nullable WMDownloaderCompletedBlock)completedBlock {
    if (!url || !url.length) {
        return nil;
    }
    if (canRemoveFile) {
        [WMFileManager removeDocumentDownloadedDataWithURL:url];
    }
    //本地缓存有没有
    if ([WMFileManager isExitFinishDownloadFileDirWithURL:url]) {
        NSString *path = [WMFileManager  finishedDownloadFileDirWithURL:url];
        if (completedBlock) {
            completedBlock (path, nil, YES);
        }
        return nil;
    }
    return [_fileDownloader downloadFileTaskWithURL:url
                                            options:options
                                       processBlock:processBlock
                                          completed:^(id  _Nullable data, NSError * _Nullable error, BOOL finished) {
                                              safe_dispatch_main_async(^{
                                                  if (completedBlock) {
                                                      completedBlock(data, error, finished);
                                                  }
                                              });
                                          }];
}
@end
