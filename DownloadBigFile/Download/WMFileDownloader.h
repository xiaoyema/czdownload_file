//
//  WMFileDownloader.h
//  CoreAnimationDemo
//
//  Created by iwm on 2018/6/5.
//  Copyright © 2018年 Mr.Chen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WMDownloadOperation.h"

@interface WMFileDownloader : NSObject

@property (strong, nonatomic, readonly) NSURLSession *session;

+ (instancetype)shareFileDownloader;

- (WMDownloadOperation *)downloadFileTaskWithURL:(NSString *)url
                                         options:(WMDownloaderOptions)options
                                    processBlock:(WMDownloaderProcessBlock)processBlock
                                       completed:(WMDownloaderCompletedBlock)completedBlock;

@end
