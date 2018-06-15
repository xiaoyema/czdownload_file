//
//  WMFileDownloader.m
//  CoreAnimationDemo
//
//  Created by iwm on 2018/6/5.
//  Copyright © 2018年 Mr.Chen. All rights reserved.
//

#import "WMFileDownloader.h"

#define LOCK(lock) dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
#define UNLOCK(lock) dispatch_semaphore_signal(lock);
#define LOCK [self.lock lock];
#define UNLOCK [self.lock unlock];

@interface WMFileDownloader () <NSURLSessionDelegate, NSURLSessionDelegate, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate, NSURLSessionTaskDelegate>

@property (strong, nonatomic) NSURLSession *session;
@property (strong, nonatomic) NSMutableDictionary *urlDictionary;
@property (strong, nonatomic) NSOperationQueue *downloadQueue;
@property (strong, nonatomic) NSLock *lock;
@property (assign, nonatomic) NSTimeInterval timeoutInterval;
@property (strong, nonatomic) NSOperationQueue *delegateQueue;
@property (strong, nonatomic, nonnull) dispatch_semaphore_t operationsLock;
@end

@implementation WMFileDownloader

static WMFileDownloader *fileDownloader = nil;

+ (instancetype)shareFileDownloader {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fileDownloader = [[WMFileDownloader alloc] init];
    });
    return fileDownloader;
}

- (instancetype)init {
    NSString *backgroundIdentifier = @"backGroundIdentifier";
   return [self initWithSessionConfiguration:[NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:backgroundIdentifier]];
}

- (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)sessionConfiguration {
    if (self = [super init]) {
        [self initilizer];
        [self createNewSessionWithConfiguration:sessionConfiguration];
    }
    return self;
}

- (void)initilizer {
    _downloadQueue = [[NSOperationQueue alloc] init];
    _downloadQueue.maxConcurrentOperationCount = 6;
    
    _delegateQueue = [[NSOperationQueue alloc] init];
    _delegateQueue.maxConcurrentOperationCount = 1;
    
    _urlDictionary = [NSMutableDictionary dictionary];
    
    _timeoutInterval = 15.0f;
    
    _operationsLock = dispatch_semaphore_create(1);
    
    _lock = [[NSLock alloc] init];
}

- (void)createNewSessionWithConfiguration:(NSURLSessionConfiguration *)sessionConfiguration {
    sessionConfiguration.timeoutIntervalForRequest = self.timeoutInterval;
    self.session = [NSURLSession sessionWithConfiguration:sessionConfiguration
                                                 delegate:self
                                            delegateQueue:self.delegateQueue];
}


- (WMDownloadOperation *)downloadFileTaskWithURL:(NSString *)url
                        options:(WMDownloaderOptions)options
                   processBlock:(WMDownloaderProcessBlock)processBlock
                      completed:(WMDownloaderCompletedBlock)completedBlock {
    __weak typeof (self) weakSelf = self;
   return [self createDownloadOperation:url
                                options:(WMDownloaderOptions)options
                    callBackBlock:^WMDownloadOperation *{
        
        __strong typeof (weakSelf) strongSelf = weakSelf;
        NSTimeInterval timeout = strongSelf.timeoutInterval;
        NSURLRequestCachePolicy cachePolicy = options & WMDownloaderOptionsDownloaderUseNSURLCache ? NSURLRequestUseProtocolCachePolicy : NSURLRequestReloadIgnoringLocalCacheData;
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url] cachePolicy:cachePolicy timeoutInterval:timeout];
        request.HTTPShouldUsePipelining = YES;
        WMDownloadOperation *operation = [[WMDownloadOperation alloc] initWithRequest:request inSession:strongSelf.session options:options];

        if (options & WMDownloaderOptionsLowPriority) {
            operation.queuePriority = NSOperationQueuePriorityLow;
        } else if (options & WMDownloaderOptionsHightPriority) {
            operation.queuePriority = NSOperationQueuePriorityHigh;
        }
                        
        [operation addHandlersForCompleted:completedBlock processBlock:processBlock];
        return operation;
    }];
}

- (WMDownloadOperation *)createDownloadOperation:(NSString *)url
                                         options:(WMDownloaderOptions)options
                                   callBackBlock:(WMDownloadOperation * (^)(void))callBackBlock {
    LOCK;
    WMDownloadOperation *operation = [_urlDictionary objectForKey:url];
    if (!operation) {
        operation = callBackBlock();
        __weak typeof(self) weakSelf = self;
        operation.completionBlock = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return ;
            }
            LOCK;
            [strongSelf.urlDictionary removeObjectForKey:url];
            UNLOCK;
            if (options & WMDownloaderOptionsHightPriorityStopLowPriortyOperation) {
                [strongSelf resumeLowPriorityOperaton];
            }
        };
        if (options & WMDownloaderOptionsHightPriorityStopLowPriortyOperation) {
            [self stopLowPriorityOperation];
        }
        [self.urlDictionary setObject:operation forKey:url];
        [self.downloadQueue addOperation:operation];
    } else {
        
    }
    UNLOCK;
    return operation;
}

- (void)stopLowPriorityOperation {
    for (WMDownloadOperation *operation in  self.downloadQueue.operations) {
        if (operation.queuePriority == NSOperationQueuePriorityLow) {
            [operation pause];
        }
    }
}

- (void)resumeLowPriorityOperaton {
    for (WMDownloadOperation *operation in  self.downloadQueue.operations) {
        if (operation.queuePriority == NSOperationQueuePriorityLow) {
            [operation resume];
        }
    }
}

- (WMDownloadOperation *)operationWithTask:(NSURLSessionTask *)task {
    WMDownloadOperation *returnOperation = nil;
    for (WMDownloadOperation *operation in self.downloadQueue.operations) {
        if (operation.dataTask.taskIdentifier == task.taskIdentifier) {
            returnOperation = operation;
            break;
        }
    }
    return returnOperation;
}

#pragma mark NSURLSessionDelegate

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {

}

#pragma mark NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    
    // Identify the operation that runs this task and pass it the delegate method
    WMDownloadOperation *dataOperation = [self operationWithTask:dataTask];
    if ([dataOperation respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)]) {
        [dataOperation URLSession:session dataTask:dataTask didReceiveResponse:response completionHandler:completionHandler];
    } else {
        if (completionHandler) {
            completionHandler(NSURLSessionResponseAllow);
        }
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    
    // Identify the operation that runs this task and pass it the delegate method
    WMDownloadOperation *dataOperation = [self operationWithTask:dataTask];
    if ([dataOperation respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
        [dataOperation URLSession:session dataTask:dataTask didReceiveData:data];
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler {
    
    // Identify the operation that runs this task and pass it the delegate method
    WMDownloadOperation *dataOperation = [self operationWithTask:dataTask];
    if ([dataOperation respondsToSelector:@selector(URLSession:dataTask:willCacheResponse:completionHandler:)]) {
        [dataOperation URLSession:session dataTask:dataTask willCacheResponse:proposedResponse completionHandler:completionHandler];
    } else {
        if (completionHandler) {
            completionHandler(proposedResponse);
        }
    }
}

#pragma mark NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    
    // Identify the operation that runs this task and pass it the delegate method
    WMDownloadOperation *dataOperation = [self operationWithTask:task];
    if ([dataOperation respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
        [dataOperation URLSession:session task:task didCompleteWithError:error];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    
    // Identify the operation that runs this task and pass it the delegate method
    WMDownloadOperation *dataOperation = [self operationWithTask:task];
    if ([dataOperation respondsToSelector:@selector(URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:)]) {
        [dataOperation URLSession:session task:task willPerformHTTPRedirection:response newRequest:request completionHandler:completionHandler];
    } else {
        if (completionHandler) {
            completionHandler(request);
        }
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    
    // Identify the operation that runs this task and pass it the delegate method
    WMDownloadOperation *dataOperation = [self operationWithTask:task];
    if ([dataOperation respondsToSelector:@selector(URLSession:task:didReceiveChallenge:completionHandler:)]) {
        [dataOperation URLSession:session task:task didReceiveChallenge:challenge completionHandler:completionHandler];
    } else {
        if (completionHandler) {
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        }
    }
}

#pragma mark NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    WMDownloadOperation *dataOperation = [self operationWithTask:downloadTask];
    if ([dataOperation respondsToSelector:@selector(URLSession:downloadTask:didFinishDownloadingToURL:)]) {
        [dataOperation URLSession:session
                     downloadTask:downloadTask
        didFinishDownloadingToURL:location];
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    WMDownloadOperation *dataOperation = [self operationWithTask:downloadTask];
    if ([dataOperation respondsToSelector:@selector(URLSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)]) {
        [dataOperation URLSession:session
                     downloadTask:downloadTask
                     didWriteData:bytesWritten
                totalBytesWritten:totalBytesWritten
        totalBytesExpectedToWrite:totalBytesExpectedToWrite];
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes {
    WMDownloadOperation *dataOperation = [self operationWithTask:downloadTask];
    if ([dataOperation respondsToSelector:@selector(URLSession:downloadTask:didResumeAtOffset:expectedTotalBytes:)]) {
        [dataOperation URLSession:session downloadTask:downloadTask
                didResumeAtOffset:fileOffset
               expectedTotalBytes:expectedTotalBytes];
    }
}


@end
