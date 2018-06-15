//
//  WMDownloadManager.h
//  CoreAnimationDemo
//
//  Created by iwm on 2018/5/28.
//  Copyright © 2018年 Mr.Chen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WMDownloadOperation.h"
#import "WMDownloadCompat.h"
@interface WMDownloadManager : NSObject

+ (instancetype)manager;

- (WMDownloadOperation *)downLoadFileWithURL:(NSString *)url
                                     options:(WMDownloaderOptions)options
                                processBlock:(WMDownloaderProcessBlock)processBlock
                                   completed:(nullable WMDownloaderCompletedBlock)completedBlock;

- (WMDownloadOperation *)downLoadFileWithURL:(NSString *)url
                     removeOldDownloadedFile:(BOOL)canRemoveFile
                                     options:(WMDownloaderOptions)options
                                processBlock:(WMDownloaderProcessBlock)processBlock
                                   completed:(nullable WMDownloaderCompletedBlock)completedBlock;

@end
