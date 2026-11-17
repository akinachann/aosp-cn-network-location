#!/system/bin/sh
# customize.sh —— 模块安装时执行
# Magisk / APatch / KernelSU 会加载本文件，并导出 MODPATH（模块解压目录）

MODPATH=${MODPATH:-$PWD}

# 兼容不同管理器：缺少工具函数时给出最小实现
command -v ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }
command -v abort    >/dev/null 2>&1 || abort()    { ui_print "$1"; exit 1; }
command -v set_perm >/dev/null 2>&1 || set_perm() {
  chown "$2:$3" "$1" 2>/dev/null
  chmod "$4" "$1" 2>/dev/null
}

APK_REL="system/priv-app/BaiduNetworkLocation/BaiduNetworkLocation.apk"
LIB64_REL="system/priv-app/BaiduNetworkLocation/lib/arm64/libnlocSDK7d.so"
LIB32_REL="system/priv-app/BaiduNetworkLocation/lib/arm/libnlocSDK7d.so"
PERM_REL="system/etc/permissions/privapp-permissions-com.baidu.map.location.xml"
DEFPERM_REL="system/etc/default-permissions/baidu-network-location.xml"

ui_print "*******************************"
ui_print " 百度网络定位 v5.2.0"
ui_print " com.baidu.map.location"
ui_print "*******************************"

[ -f "$MODPATH/$APK_REL" ] || abort "! 模块内未找到 APK，压缩包可能已损坏"

ui_print "- 安装位置：/system/priv-app/BaiduNetworkLocation/"
ui_print "- 特权白名单：privapp-permissions-com.baidu.map.location.xml"

set_perm "$MODPATH/$APK_REL" 0 0 0644
set_perm "$MODPATH/$LIB64_REL" 0 0 0644
set_perm "$MODPATH/$LIB32_REL" 0 0 0644
set_perm "$MODPATH/$PERM_REL" 0 0 0644
set_perm "$MODPATH/$DEFPERM_REL" 0 0 0644
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755

ui_print "- 开机自动修补后台定位权限（service.sh）"
ui_print "- 首次安装可能需要重启两次，权限才会稳定"
ui_print "- 完成，重启设备后生效"
ui_print "- 若之前以普通应用装过同包名，建议先卸载再重启"
ui_print "- 验证：adb shell dumpsys location | grep -i baidu"
