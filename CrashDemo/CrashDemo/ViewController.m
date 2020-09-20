//
//  ViewController.m
//  CrashDemo
//
//  Created by FengyunSky on 2020/8/29.
//  Copyright © 2020 Logic. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UILabel *label;
@property (nonatomic, copy) NSString * name;

@end

@implementation ViewController

- (void)badAccess
{
   uintptr_t *ptr = NULL;
    *ptr = 1;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    //不是主线程可以让应用起死回生
//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//        NSArray *array = @[@"hello"];
//        NSLog(@"array:%@", [array objectAtIndex:3]);
//        while (1) {
//            NSLog(@"11");
//            sleep(1);
//        }
//    });
    
//    [self performSelector:@selector(hello) withObject:nil afterDelay:1.0];
    [self performSelector:@selector(badAccess) withObject:nil afterDelay:2.0];
    
    //其他线程异常
//    [NSThread detachNewThreadWithBlock:^{
//        NSLog(@"thread:%@", [NSThread currentThread]);
//        uintptr_t *ptr = NULL;
//        *ptr = 1;
//    }];
    
    
//    //越界访问
//    NSArray *array = @[@"hello"];
//    NSLog(@"array:%@", [array objectAtIndex:3]);
    //内存对齐错误
//    char *name = "hello";
//    int tmp = *(int*)name + 1;
//    NSLog(@"tmp:%d", tmp);
//
    //找不到方法
//    [self performSelector:@selector(hello)];
    
    //kvc找不到key
//    [self setValue:@"" forKey:@"hello"];
    
    //访问无效地址0-4GB地址导致崩溃？？？
//    uintptr_t *ptr = NULL;
//    *ptr = 1;
    
    //死锁
//    NSLock *m_lock = [[NSLock alloc]init];
//    [m_lock lock]; // 成功上锁
//    NSLog(@"1");
//    [m_lock lock]; // 上面已经上锁，这里阻塞等待锁释放，不会再执行下面，锁永远得不到释放，即死锁
//    NSLog(@"2");
//    [m_lock unlock]; // 不会执行到
//    NSLog(@"3");
//    [m_lock unlock];
    
    //断言
//    NSAssert(0, @"test");
}


- (IBAction)clickBtn:(id)sender {
    NSLog(@"hello");
    
}

@end
