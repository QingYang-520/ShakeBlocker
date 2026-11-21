#import <Foundation/Foundation.h>
#import <CoreMotion/CoreMotion.h>
#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>
#import "SBPaths.h"

// ============================================================
// 运行时门控：只有“自身进程 Bundle ID 在 active/ 下有标志文件”才 Hook。
// 非目标 App 即使被注入也全部走 %orig，零副作用。
// ============================================================
static BOOL SBEnabled = NO;

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        NSString *flag = [SB_ACTIVE_DIR stringByAppendingPathComponent:bid];
        SBEnabled = [[NSFileManager defaultManager] fileExistsAtPath:flag];

        // 构造函数日志：确认是否命中（Filza 看 /var/log/syslog，或 syslog 命令）
        NSLog(@"[ShakeBlocker] ctor bid=%@ enabled=%d flag=%@", bid, SBEnabled, flag);
    }
}

// ------------------------------------------------------------
// a) CMMotionManager：吞掉传感器启动，屏蔽可用性，读数返回 nil
//    注意：这里只覆盖“公开 API”。若广告 SDK 走 IOKit/私有路径可能绕过，
//    本方案不承诺 100%（见 README 残余风险）。
// ------------------------------------------------------------
%hook CMMotionManager

// ---- 启动类：门控开启时置为空操作 ----
- (void)startAccelerometerUpdates {
    if (!SBEnabled) %orig;
}
- (void)startAccelerometerUpdatesToQueue:(NSOperationQueue *)queue
                             withHandler:(CMAccelerometerHandler)handler {
    if (!SBEnabled) %orig;
}
- (void)startGyroUpdates {
    if (!SBEnabled) %orig;
}
- (void)startGyroUpdatesToQueue:(NSOperationQueue *)queue
                    withHandler:(CMGyroHandler)handler {
    if (!SBEnabled) %orig;
}
- (void)startDeviceMotionUpdates {
    if (!SBEnabled) %orig;
}
- (void)startDeviceMotionUpdatesToQueue:(NSOperationQueue *)queue
                            withHandler:(CMDeviceMotionHandler)handler {
    if (!SBEnabled) %orig;
}
- (void)startDeviceMotionUpdatesUsingReferenceFrame:(CMAttitudeReferenceFrame)referenceFrame {
    if (!SBEnabled) %orig;
}
- (void)startDeviceMotionUpdatesUsingReferenceFrame:(CMAttitudeReferenceFrame)referenceFrame
                                            toQueue:(NSOperationQueue *)queue
                                        withHandler:(CMDeviceMotionHandler)handler {
    if (!SBEnabled) %orig;
}
- (void)startMagnetometerUpdates {
    if (!SBEnabled) %orig;
}
- (void)startMagnetometerUpdatesToQueue:(NSOperationQueue *)queue
                            withHandler:(CMMagnetometerHandler)handler {
    if (!SBEnabled) %orig;
}

// ---- 可用性：门控开启时返回 NO ----
- (BOOL)isAccelerometerAvailable {
    if (SBEnabled) return NO;
    return %orig;
}
- (BOOL)isGyroAvailable {
    if (SBEnabled) return NO;
    return %orig;
}
- (BOOL)isDeviceMotionAvailable {
    if (SBEnabled) return NO;
    return %orig;
}
- (BOOL)isMagnetometerAvailable {
    if (SBEnabled) return NO;
    return %orig;
}

// ---- 读数：门控开启时返回 nil ----
- (CMAccelerometerData *)accelerometerData {
    if (SBEnabled) return nil;
    return %orig;
}
- (CMGyroData *)gyroData {
    if (SBEnabled) return nil;
    return %orig;
}
- (CMDeviceMotion *)deviceMotion {
    if (SBEnabled) return nil;
    return %orig;
}
- (CMMagnetometerData *)magnetometerData {
    if (SBEnabled) return nil;
    return %orig;
}
%end

// ------------------------------------------------------------
// b) UIResponder：吞掉摇动事件（motionBegan/Ended/Cancelled）
//    UIEventSubtype 在 iOS 13+ 标注废弃但仍可用，iOS 13-16 签名一致，
//    因此 Tweak.xm 无需版本分支。
// ------------------------------------------------------------
%hook UIResponder
- (void)motionBegan:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (!SBEnabled) %orig;
}
- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (!SBEnabled) %orig;
}
- (void)motionCancelled:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (!SBEnabled) %orig;
}
%end

// ------------------------------------------------------------
// c) CLLocationManager：阻断磁力计航向（倾斜跳转的绕行路径）
//    didUpdateHeading: 是 delegate 回调，无法预知谁是 delegate；
//    务实做法是从源头掐断：不让 heading 更新发生 + headingAvailable 返 NO。
// ------------------------------------------------------------
%hook CLLocationManager
- (void)startUpdatingHeading {
    if (!SBEnabled) %orig;
}
+ (BOOL)headingAvailable {
    if (SBEnabled) return NO;
    return %orig;
}
%end

// ------------------------------------------------------------
// d) UIDevice：阻断接近传感器
// ------------------------------------------------------------
%hook UIDevice
- (void)setProximityMonitoringEnabled:(BOOL)enabled {
    if (!SBEnabled) %orig;
}
- (BOOL)proximityMonitoringEnabled {
    if (SBEnabled) return NO;
    return %orig;
}
%end
