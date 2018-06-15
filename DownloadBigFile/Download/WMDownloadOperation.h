//
//  WMDownloadOperation.h
//  CoreAnimationDemo
//
//  Created by iwm on 2018/6/5.
//  Copyright © 2018年 Mr.Chen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef void (^WMDownloaderCompletedBlock)(id data, NSError *_Nullable error, BOOL finished) ;
typedef void (^WMDownloaderProcessBlock)(CGFloat processRatio, NSError *_Nullable error) ;

typedef NS_ENUM(NSUInteger, WMDownloaderOptions) {
    WMDownloaderOptionsDefultPriority                                = 1 << 0,
    WMDownloaderOptionsLowPriority                                   = 1 << 1,
    WMDownloaderOptionsHightPriority                                 = 1 << 2,
    WMDownloaderOptionsDownloaderUseNSURLCache                       = 1 << 3,
    WMDownloaderOptionsDownloaderBigFile                             = 1 << 4,
    WMDownloaderOptionsAllowInvalidSSLCertificates                   = 1 << 5,
    WMDownloaderOptionsHightPriorityStopLowPriortyOperation          = 1 << 6,
};

@interface WMDownloadOperation : NSOperation <NSURLSessionDelegate, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate>

@property (nonatomic, strong, nullable) NSURLSessionTask *dataTask;

- (void)addHandlersForCompleted:(WMDownloaderCompletedBlock)completedBlock
                   processBlock:(WMDownloaderProcessBlock)processBlock;

- (void)pause;

- (void)resume;

- (void)cancel;

- (instancetype)initWithRequest:(NSURLRequest *)request
                      inSession:(NSURLSession *)session
                        options:(WMDownloaderOptions)options;

@end
