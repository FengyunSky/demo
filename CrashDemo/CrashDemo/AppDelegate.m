//
//  AppDelegate.m
//  CrashDemo
//
//  Created by FengyunSky on 2020/8/29.
//  Copyright © 2020 Logic. All rights reserved.
//

#import "AppDelegate.h"
#import <mach/message.h>
#import <mach/mach_types.h>
#import <mach/mach_init.h>
#import <mach/mach_port.h>
#import <mach/mach_error.h>
#import <mach/task.h>
#import <pthread.h>
#import <execinfo.h>

#define MACH_MSG_LEN 16
#define MACH_MSG_LEN_MAX 1024

typedef struct
{
    /** Mach header. */
    mach_msg_header_t          header;

    // Start of the kernel processed data.

    /** Basic message body data. */
    mach_msg_body_t            body;

    /** The thread that raised the exception. */
    mach_msg_port_descriptor_t thread;

    /** The task that raised the exception. */
    mach_msg_port_descriptor_t task;

    // End of the kernel processed data.

    /** Network Data Representation. */
    NDR_record_t               NDR;

    /** The exception that was raised. */
    exception_type_t           exception;

    /** The number of codes. */
    mach_msg_type_number_t     codeCount;

    /** Exception code and subcode. */
    // ux_exception.c defines this as mach_exception_data_t for some reason.
    // But it's not actually a pointer; it's an embedded array.
    // On 32-bit systems, only the lower 32 bits of the code and subcode
    // are valid.
    mach_exception_data_type_t code[0];

    /** Padding to avoid RCV_TOO_LARGE. */
    char                       padding[512];
} MachExceptionMessage;

typedef struct
{
    /** Mach header. */
    mach_msg_header_t header;

    /** Network Data Representation. */
    NDR_record_t      NDR;

    /** Return code. */
    kern_return_t     returnCode;
} MachReplyMessage;

mach_port_t g_exceptionPort;

#pragma mark - handle Mach异常

static void* handleExceptions(void * arg) {
    NSLog(@"handle exception");
    MachExceptionMessage exceptionMessage = {{0}};
    MachReplyMessage replyMessage = {{0}};
    kern_return_t kr;
    
    for(;;)
    {
        //等待异常消息
        //mach_msg系统调用runloop 接收我们异常消息
        kr = mach_msg(&exceptionMessage.header,
                        MACH_RCV_MSG,
                        0,
                        sizeof(exceptionMessage),
                        g_exceptionPort,
                        MACH_MSG_TIMEOUT_NONE,
                        MACH_PORT_NULL);
        if(kr == KERN_SUCCESS) {
            printf("recv mach msg \n");
            break;
        }

        printf("mach_msg: %s \n", mach_error_string(kr));
    }
    
    printf("mach exception code 0x%llx, subcode 0x%llx \n", exceptionMessage.code[0], exceptionMessage.code[1]);
    
    // 响应不处理该消息
#if 0
    NSLog(@"Replying to mach exception message.");
    replyMessage.header = exceptionMessage.header;
    replyMessage.NDR = exceptionMessage.NDR;
    replyMessage.returnCode = KERN_FAILURE;

    kr = mach_msg(&replyMessage.header,
                     MACH_SEND_MSG,
                     sizeof(replyMessage),
                     0,
                     MACH_PORT_NULL,
                     MACH_MSG_TIMEOUT_NONE,
                     MACH_PORT_NULL);
    if (kr != KERN_SUCCESS) {
        printf("reply Mach msg failed(%s) \n", mach_error_string(kr));
    }
#else
    //退出应用
    NSLog(@"exit app");
    exit(1);
#endif
    
    return NULL;
}

static void installExceptionHanlder(void) {
    kern_return_t kr;
    
    const task_t thisTask = mach_task_self();
    exception_mask_t mask = EXC_MASK_BAD_ACCESS |
                            EXC_MASK_BAD_INSTRUCTION |
                            EXC_MASK_ARITHMETIC |
                            EXC_MASK_SOFTWARE |
                            EXC_MASK_BREAKPOINT;
    kr = mach_port_allocate(thisTask,
                                MACH_PORT_RIGHT_RECEIVE,
                                &g_exceptionPort);
    if(kr != KERN_SUCCESS) {
        printf("mach_port_allocate: %s \n", mach_error_string(kr));
        return;
    }

    //添加发送权限
    kr = mach_port_insert_right(thisTask,
                                g_exceptionPort,
                                g_exceptionPort,
                                MACH_MSG_TYPE_MAKE_SEND);
    if(kr != KERN_SUCCESS) {
        printf("mach_port_insert_right: %s", mach_error_string(kr));
        return;
    }

    //当前进程注册异常端口来接收Mach异常消息 mach异常消息
    kr = task_set_exception_ports(thisTask,
                                  mask,
                                  g_exceptionPort,
                                  (int)(EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES),
                                  THREAD_STATE_NONE);
    if(kr != KERN_SUCCESS) {
        printf("task_set_exception_ports: %s", mach_error_string(kr));
        return;
    }
    //创建异常处理线程来接收Mach异常消息
    pthread_t pthreadId = 0;
    int error = pthread_create(&pthreadId,
                            NULL,
                            &handleExceptions,
                            NULL);
    if (error != 0) {
        printf("pthread_create error:%s \n", strerror(errno));
        return;
    }
}

#pragma mark - CrashHandler

NSString * const kSignalExceptionName = @"kSignalExceptionName";
NSString * const kSignalKey = @"kSignalKey";
NSString * const kCaughtExceptionStackInfoKey = @"kCaughtExceptionStackInfoKey";

@interface CrashHandler : NSObject {
    BOOL _ignore;
}

+ (instancetype)sharedInstance;

@end

@implementation CrashHandler

static CrashHandler *instance = nil;

+ (instancetype)sharedInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[[self class] alloc] init];
    });
    return instance;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [super allocWithZone:zone];
    });
    return instance;
}

+ (NSArray *)getBacktrace
{
    void* callstack[128];
    int frames = backtrace(callstack, 128);
    char **strs = backtrace_symbols(callstack, frames);
    
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:frames];
    for (int i = 0; i < frames; i++) {
        [array addObject:[NSString stringWithUTF8String:strs[i]]];
    }
    free(strs);
    
    return array;
}

- (void)alertView:(UIAlertView *)anAlertView clickedButtonAtIndex:(NSInteger)anIndex
{
    if (anIndex == 0) {
        _ignore = YES;
    } else if (anIndex == 1) {
        NSLog(@"起死回生");
    }
}

//returun系统kill应用 线程执行
- (void)handleException:(NSException *)exception
{
    NSString *message = [NSString stringWithFormat:@"崩溃原因如下:\n%@\n%@",
                         [exception reason],
                         [[exception userInfo] objectForKey:kCaughtExceptionStackInfoKey]];
    NSLog(@"%@",message);
    
    //UIAlertView弹窗，其执行依赖于至下面新创建的runloop中渲染
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"程序崩溃了"
                                                    message:@"如果你能让程序起死回生，那你的决定是？"
                                                   delegate:self
                                          cancelButtonTitle:@"崩就蹦吧"
                                          otherButtonTitles:@"起死回生", nil];
    //非阻塞执行 runloop 渲染
    [alert show];
    
    //获取当前runloop
    //线程保活runloop
    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    CFArrayRef allModes = CFRunLoopCopyAllModes(runLoop);
    while (!_ignore) {
        for (NSString *mode in (__bridge NSArray *)allModes) {
            if ([mode isEqualToString:(NSString *)kCFRunLoopCommonModes]) {
                continue;
            }
            CFStringRef modeRef  = (__bridge CFStringRef)mode;
            //重新运行另一个循环，接收异步事件：ui渲染 timer
            CFRunLoopRunInMode(modeRef, 0.1, false);
        }
    }
    //释放内存
    CFRelease(allModes);
    
    //避免崩溃循环
    NSSetUncaughtExceptionHandler(NULL);
    signal(SIGABRT, SIG_DFL);
    signal(SIGILL, SIG_DFL);
    signal(SIGSEGV, SIG_DFL);
    signal(SIGFPE, SIG_DFL);
    signal(SIGBUS, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    //抛出异常让应用退出
    if ([[exception name] isEqual:kSignalExceptionName]) {
        kill(getpid(), [[[exception userInfo] objectForKey:kSignalKey] intValue]);
    } else {
        [exception raise];
    }
}

@end

#pragma mark - uncaughtException
static NSUncaughtExceptionHandler *_previousHandler;
static void _handleUncaughtExceptionHandler(NSException* exception) {
    NSLog(@"exception:%@", exception);
    
    //调用之前的异常处理函数
    if(_previousHandler){
        _previousHandler(exception);
    }
    
    // 获取异常的堆栈信息
    NSArray *callStack = [exception callStackSymbols];
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setObject:callStack forKey:kCaughtExceptionStackInfoKey];
    
    CrashHandler *crashObject = [CrashHandler sharedInstance];
    NSException *customException = [NSException exceptionWithName:[exception name] reason:[exception reason] userInfo:userInfo];
    //通过performSelector进而调用objc_msgSend
    [crashObject performSelectorOnMainThread:@selector(handleException:) withObject:customException waitUntilDone:YES];
    NSLog(@"handle uncaught exception end");
}

#pragma mark - handle signal
static void handleSignal(int signo) {
    printf("handler signo:%d \n", signo);
    // 这种情况的崩溃信息，就另某他法来捕获吧
    NSArray *callStack = [CrashHandler getBacktrace];
    NSLog(@"信号捕获崩溃，堆栈信息：%@",callStack);
    
    CrashHandler *crashObject = [CrashHandler sharedInstance];
    NSException *customException = [NSException exceptionWithName:kSignalExceptionName
                                                           reason:[NSString stringWithFormat:NSLocalizedString(@"Signal %d was raised.", nil),signal]
                                                         userInfo:@{kSignalKey:[NSNumber numberWithInt:signal]}];
    //主线程立即执行异常处理方法->让主线程重新启动runloop循环接收各种事件：触摸、渲染等
    [crashObject performSelectorOnMainThread:@selector(handleException:) withObject:customException waitUntilDone:YES];
    NSLog(@"handle uncaught exception end");
}

#pragma mark - AppDelegate

@interface AppDelegate ()

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    //注册异常端口并接收异常消息 异常端口mach异常消息！！！
    installExceptionHanlder();
    
#if 0
    //捕获信号
    if (signal(SIGABRT, handleSignal) == SIG_ERR) {
        printf("signal error:%s \n", strerror(errno));
    }
    if (signal(SIGSEGV, handleSignal) == SIG_ERR) {
        printf("signal error:%s \n", strerror(errno));
    }
    if (signal(SIGBUS, handleSignal) == SIG_ERR) {
        printf("signal error:%s \n", strerror(errno));
    }
    
    //先保存之前的异常处理函数(避免影响第三方SDK)
    _previousHandler = NSGetUncaughtExceptionHandler();
    //设置新的异常处理函数，捕获OC异常
    NSSetUncaughtExceptionHandler(&_handleUncaughtExceptionHandler);
#endif
    
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    UIBackgroundTaskIdentifier _backgroundTaskIdentifier = [application beginBackgroundTaskWithExpirationHandler:^{
    }];
    
    NSLog(@"开始执行后台任务");
//    while (1) {
//        NSLog(@"1");
//    }
    [application endBackgroundTask:_backgroundTaskIdentifier];

}


@end
