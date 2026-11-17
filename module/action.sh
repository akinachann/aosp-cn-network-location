#!/system/bin/sh
# action.sh —— 模块「操作」按钮：手动修复后台定位权限
#
# 适用于：
#   - 新装模块后天气 App 仍提示「无法获取位置」
#   - 在设置里误点了「拒绝」后想恢复
#   - service.sh 没跑成功（例如 ROM 清理过 /data 权限库）
#
# 执行内容与 post-fs-data.sh / service.sh 相同：
#   1) 把 installerPackageName 设成 com.android.packageinstaller
#   2) 把 runtime-permissions.xml 里百度的后台定位改成已授权
# 完成后需要重启一次设备才会生效。

PKG=com.baidu.map.location
LOG=/data/local/tmp/baidu_nlp_boot.log

log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null; echo "$*"; }

echo "=== 百度网络定位：手动修复 ==="

if ! pm path "$PKG" >/dev/null 2>&1; then
  echo "! 找不到 $PKG，请先确认模块已安装并重启过"
  exit 1
fi

# 1) 安装来源
CUR_INST=$(dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*installerPackageName=\(.*\)/\1/p' | head -1)
if pm list packages 2>/dev/null | grep -q "^package:com.android.packageinstaller$"; then
  WANT_INST=com.android.packageinstaller
else
  WANT_INST=com.google.android.packageinstaller
fi

if [ "$CUR_INST" = "$WANT_INST" ]; then
  echo "- 安装来源已是 $WANT_INST"
else
  if su 2000 -c "pm set-installer $PKG $WANT_INST" >/dev/null 2>&1 || pm set-installer "$PKG" "$WANT_INST" >/dev/null 2>&1; then
    echo "- 已将安装来源设为 $WANT_INST"
    log "action: installer -> $WANT_INST"
  else
    echo "! 设置安装来源失败（当前：${CUR_INST:-空}）"
  fi
fi

# 2) 后台定位权限
echo "- 当前状态："
dumpsys package "$PKG" 2>/dev/null | grep -A1 "ACCESS_BACKGROUND_LOCATION:" | tail -2

NEED_REBOOT=0
for F in \
  /data/misc/apexdata/com.android.permission/runtime-permissions.xml \
  /data/misc_de/0/apexdata/com.android.permission/runtime-permissions.xml
do
  [ -f "$F" ] || continue
  T=/data/local/tmp/.baidu_rp_action.new
  awk '
    /<package name="com\.baidu\.map\.location">/ { inb = 1 }
    inb && /ACCESS_BACKGROUND_LOCATION/ {
      sub(/granted="[a-z]+"/, "granted=\"true\"")
      sub(/flags="[0-9a-fA-F]+"/, "flags=\"901\"")
      inb = 0
    }
    { print }
  ' "$F" > "$T" 2>/dev/null
  if [ -s "$T" ] && ! cmp -s "$T" "$F"; then
    cat "$T" > "$F" && echo "- 已修改权限库：$F" && NEED_REBOOT=1
    log "action: patched $F"
  fi
  rm -f "$T"
done

# 3) 顺手再尝试一次 pm grant（部分 ROM 已经可以接受）
pm grant "$PKG" android.permission.ACCESS_BACKGROUND_LOCATION >/dev/null 2>&1

echo
if [ $NEED_REBOOT -eq 1 ]; then
  echo ">> 请重启设备后生效"
else
  echo ">> 权限库已是授权状态，若仍不生效请重启一次"
fi
