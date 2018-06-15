//
//  WMFileManager.m
//  CoreAnimationDemo
//
//  Created by iwm on 2018/6/12.
//  Copyright © 2018年 Mr.Chen. All rights reserved.
//

#import "WMFileManager.h"
#import <CommonCrypto/CommonDigest.h>
#import <sqlite3.h>
#import <objc/runtime.h>

static sqlite3 *_dataBase;
static dispatch_queue_t _fileQueue;
const char * fileDispatchQueue = "fileDispatchQueue";
@implementation WMFileManager

+ (void)initializeFileManager {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self initilizerSqliteDB];
        [self initializeDispatchQueue];
    });
}

+ (void)initializeDispatchQueue {
    if (!_fileQueue) {
        _fileQueue = dispatch_queue_create(fileDispatchQueue, DISPATCH_QUEUE_SERIAL);
    }
}

+ (dispatch_queue_t)dispatchQueue {
    if (!_fileQueue) {
        [self initializeDispatchQueue];
    }
    return _fileQueue;
}

+ (void)initilizerSqliteDB {
    sqlite3 *database;
    
    int databaseResult = sqlite3_open([[self rootDoumentDownloadingDataDir] UTF8String], &database);

    if (databaseResult != SQLITE_OK) {
        NSLog(@"创建／打开数据库失败,%d",databaseResult);
    }
    char *error;
    
    const char *createSQL = "create table if not exists list(id integer primary key autoincrement,url char,temp_data ntext)";
    
    int tableResult = sqlite3_exec(database, createSQL, NULL, NULL, &error);
    
    if (tableResult != SQLITE_OK) {
        
        NSLog(@"创建表失败:%s",error);
    }
    _dataBase = database;
}

+ (sqlite3 *)openDB {
    if (_dataBase) {
        return _dataBase;
    }
    sqlite3 *database = _dataBase;
    
    int databaseResult = sqlite3_open([[self rootDoumentDownloadingDataDir] UTF8String], &database);
    
    if (databaseResult != SQLITE_OK) {
        NSLog(@"创建／打开数据库失败,%d",databaseResult);
    }
    return database;
}

+ (NSString *)rootDoumentDir {
    NSString *dirPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject  stringByAppendingPathComponent:@"WMDownloaderFile"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dirPath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return dirPath;
}

+ (NSString *)rootDoumentDownloadingDataDir {
    NSString *dataPath = [self rootDoumentDir];

    dataPath = [dataPath stringByAppendingString:[NSString stringWithFormat:@"/downloadingdata.sqlite"]];
    if (!dataPath) {
        NSLog(@"error no downloadfile.db");
        return nil;
    }
    return dataPath;
}

#pragma mark finishedData
+ (void)moveToDocumentDirWithTempDir:(NSString *)tempDir
                                 url:(NSString *)url {
    if (!tempDir || !tempDir.length) return;
    NSError *error = nil;
    [[NSFileManager defaultManager] copyItemAtPath:tempDir toPath:[self finishedDownloadFileDirWithURL:url] error:&error];
    if (error) {
        NSLog(@"error:%@",error.description);
    }
}

+ (NSString *)finishedDownloadFileDirWithURL:(NSString *)url {
    NSString *fileName = [[self encryptionWithString:url] stringByAppendingString:[self parseUrlSuffixWithURL:url]];
    return [[self rootDoumentDir] stringByAppendingString:[NSString stringWithFormat:@"/%@",fileName]];
}

+ (void)removeDocumentDownloadedDataWithURL:(NSString *)url {
    if ([self isExitFinishDownloadFileDirWithURL:url]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:[self finishedDownloadFileDirWithURL:url] error:&error];
    }
}

#pragma mark downloadingData

+ (NSData *)readTempDownloadingDataFromDiskWithURL:(NSString *)url {
    return [self searchTableDataValuesWithKey:url];
}

+ (BOOL)removeDocumentDownloadingDataWithURL:(NSString *)url {
    return [self deleteTempDownloadDataToDisk:url];
}

+ (void)moveTempFileToDocumentDownloadDir {
    dispatch_async([self dispatchQueue], ^{
        NSArray *paths = [[NSFileManager defaultManager] subpathsAtPath:NSTemporaryDirectory()];
        for (NSString *filePath in paths) {
            if ([filePath rangeOfString:@"CFNetworkDownload"].length > 0) {
                NSString *toPath = [[self rootDoumentDir] stringByAppendingString:[NSString stringWithFormat:@"/%@",filePath]];
                NSString *fromPath = [NSTemporaryDirectory() stringByAppendingPathComponent:filePath];
                NSError *error;
                if ([[NSFileManager defaultManager] fileExistsAtPath:toPath]) {
                    [[NSFileManager defaultManager] removeItemAtPath:toPath error:nil];
                }
                [[NSFileManager defaultManager] copyItemAtPath:fromPath toPath:toPath error:&error];
                if (error) {
                    NSLog(@"%@",error.description);
                } else {
                    NSLog(@"移入documentDir");
                }
            }
        }
    });
}

+ (void)moveDocumentDownloadingDataToTempFile {
    dispatch_sync([self dispatchQueue], ^{
        NSArray *paths = [[NSFileManager defaultManager] subpathsAtPath:[self rootDoumentDir]];
        for (NSString *filePath in paths) {
            if ([filePath rangeOfString:@"CFNetworkDownload"].length > 0) {
                NSString *toPath = [NSTemporaryDirectory() stringByAppendingPathComponent:filePath];
                NSString *fromPath = [[self rootDoumentDir] stringByAppendingString:[NSString stringWithFormat:@"/%@",filePath]];
                NSError *error;
                if ([[NSFileManager defaultManager] fileExistsAtPath:toPath]) {
                    [[NSFileManager defaultManager] removeItemAtPath:toPath error:nil];
                }
                [[NSFileManager defaultManager] copyItemAtPath:fromPath toPath:toPath error:&error];
                if (error) {
                    NSLog(@"%@",error.description);
                }
            }
        }
    });
}

+ (void)clearDocumentDownloadingData {
    NSArray *paths = [[NSFileManager defaultManager] subpathsAtPath:[self rootDoumentDir]];
    for (NSString *filePath in paths) {
        if ([filePath rangeOfString:@"CFNetworkDownload"].length > 0) {
            NSString *fromPath = [[self rootDoumentDir] stringByAppendingString:[NSString stringWithFormat:@"/%@",filePath]];
            [[NSFileManager defaultManager] removeItemAtPath:fromPath error:nil];
        }
    }
}

#pragma mark 查

+ (NSData *)searchTableDataValuesWithKey:(NSString *)url {
    if (!url || !url.length) return nil;
    __block NSData *returnData;
    dispatch_sync([self dispatchQueue], ^{
        sqlite3_stmt *stmt = NULL;
        sqlite3 *database = [self openDB];
        
        NSString *sql = [NSString stringWithFormat:@"select * from list where url like ?"];
        int searchResult = sqlite3_prepare_v2(database, [sql UTF8String], -1, &stmt, nil);
        
        if (searchResult != SQLITE_OK) {
            NSLog(@"查询失败,%d",searchResult);
            returnData = nil;
        }
        else{
            sqlite3_bind_text(stmt, 1, [url UTF8String], -1, NULL);
            //默认查找第一条 一般情况不会出现相同的条件的两条
            sqlite3_step(stmt);
            const unsigned char *test1 = sqlite3_column_text(stmt, 2);
            if (!test1) {
                returnData = nil;
                NSLog(@"读取nil");
            } else {
                NSString *dataStr = [NSString stringWithUTF8String:test1];
                NSData *data = [dataStr dataUsingEncoding:NSUTF8StringEncoding];
                returnData = data;
                NSLog(@"读取成功");
            }
        }
    });
    return returnData;
}

#pragma mark 删

+ (BOOL)deleteTempDownloadDataToDisk:(NSString *)url {
    if (!url || !url.length) return NO;
    __block BOOL success = NO;
    dispatch_async([self dispatchQueue], ^{
        sqlite3_stmt *stmt = NULL;
        NSString *sql = [NSString stringWithFormat:@"delete from list where url like ?"];
        sqlite3 * db = [self openDB];
        int stat=sqlite3_prepare_v2(db, [sql UTF8String], -1, &stmt, nil);
        if (stat==SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [url UTF8String], -1, NULL);
            int result;
            do {
                result = sqlite3_step(stmt);
            }
            while (result == SQLITE_ROW);
            if (result == SQLITE_DONE) {
                NSLog(@"删除成功");
                success = YES;
            }
        }
    });
    return success;
}

#pragma mark 增和改

+ (BOOL)saveTempDownloadDataToDisk:(NSData *)data
                               url:(NSString *)url
                      tempFilePath:(NSString *)tempPath {
    if (!data) return NO;
    __block BOOL success = NO;
    NSData *searchData = [self searchTableDataValuesWithKey:url];
    dispatch_async([self dispatchQueue], ^{
        NSString *insertClassification = nil;
        if (!searchData) {
            insertClassification = @"insert into list(temp_data,url) values(?,?)";
        } else {
            insertClassification = @"update list set temp_data=? where url like ?";
        }
        sqlite3_stmt *stmt = NULL;
        //插入语句
        sqlite3 * db = [self openDB];
        int stat=sqlite3_prepare_v2(db, [insertClassification UTF8String], -1, &stmt, nil);
        if (stat==SQLITE_OK) {
            NSString *encodedStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            
            sqlite3_bind_text(stmt, 2, [url UTF8String], -1, NULL);
            sqlite3_bind_text(stmt, 1, [encodedStr UTF8String], -1, NULL);
            
            int result = sqlite3_step(stmt);
            if (result == SQLITE_DONE) {
                NSLog(@"插入成功");
                success = YES;
            } else {
                NSLog(@"插入或更新失败%d",result);
            }
        }
    });
    
    return success;
}

+ (NSString *)parseUrlSuffixWithURL:(NSString *)urlStr {
    NSString *formatStr = @".";
    if (!urlStr || !urlStr.length) {
        return @"";
    }
    NSArray *strArr = [urlStr componentsSeparatedByString:@"."];
    if (!strArr.count) {
        return @"";
    }
    if ([strArr lastObject]) {
       formatStr = [formatStr stringByAppendingString:[strArr lastObject]];
    }
    return formatStr;
}

+ (BOOL)isExitFinishDownloadFileDirWithURL:(NSString *)url {
    NSString *path = [self finishedDownloadFileDirWithURL:url];
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

+ (NSString *)encryptionWithString:(NSString *)str {
    if (!str || !str.length) return @"";
    return  [self md5:str];
}

+ (NSString *)md5:(NSString *)input {
    
    const char *cStr = [input UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5( cStr, strlen(cStr), digest ); // This is the md5 call
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
        [output appendFormat:@"%02x", digest[i]];
    
    return  output;
}

@end
