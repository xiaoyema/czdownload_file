//
//  WMDownloadCompat.h
//  CoreAnimationDemo
//
//  Created by iwm on 2018/6/5.
//  Copyright © 2018年 Mr.Chen. All rights reserved.
//

#ifndef dispatch_queue_async_safe
#define dispatch_queue_async_safe(queue, block)\
    if (dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) == dispatch_queue_get_label(queue)) {\
        block();\
    } else {\
        dispatch_async(queue, block);\
    }
#endif

#ifndef safe_dispatch_main_async
#define safe_dispatch_main_async(block) dispatch_queue_async_safe(dispatch_get_main_queue(), block)
#endif
