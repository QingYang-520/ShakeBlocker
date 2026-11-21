# ============================================================
# ShakeBlocker — 双 scheme Theos 工程（rootful / rootless）
# ============================================================
# 构建 rootful（iOS 13-14，iphoneos-arm，依赖 mobilesubstrate）：
#     make clean && make package
# 构建 rootless（iOS 15-16，iphoneos-arm64，依赖 ellekit）：
#     make clean && make SCHEME=rootless package
#
# ⚠️ 切换 SCHEME 前必须 make clean！否则 staging 目录会残留上一 scheme
#    的文件前缀，导致 deb 里混进错误的安装路径。
# ============================================================

ifeq ($(SCHEME),rootless)
    export THEOS_PACKAGE_SCHEME = rootless
    ARCHS = arm64
    CONTROL_SRC = control.rootless    # iphoneos-arm64 + Depends: ellekit
else
    ARCHS = arm64
    CONTROL_SRC = control             # iphoneos-arm + Depends: mobilesubstrate
endif

include $(THEOS)/makefiles/common.mk

# ---------- Tweak（注入模块）----------
TWEAK_NAME = ShakeBlocker
ShakeBlocker_FILES = Tweak.xm
ShakeBlocker_CFLAGS = -include rootless.h -fobjc-arc

# ---------- Daemon（守护进程）----------
TOOL_NAME = shakeblockerd
shakeblockerd_FILES = daemon/main.m
shakeblockerd_CFLAGS = -include rootless.h -fobjc-arc
shakeblockerd_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/tool.mk

# ---------- 额外资源打包 ----------
# Theos 在 rootless scheme 下会自动给 $(THEOS_STAGING_DIR) 加 /var/jb 前缀，
# 所以这里一律写“相对于安装前缀”的路径，不写死 /var/jb。
after-stage::
	$(CREATE_FOLDER) "$(THEOS_STAGING_DIR)/Library/Application Support/ShakeBlocker"
	$(CP) targets.plist "$(THEOS_STAGING_DIR)/Library/Application Support/ShakeBlocker/targets.plist"
	$(CREATE_FOLDER) "$(THEOS_STAGING_DIR)/Library/LaunchDaemons"
	$(CP) com.qingyang.shakeblocker.daemon.plist "$(THEOS_STAGING_DIR)/Library/LaunchDaemons/com.qingyang.shakeblocker.daemon.plist"
	$(CREATE_FOLDER) "$(THEOS_STAGING_DIR)/DEBIAN"
	# Theos 已按 Scheme 把 control 拷进 staging；这里用对应 control 覆盖，
	# 保证 Architecture / Depends 与 scheme 严格一致（rootful=iphoneos-arm/mobilesubstrate，
	# rootless=iphoneos-arm64/ellekit）。
	$(CP) $(CONTROL_SRC) "$(THEOS_STAGING_DIR)/DEBIAN/control"
	$(CP) scripts/postinst "$(THEOS_STAGING_DIR)/DEBIAN/postinst"
	$(CP) scripts/prerm "$(THEOS_STAGING_DIR)/DEBIAN/prerm"
	$(CHMOD) 755 "$(THEOS_STAGING_DIR)/DEBIAN/postinst" "$(THEOS_STAGING_DIR)/DEBIAN/prerm"
