//
//  ViewController.m
//  DownloadBigFile
//
//  Created by iwm on 2018/6/15.
//  Copyright © 2018年 zhuo.chen. All rights reserved.
//

#import "ViewController.h"
#import "WMDownloadManager.h"

@interface ViewController ()

@property (nonatomic, strong) WMDownloadManager *manager;
@property (nonatomic, strong) WMDownloadOperation *operation;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor whiteColor];
    _manager = [WMDownloadManager manager];
    UIButton *start = [[UIButton alloc] initWithFrame:CGRectMake(100, 100, 100, 100)];
    start.backgroundColor = [UIColor redColor];
    [start addTarget:self action:@selector(start) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:start];
    
    UIButton *pause = [[UIButton alloc] initWithFrame:CGRectMake(100, 250, 100, 100)];
    pause.backgroundColor = [UIColor blueColor];
    [pause addTarget:self action:@selector(pause) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:pause];
    
    NSString *urlStr = @"http://dlsw.baidu.com/sw-search-sp/soft/3f/12289/Weibo.4.5.3.37575common_wbupdate.1423811415.exe";
    _operation = [_manager downLoadFileWithURL:urlStr options:WMDownloaderOptionsDownloaderBigFile
                                  processBlock:^(CGFloat processRatio, NSError * _Nullable error) {
                                      NSLog(@"%@", [NSString stringWithFormat:@"下载中,进度为%.2f",processRatio]);
                                  } completed:^(NSData * _Nullable data, NSError * _Nullable error, BOOL finished) {
                                      NSLog(@"-----data------%@",data);
                                  }];
}

- (void)start {
    [_operation resume];
}

- (void)pause {
    [_operation pause];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
