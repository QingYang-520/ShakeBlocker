#pragma once
#import <Foundation/Foundation.h>

// rootless.h 由 Theos（Procursus toolchain）提供。
// ROOT_PATH_NS 在 rootful 下返回原路径，在 rootless 下自动加 /var/jb 前缀，
// 全工程不写死 /var/jb，符合双包要求。
#include <rootless.h>

// 若某些环境没有 rootless.h，可用下面这个等价兜底实现（同样不写死业务路径）：
// #ifndef ROOT_PATH_NS
// #define ROOT_PATH_NS(p) ([NSFileManager fileExistsAtPath:@"/var/jb"] \
//     ? [@"/var/jb" stringByAppendingString:p] : p)
// #endif

// daemon 与 tweak 必须用完全相同的规则构造路径，保证标志文件落点一致。
#define SB_LIB_DIR       ROOT_PATH_NS(@"/var/mobile/Library/ShakeBlocker")
#define SB_ACTIVE_DIR    [SB_LIB_DIR stringByAppendingPathComponent:@"active"]
#define SB_KNOWN_PLIST   [SB_LIB_DIR stringByAppendingPathComponent:@"known_bundles.plist"]
#define SB_TARGETS_PLIST ROOT_PATH_NS(@"/Library/Application Support/ShakeBlocker/targets.plist")
