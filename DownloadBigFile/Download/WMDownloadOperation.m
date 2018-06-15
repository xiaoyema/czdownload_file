//
//  WMDownloadOperation.m
//  CoreAnimationDemo
//
//  Created by iwm on 2018/6/5.
//  Copyright © 2018年 Mr.Chen. All rights reserved.
//

#import "WMDownloadOperation.h"
#import "WMDownloadCompat.h"
#import <CommonCrypto/CommonDigest.h>
#import "WMFileManager.h"

static NSString *const kCompletedCallBackKey = @"completed";
static NSString *const kProcessCallBackKey = @"process";

NSString *const kDownloadErrorDomain = @"downloadErrorDomain";

@interface WMDownloadOperation ()

@property (nonatomic, strong) NSURLRequest *request;

@property (nonatomic, strong) NSURLSession *ownedSession;

@property (nonatomic, strong) NSMutableArray <NSMutableDictionary *> *callBackArr;

@property (nonatomic, strong) NSLock *lock;

@property (nonatomic, assign) NSUInteger expectedSize;

@property (nonatomic, strong) NSMutableData *downloadData;

@property (nonatomic, assign) WMDownloaderOptions options;

@property (readonly, getter=isFinished) BOOL finished;

@property (assign, nonatomic, getter = isExecuting) BOOL executing;

@property (strong, nonatomic) NSData *resumeData;

@property (strong, nonatomic) NSString *localTempFileName;

@property (weak, nonatomic) NSTimer *timer;

@end

@implementation WMDownloadOperation {
    NSString *_downloadUrl;
    NSString *_tempFilePath;
}

@synthesize finished = _finished;
@synthesize executing = _executing;

- (instancetype)init {
    return [self initWithRequest:nil inSession:nil options:WMDownloaderOptionsDefultPriority];
}

- (instancetype)initWithRequest:(NSURLRequest *)request
                      inSession:(NSURLSession *)session
                        options:(WMDownloaderOptions)options {
    if (self = [super init]) {
        _request = [request copy];
        _ownedSession = session;
        _callBackArr = [NSMutableArray array];
        _downloadData = [NSMutableData data];
        _options = options;
        _finished = NO;
        _lock = [[NSLock alloc] init];
        _downloadUrl = request.URL.absoluteString;
        
        NSLog(@"rootDoumentDir:%@",[WMFileManager rootDoumentDir]);
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(willEnterBackground) name:UIApplicationWillResignActiveNotification
                                                   object:nil];
    }
    return self;
}

- (void)start {
    NSURLSession *session = self.ownedSession;
    if (_options & WMDownloaderOptionsDownloaderBigFile) {
        [self _resume_inner];
    } else {
        self.dataTask = [session dataTaskWithRequest:self.request];
        [self.dataTask resume];
    }
}
- (void)resume {
    if (self.executing) return;
    [self _resume_inner];
}

- (void)_resume_inner {
    if (!(_options & WMDownloaderOptionsDownloaderBigFile)) return;
    self.executing = YES;
    NSData *resumeD = nil;
    if (self.resumeData) {
        resumeD = self.resumeData;
    } else {
        resumeD = [WMFileManager readTempDownloadingDataFromDiskWithURL:_downloadUrl];
    }
    if (!resumeD) {
        self.dataTask = [self.ownedSession downloadTaskWithRequest:self.request];
    } else {
        self.dataTask = [self.ownedSession downloadTaskWithResumeData:resumeD];
    }
    [self.dataTask resume];
}

- (void)pause {
    if (!(_options & WMDownloaderOptionsDownloaderBigFile)) return;
    if (!self.executing) return;
    self.executing = NO;
    __weak typeof(self) weakSelf = self;
    [(NSURLSessionDownloadTask *)self.dataTask cancelByProducingResumeData:^(NSData * _Nullable resumeData) {
        [WMFileManager saveTempDownloadDataToDisk:resumeData url:_downloadUrl tempFilePath:_tempFilePath];
        [WMFileManager moveTempFileToDocumentDownloadDir];
        weakSelf.resumeData = resumeData;
        weakSelf.dataTask = nil;
    }];
}

- (void)_pause_inner {
    if (!(_options & WMDownloaderOptionsDownloaderBigFile)) return;
    self.executing = NO;
    __weak typeof(self) weakSelf = self;
    [(NSURLSessionDownloadTask *)self.dataTask cancelByProducingResumeData:^(NSData * _Nullable resumeData) {
        [WMFileManager saveTempDownloadDataToDisk:resumeData url:_downloadUrl tempFilePath:_tempFilePath];
        [WMFileManager moveTempFileToDocumentDownloadDir];
        weakSelf.resumeData = resumeData;
        weakSelf.dataTask = nil;
        [weakSelf resume];
    }];
}

- (void)reset {
    [self.lock lock];
    [self.callBackArr removeAllObjects];
    [self.lock unlock];
    self.finished = YES;
    self.executing = NO;
    self.dataTask = nil;
    self.ownedSession = nil;
}

- (void)cancel {
    @synchronized (self) {
        [self cancelInternal];
    }
}

- (void)cancelInternal {
    if (self.isFinished) return;
    [super cancel];
    
    if (self.dataTask) {
        [self.dataTask cancel];
    }
    [self reset];
}

- (void)setExecuting:(BOOL)executing {
    [self willChangeValueForKey:@"isExecuting"];
    _executing = executing;
    [self didChangeValueForKey:@"isExecuting"];
}

- (void)setFinished:(BOOL)finished {
    [self willChangeValueForKey:@"isFinished"];
    _finished = finished;
    [self didChangeValueForKey:@"isFinished"];
}

- (void)addHandlersForCompleted:(WMDownloaderCompletedBlock)completedBlock
                   processBlock:(WMDownloaderProcessBlock)processBlock {
    NSMutableDictionary *callbackDic = [NSMutableDictionary dictionary];
    if (completedBlock) {
        callbackDic[kCompletedCallBackKey] = [completedBlock copy];
    }
    if (processBlock) {
        callbackDic[kProcessCallBackKey] = [processBlock copy];
    }
    [self.lock lock];
    [self.callBackArr addObject:callbackDic];
    [self.lock unlock];
}

- (void)downloadingOperationProcessBlockCallBackWithProcess:(CGFloat)processRatio
                                                      error:(NSError *)error {
    NSArray *completeArr = [self callProcessBlockForKey:kProcessCallBackKey];
    safe_dispatch_main_async(^{
        for (WMDownloaderProcessBlock processBlock in completeArr) {
            processBlock(processRatio, error);
        }
    });
}

- (nullable NSArray *)callProcessBlockForKey:(NSString *)key {
    [self.lock lock];
    NSMutableArray <id> *callbacks = [[self.callBackArr valueForKey:key] mutableCopy];
    [self.lock unlock];
    return callbacks;
}

- (nullable NSArray *)callBackBlockForKey:(NSString *)key {
    [self.lock lock];
    NSMutableArray <id> *callbacks = [[self.callBackArr valueForKey:key] mutableCopy];
    [self.lock unlock];
    [callbacks removeObjectIdenticalTo:[NSNull null]];
    return [callbacks copy];
}

#pragma mark Error

- (void)downloadOperationErrorHandlerWithError:(NSError *)error {
    [self downloadOperationErrorHandlerWithData:nil error:error finished:YES];
}

- (void)downloadOperationErrorHandlerWithData:(NSData *)data
                                        error:(NSError *)error
                                     finished:(BOOL)finished {
    NSArray *completeArr = [self callBackBlockForKey:kCompletedCallBackKey];
    safe_dispatch_main_async(^{
        for (WMDownloaderCompletedBlock completedBlock in completeArr) {
            completedBlock(data, error, finished);
        }
    });
}

- (void)downloadOperationErrorHandlerWithPath:(NSString *)path
                                        error:(NSError *)error
                                     finished:(BOOL)finished {
    NSArray *completeArr = [self callBackBlockForKey:kCompletedCallBackKey];
    safe_dispatch_main_async(^{
        for (WMDownloaderCompletedBlock completedBlock in completeArr) {
            completedBlock(path, error, finished);
        }
    });
}

#pragma mark NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    NSURLSessionResponseDisposition disposition = NSURLSessionResponseAllow;
    NSUInteger expectedLength = (NSUInteger)response.expectedContentLength;
    expectedLength = expectedLength > 0 ? expectedLength : 0;
    self.expectedSize = expectedLength;
    NSInteger statusCode =[response respondsToSelector:@selector(statusCode)] ? ((NSHTTPURLResponse *)response).statusCode : 200;
    BOOL valid = statusCode < 400;
    if (valid) {
        self.executing = YES;
    } else {
        disposition = NSURLSessionResponseCancel;
    }
    if (completionHandler) {
        completionHandler(disposition);
    }
    
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    if (!_downloadData) {
       self.downloadData = [[NSMutableData alloc] initWithCapacity:self.expectedSize];
    }
    [self.downloadData appendData:data];
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler {
    NSCachedURLResponse *cachedReponse = proposedResponse;
    if (!(self.options & WMDownloaderOptionsDownloaderUseNSURLCache)) {
        cachedReponse = nil;
    }
    if (completionHandler) {
        completionHandler(cachedReponse);
    }
}

#pragma mark NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        NSLog(@"requestURL:%@--%@",task.currentRequest.URL,error);
        [self downloadOperationErrorHandlerWithError:error];
        if ([error.userInfo objectForKey:NSURLSessionDownloadTaskResumeData]) {
            NSData *resumeData = [error.userInfo objectForKey:NSURLSessionDownloadTaskResumeData];
            NSURLSessionTask *task = [self.ownedSession downloadTaskWithResumeData:resumeData];
            [task resume];
        }
    } else {
        //download本地存储
        if (self.options & WMDownloaderOptionsDownloaderBigFile) {
            NSString *path = [WMFileManager finishedDownloadFileDirWithURL:_downloadUrl];
            [self downloadOperationErrorHandlerWithPath:path error:nil finished:YES];
            [self reset];
            return;
        }
        
        //competedBlock
        if (self.downloadData.length > 0) {
            [self downloadOperationErrorHandlerWithData:self.downloadData error:nil finished:YES];
        } else {
            [self downloadOperationErrorHandlerWithError:[NSError errorWithDomain:kDownloadErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"data is nil"}]];
        }
    }
    [self reset];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    //处理重定向
    NSInteger code = response.statusCode;
    NSURLRequest *redirectRequest = nil;
    if (code == 301 || code == 302) {
        NSString *url = response.allHeaderFields[@"Location"];
        if (!url) {
            return;
        }
        NSURLRequestCachePolicy cachePolicy = _options & WMDownloaderOptionsDownloaderUseNSURLCache ? NSURLRequestUseProtocolCachePolicy : NSURLRequestReloadIgnoringLocalCacheData;
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]
                                                                    cachePolicy:cachePolicy
                                                                timeoutInterval:15.0];
        request.HTTPShouldUsePipelining = YES;
        redirectRequest = request;
    }
    if (completionHandler) {
        completionHandler(request);
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    __block NSURLCredential *credential = nil;
    
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if (!(self.options & WMDownloaderOptionsAllowInvalidSSLCertificates)) {
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        } else {
            credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            disposition = NSURLSessionAuthChallengeUseCredential;
        }
    } else {
        if (challenge.previousFailureCount == 0) {
//            if (self.credential) {
//                credential = self.credential;
//                disposition = NSURLSessionAuthChallengeUseCredential;
//            } else {
            disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
//            }
        } else {
            disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
        }
    }
    
    if (completionHandler) {
        completionHandler(disposition, credential);
    }
}

#pragma mark NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
    didFinishDownloadingToURL:(NSURL *)location {
    if (!location.path) return;
    [WMFileManager moveToDocumentDirWithTempDir:location.path url:_downloadUrl];
    [WMFileManager removeDocumentDownloadingDataWithURL:_downloadUrl];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
    didWriteData:(int64_t)bytesWritten
totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    self.executing = YES;
    [self downloadingOperationProcessBlockCallBackWithProcess:totalBytesWritten*100.0/totalBytesExpectedToWrite error:nil];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
    didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes {
    
}

- (void)willEnterBackground {
    [self _pause_inner];
}

@end


