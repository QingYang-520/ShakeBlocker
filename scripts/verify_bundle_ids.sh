#!/bin/sh
# ============================================================
# verify_bundle_ids.sh — 在越狱设备上跑，列出已安装 App 的
# “显示名 -> 真实 Bundle ID”，用于核实清单里“待核实/待复核”的条目。
# 用法：sh verify_bundle_ids.sh > bundleids.txt
# ============================================================
PREFIX=""
if [ -d /var/jb ]; then PREFIX="/var/jb"; fi

for ROOT in /var/containers/Bundle/Application /var/mobile/Applications; do
    [ -d "$ROOT" ] || continue
    for UUID in "$ROOT"/*; do
        [ -d "$UUID" ] || continue
        for APP in "$UUID"/*.app; do
            [ -d "$APP" ] || continue
            INFO="$APP/Info.plist"
            [ -f "$INFO" ] || continue
            # 用 PlistBuddy（若可用）或 defaults 读取；两台都不在时退回 strings 粗提取
            if command -v plutil >/dev/null 2>&1; then
                BID=$(plutil -extract CFBundleIdentifier raw -o - "$INFO" 2>/dev/null)
                NAME=$(plutil -extract CFBundleDisplayName raw -o - "$INFO" 2>/dev/null)
            fi
            if [ -z "$BID" ] && command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
                BID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO" 2>/dev/null)
                NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$INFO" 2>/dev/null)
            fi
            [ -z "$BID" ] && BID=$(strings "$INFO" | grep -A1 CFBundleIdentifier | grep -o '[a-zA-Z0-9.]*\{3,\}' | head -1)
            printf '%-24s | %s\n' "$BID" "${NAME:-$(basename "$APP" .app)}"
        done
    done
done | sort -u
