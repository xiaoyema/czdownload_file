//
//  WMFileManager.h
//  CoreAnimationDemo
//
//  Created by iwm on 2018/6/12.
//  Copyright © 2018年 Mr.Chen. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface WMFileManager : NSObject

+ (void)initializeFileManager;

+ (NSString *)rootDoumentDir;

+ (BOOL)saveTempDownloadDataToDisk:(NSData *)data
                               url:(NSString *)url
                      tempFilePath:(NSString *)tempPath;

+ (NSData *)readTempDownloadingDataFromDiskWithURL:(NSString *)url;

+ (void)moveToDocumentDirWithTempDir:(NSString *)tempDir
                                 url:(NSString *)url;

+ (NSString *)finishedDownloadFileDirWithURL:(NSString *)url;

+ (BOOL)isExitFinishDownloadFileDirWithURL:(NSString *)url;

+ (void)removeDocumentDownloadedDataWithURL:(NSString *)url;

+ (NSData *)searchTableDataValuesWithKey:(NSString *)url;

+ (void)moveTempFileToDocumentDownloadDir;

+ (BOOL)removeDocumentDownloadingDataWithURL:(NSString *)url;

+ (void)moveDocumentDownloadingDataToTempFile;

+ (void)clearDocumentDownloadingData;
@end
