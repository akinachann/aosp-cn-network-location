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

# APK 完整性检查：截断/空文件会让系统在启动该 App 进程时抛
# java.lang.NullPointerException at ConfigurationController.updateLocaleListFromAppContext
APK_SIZE=$(wc -c < "$MODPATH/$APK_REL" 2>/dev/null | tr -d ' ')
case "$APK_SIZE" in
  ''|*[!0-9]*) abort "! 无法读取 APK 大小，压缩包可能已损坏，请重新下载" ;;
esac
[ "$APK_SIZE" -gt 700000 ] || abort "! 模块内 APK 只有 $APK_SIZE 字节，压缩包不完整，请重新下载"

# 同名包已存在时的处理。
# 如果之前用普通 APK 装过同包名，PackageManager 会保留旧的 /data/app 路径，
# 新挂载的 priv-app 会被忽略，App 进程启动时 Resources 为 null，直接 NPE 崩溃。
if pm path com.baidu.map.location >/dev/null 2>&1; then
  OLD_PATH=$(pm path com.baidu.map.location 2>/dev/null | head -1 | cut -d: -f2)
  case "$OLD_PATH" in
    /system/priv-app/BaiduNetworkLocation/*) : ;;
    *)
      ui_print "! 检测到已安装的同名包：$OLD_PATH"
      ui_print "! 它会让系统继续使用旧路径，导致 App 启动即崩溃（Resources 为 null）"
      ui_print "- 正在移除旧安装…"
      pm uninstall --user 0 com.baidu.map.location >/dev/null 2>&1 \
        || pm uninstall com.baidu.map.location >/dev/null 2>&1
      if pm path com.baidu.map.location >/dev/null 2>&1; then
        ui_print "! 自动移除失败"
        ui_print "! 请先在系统设置里手动卸载 com.baidu.map.location，重启后再刷本模块"
      else
        ui_print "- 已移除旧安装，重启后由本模块提供"
      fi
      ;;
  esac
fi

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
