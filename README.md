# ShakeBlocker — iOS 开屏摇一摇广告传感器拦截（Theos 双包工程）

[![Build ShakeBlocker DEBs](https://github.com/QingYang-520/ShakeBlocker/actions/workflows/build.yml/badge.svg)](https://github.com/QingYang-520/ShakeBlocker/actions/workflows/build.yml)

> 本鲸鱼娘给主人写的完整工程喵～ *尾巴摇了摇*
> 目标：已越狱 iOS 13–16，每 60 秒扫描新装 App，命中目标后在该 App 进程内
> 禁用开屏广告“摇一摇/扭一扭/倾斜跳转”依赖的传感器与感知 API。

---

## 一、方案说明

### 组件
1. **Daemon（`shakeblockerd`）**：launchd 每 60 秒拉起一次，扫两个安装根目录，
   读 `Info.plist` 的 `CFBundleIdentifier` 与 `targets.plist` 比对，维护
   `known_bundles.plist` 防重复，给新命中的 App 在
   `ROOT_PATH_NS(@"/var/mobile/Library/ShakeBlocker/active")` 下建以 Bundle ID 命名的标志文件。
2. **Tweak（`ShakeBlocker.dylib`）**：注入目标 App，启动时读自身 Bundle ID，
   只有 `active/<BundleID>` 标志存在才启用 Hook，否则全部 `%orig` 透传。

### 双包策略（rootful / rootless 不混进同一个 DEB）
| 项 | Rootful 包 | Rootless 包 |
|---|---|---|
| 系统 | iOS 13–14 | iOS 15–16 |
| 安装前缀 | `/` | `/var/jb/` |
| DEB 架构 | `iphoneos-arm` | `iphoneos-arm64` |
| 依赖 | `mobilesubstrate` | `ellekit` |
| Package Identifier | `com.qingyang.shakeblocker`（相同，APT 按架构自动选） | 同左 |
| 构建开关 | 默认 | `SCHEME=rootless` |

- Makefile 用 `ifeq ($(SCHEME),rootless)` 条件切换 `THEOS_PACKAGE_SCHEME`、`PACKAGE_ARCH`、依赖。
- 全部路径用 `rootless.h` 的 `ROOT_PATH_NS`，不写死 `/var/jb`（postinst/plist 里的 `/var/jb` 仅为脚本运行时判断与字符串修正，属必要例外）。
- **切换 scheme 前必须 `make clean`**，否则 staging 残留会混进错误前缀。

### filter 取舍
采用 **“预置目标 Bundle ID 白名单 filter + 运行时门控”**：
- 白名单保证 dylib 只注入目标 App，不碰 SpringBoard / 系统守护进程 / 内核 / 私有 API；
- 门控保证被注入的非目标也零副作用。
- **新装目标 App 如何生效**：filter 按 Bundle ID 静态匹配，与安装时间无关——新装 App 只要 ID 在列表里就会被注入；daemon 60 秒内建标志；dylib 启动时读标志启用 Hook。
- 备选“注入所有 App + 纯门控”注入面太大，不采用。

### 关于“待核实”Bundle ID（重要，诚实交代）
主人给的清单里有 9 个 App 写“待核实”、6 个写“待复核”。本工程**绝不编造 Bundle ID**：
- 已明确 ID 的 16 个 → 写进 `targets.plist` 的 `BundleIDs` + filter；
- 待核实的 9 个 → 用 `DisplayNames` 兜底：daemon 扫到 App 时读它自己的 Info.plist，
  显示名命中即建标志，**并把“显示名 → 真实 Bundle ID”写进日志**。
  这样不预知 ID 也能“发现并记录”，但在把真 ID 加进 filter 前它们不会被注入——
  这是不编造 ID 前提下的诚实结果。
- 在设备上跑 `sh scripts/verify_bundle_ids.sh > bundleids.txt` 拿到真 ID 后，
  把它们补进 `targets.plist` 的 `BundleIDs` 和 `ShakeBlocker.plist` 的 filter，重新打包即可。

### iOS 13–16 版本分支
`Tweak.xm` **不需要版本分支**。理由：本方案 Hook 的 4 类 API
（`CMMotionManager` / `UIResponder` / `CLLocationManager` / `UIDevice`）都是公开 API，
在 iOS 13–16 之间方法签名稳定（`UIEventSubtype` 虽标废弃但签名一致）。
差异全在打包层，已由 Makefile 的 scheme 处理。

---

## 二、工程目录树

```
ShakeBlocker/
├── Makefile                          # 双 scheme 构建总控
├── control                           # 元数据（Arch/Depends 由 Makefile 覆盖）
├── SBPaths.h                         # daemon 与 tweak 共享的 ROOT_PATH_NS 路径宏
├── Tweak.xm                          # Logos 注入模块（a/b/c/d 四类 Hook + 门控）
├── ShakeBlocker.plist                # filter：目标 Bundle ID 白名单
├── targets.plist                     # 目标列表（BundleIDs + DisplayNames 兜底）
├── com.qingyang.shakeblocker.daemon.plist  # launchd plist 模板
├── daemon/
│   └── main.m                        # 扫描守护进程源码
├── scripts/
│   ├── postinst                      # 安装后：修路径 + 加载 launchd + 建目录
│   ├── prerm                         # 卸载前：卸载 launchd + 清理
│   └── verify_bundle_ids.sh          # 真机核实显示名→Bundle ID
└── packages/                         # 编译产物（.deb）输出目录
```

---

## 三、双包编译打包

环境：macOS + Xcode（推荐）或 Linux + Procursus toolchain；Theos 装在 `~/theos`（非此路径则导出 `THEOS`）。

```sh
cd ~/theos/projects/ShakeBlocker   # 把本工程目录拷到这里

# ① rootful 包（iOS 13–14）
make clean
make package
# 产物 packages/com.qingyang.shakeblocker_1.0.0_iphoneos-arm.deb

# ② rootless 包（iOS 15–16）
make clean                          # ⚠️ 必须！不 clean 会混前缀
make SCHEME=rootless package
# 产物 packages/com.qingyang.shakeblocker_1.0.0_iphoneos-arm64.deb
```

两个包 `Package:` 相同、架构不同，APT 按设备架构自动挑正确的安装。

### ☁️ 用 GitHub Actions 云端自动编译（推荐，本地 Windows 编不了 iOS DEB）
工程已内置 [`.github/workflows/build.yml`](.github/workflows/build.yml)：
用 **免费 `ubuntu-latest`** runner + 社区 [`Randomblock1/theos-action@v1`](https://github.com/Randomblock1/theos-action)
自动装 Theos + Linux toolchain + iOS SDK + ldid，依次编两个 scheme，
上传 DEB 为 Artifacts；打 `v*` 标签时自动发 Release。Linux 编 Theos tweak 是社区标准做法，不需要 Mac。

> ⚠️ **runner 选择的坑（本小姐实测踩过）**：`macos-14`（Apple Silicon）属 10x 计费，
> 免费账号没 macOS 分钟会在 **1 秒内秒取消**（job 连 step 都不跑、runner_id=0）；
> `macos-13` 则长时间 queued 拿不到 runner。所以最终改用 `ubuntu-latest` + theos-action，
> 免费、额度充足。若 ubuntu 也无故 pending/cancel（`billing/actions` 返回 404），
> 说明该账号/组织层面限制了 Actions，退路：
> 1. 在自己 Mac 上装 **self-hosted runner**（Settings → Actions → Runners → New self-hosted runner），
>    把 `runs-on: ubuntu-latest` 改成 `runs-on: self-hosted`；
> 2. 升级 GitHub 套餐。

步骤：
1. 把整个 `ShakeBlocker` 目录推到一个 GitHub 仓库（main/master 分支）。
2. push 后进入 **Actions** 页，等 **Build ShakeBlocker DEBs** 跑完（约 5–10 分钟）。
3. 在本次 run 页面底部 **Artifacts → ShakeBlocker-DEBs** 下载两个 deb。
4. 想直接发 Release：打个标签推上去即可——
   ```sh
   git tag v1.0.0 && git push origin v1.0.0
   ```
5. 也可在 Actions 页点 **Run workflow** 手动触发。

> 若 `theos/sdks` 源失效，编辑 workflow 里“Install iOS SDK”那步的克隆地址即可（SDK 目录名须形如 `iPhoneOS*.sdk`）。本小姐已建议优先用 macOS runner，别在 Linux 上折腾 DER 签名喵。

### 构建与签名注意事项
- **rootless 的 ldid 要新版本（DER entitlements）**：rootless 用 DER 编码 entitlements，老 `ldid` 会签失败。用 Procursus/Bingner 的 `ldid 2.x+`，`ldid -v` 确认；Theos 打包失败先查这里。
- **arm64e 限制**：iOS 14+ 设备是 arm64e，但 rootless 用 arm64 编译即可在 arm64e 设备正常运行（社区主流做法）。开 arm64e 需 Xcode 13+ 支持 ptrauth 的 clang，`ARCHS = arm64e`；工具链不满足就别开，本工程默认 arm64。
- **Linux 环境**：能编，但 DER 签名和 SDK 头文件更容易踩坑，优先 macOS + Xcode。

---

## 四、安装与验证

### 安装
把对应架构的 deb 传设备上：
```sh
dpkg -i com.qingyang.shakeblocker_1.0.0_iphoneos-arm.deb        # rootful
dpkg -i com.qingyang.shakeblocker_1.0.0_iphoneos-arm64.deb      # rootless
# 或 APT 自动选包：apt install com.qingyang.shakeblocker
```

### ① 确认 Daemon 在跑
```sh
# rootful (iOS 13-14)
launchctl list | grep shakeblocker
# rootless (iOS 15-16)
launchctl print system | grep -i shakeblocker
# 通用
ps aux | grep shakeblockerd
```

### ② 装目标 App 后 60 秒内确认标志文件
```sh
# rootful
ls -la /var/mobile/Library/ShakeBlocker/active/
cat /var/mobile/Library/ShakeBlocker/known_bundles.plist
# rootless（前缀由 ROOT_PATH_NS 决定，通常如下）
ls -la /var/jb/var/mobile/Library/ShakeBlocker/active/
```
看到以 Bundle ID 命名的文件即命中。

### ③ 摇一摇验证
打开目标 App → 开屏广告出现时摇动手机 → 不再跳转即生效。构造函数日志会打 `enabled=1`。

### ④ 非目标 App 不受影响
打开不在列表的 App 摇动 → 行为正常（要么未被注入，要么 `SBEnabled=NO` 全走 `%orig`）。

### ⑤ 看日志
```sh
# rootful
tail -f /var/log/shakeblocker.err.log
# rootless
tail -f /var/jb/var/log/shakeblocker.err.log
# 构造函数日志（syslog）
syslog 2>/dev/null | grep ShakeBlocker    # 或 Filza 看 /var/log/syslog
```

### ⑥ 卸载后确认干净
```sh
dpkg -r com.qingyang.shakeblocker
launchctl list | grep shakeblocker        # 应为空
ls /var/mobile/Library/ShakeBlocker       # rootful 应不存在
ls /var/jb/var/mobile/Library/ShakeBlocker  # rootless 应不存在
```

### ⑦ 核实待测 Bundle ID
```sh
sh scripts/verify_bundle_ids.sh > bundleids.txt
cat bundleids.txt
# 把真 ID 补进 targets.plist 的 BundleIDs + ShakeBlocker.plist 的 filter，重新打包
```

---

## 五、残余风险（不承诺 100% 禁用）

### 传感器 Hook 根本解决不了的三类广告形态（不在本方案保证范围）
1. **全屏点击诱导**：整屏可点，摇不摇都跳 → 需 UI 层拦截；
2. **假关闭按钮**：“×”其实是广告 → 需 UI 层拦截；
3. **零点击自动点击 / 倒计时自动跳转**：靠定时器触发，完全不碰传感器 → 本方案无效。

这三类需要移除广告 SDK 或做 UI 层拦截，属另一个工程量级。

### 其他风险
- 广告 SDK 若在 tweak 注入前读了传感器，或走 IOKit/私有路径，可能绕过公开 API Hook；
- `CLLocationManager` 的 delegate 回调未直接 hook，`headingAvailable`/`startUpdatingHeading` 掐断是主流但非穷尽方案；
- “待核实”App 在未补真 ID 前只被发现记录、不会被注入；
- 合规提醒：仅用于自己拥有的设备与合法测试目的。

---

*哼，本小姐可没偷懒，整套工程都给你写全了喵～ 尾巴都敲累了。*
