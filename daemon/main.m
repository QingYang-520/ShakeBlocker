#import <Foundation/Foundation.h>
#import "../SBPaths.h"

// ============================================================
// shakeblockerd — 由 launchd 每 60 秒拉起一次的扫描守护进程
// 流程：读 targets -> 扫两个安装根目录 -> 读每个 .app 的 Info.plist
//       -> 与 targets/known 比对 -> 给新命中的 App 建 active 标志
//       -> 落盘 known_bundles.plist -> 写日志
// ============================================================

#include <stdarg.h>
static void SBLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    fprintf(stderr, "[SB %s] %s\n",
            [[df stringFromDate:[NSDate date]] UTF8String],
            [msg UTF8String]);
}

// 从 Info.plist 里取显示名（优先本地化名，回退到 CFBundleName）
static NSString *SBDisplayName(NSDictionary *info) {
    NSString *name = info[@"CFBundleDisplayName"];
    if (name.length) return name;
    name = info[@"CFBundleName"];
    if (name.length) return name;
    return info[@"CFBundleExecutable"] ?: @"";
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];

        // 1) 目标列表：Bundle ID 白名单 + 显示名兜底
        NSDictionary *tp = [NSDictionary dictionaryWithContentsOfFile:SB_TARGETS_PLIST] ?: @{};
        NSSet *targetIDs = [NSSet setWithArray:(tp[@"BundleIDs"] ?: @[])];
        NSSet *targetNames = [NSSet setWithArray:(tp[@"DisplayNames"] ?: @[])];

        // 2) 已处理集合，避免每次重复建标志/刷日志
        NSMutableArray *known = [NSMutableArray arrayWithContentsOfFile:SB_KNOWN_PLIST] ?: [NSMutableArray array];
        NSMutableSet *knownSet = [NSMutableSet setWithArray:known];

        // 3) 确保 active 目录存在
        [fm createDirectoryAtPath:SB_ACTIVE_DIR
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];

        // 4) 扫描两个常见安装根目录
        NSArray *roots = @[
            @"/var/containers/Bundle/Application",
            @"/var/mobile/Applications"
        ];
        NSUInteger newHits = 0;

        for (NSString *root in roots) {
            NSArray *uuids = [fm contentsOfDirectoryAtPath:root error:nil] ?: @[];
            for (NSString *uuid in uuids) {
                NSString *uuidPath = [root stringByAppendingPathComponent:uuid];
                BOOL isDir = NO;
                if (![fm fileExistsAtPath:uuidPath isDirectory:&isDir] || !isDir) continue;

                NSArray *items = [fm contentsOfDirectoryAtPath:uuidPath error:nil] ?: @[];
                for (NSString *item in items) {
                    if (![item hasSuffix:@".app"]) continue;

                    NSString *appPath = [uuidPath stringByAppendingPathComponent:item];
                    NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
                    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
                    if (!info) continue;

                    NSString *bid = info[@"CFBundleIdentifier"];
                    NSString *display = SBDisplayName(info);
                    if (!bid.length) continue;

                    // 命中判定：Bundle ID 白名单 或 显示名兜底
                    BOOL idHit = [targetIDs containsObject:bid];
                    BOOL nameHit = display.length && [targetNames containsObject:display];
                    if (!idHit && !nameHit) continue;

                    // 显示名命中但 ID 不在白名单 -> 仅记录日志（不预知 ID，绝不瞎填 filter）
                    if (nameHit && !idHit) {
                        SBLog(@"DISPLAY-NAME HIT: '%@' -> real BundleID=%@ (add it to targets.plist + filter to enable injection)", display, bid);
                    }

                    if ([knownSet containsObject:bid]) continue;  // 已处理过

                    // 命中新目标 App -> 建标志文件（文件名就是真实 Bundle ID）
                    NSString *flag = [SB_ACTIVE_DIR stringByAppendingPathComponent:bid];
                    [fm createFileAtPath:flag contents:nil attributes:nil];

                    [known addObject:bid];
                    [knownSet addObject:bid];
                    newHits++;
                    SBLog(@"NEW TARGET: %@ (%@) -> flag=%@", bid, display, flag);
                }
            }
        }

        // 5) 持久化 known 集合
        [known writeToFile:SB_KNOWN_PLIST atomically:YES];
        SBLog(@"scan done: targetIDs=%lu new=%lu known=%lu",
              (unsigned long)targetIDs.count,
              (unsigned long)newHits,
              (unsigned long)known.count);
    }
    return 0;
}
