#!/system/bin/sh
# action.sh —— 模块「操作」按钮：一键修复
#
# 什么时候用：
#   - 在安全模式里禁用了全部模块，恢复后定位失效
#   - 新装模块后天气 App 仍提示「无法获取位置」
#   - 在设置里误点了「拒绝」后想恢复
#   - service.sh 没跑成功（例如 ROM 清理过 /data 权限库）
#
# 执行内容（全部是幂等的，重复点没副作用）：
#   1) 补运行时权限：FINE / COARSE / BACKGROUND / WRITE_EXTERNAL_STORAGE
#      （百度 SDK 缺 WRITE_EXTERNAL_STORAGE 会直接返回 no permission，一个请求都不发）
#   2) 把 installerPackageName 设成系统安装器
#   3) 权限库兜底：把百度的 ACCESS_BACKGROUND_LOCATION 改成已授权
#   4) 应用数据快照还原（模块被禁用过时系统会删掉 /data/data/<pkg>）
#   5) 禁用 microG 自带的两个定位组件
#   6) 主动触发一次定位

PKG=com.baidu.map.location
GMS=com.google.android.gms
GMS_FUSED="$GMS/org.microg.gms.location.provider.FusedLocationProviderService"
GMS_NLP="$GMS/org.microg.gms.location.network.NetworkLocationService"
LOG=/data/local/tmp/baidu_nlp_boot.log
MODDIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
[ -n "$MODDIR" ] || MODDIR=/data/adb/modules/baidu_network_location
SNAP="$MODDIR/.appdata"
DATA=/data/data/$PKG

log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null; echo "$*"; }

echo "=== 百度网络定位：一键修复 ==="

if ! pm path "$PKG" >/dev/null 2>&1; then
  echo "! 找不到 $PKG"
  echo "! 说明模块这次没有挂载成功：请确认模块已启用，然后重启一次再点"
  exit 1
fi

# 1) 运行时权限
echo "- 补齐运行时权限"
for P in \
  android.permission.ACCESS_FINE_LOCATION \
  android.permission.ACCESS_COARSE_LOCATION \
  android.permission.ACCESS_BACKGROUND_LOCATION \
  android.permission.WRITE_EXTERNAL_STORAGE
do
  pm grant "$PKG" "$P" >/dev/null 2>&1
done

# 2) 安装来源
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

# 3) 权限库兜底
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

# 4) 应用数据快照还原
if [ -d "$DATA" ] && [ -d "$SNAP" ] && [ -z "$(ls -A "$DATA/shared_prefs" 2>/dev/null)" ] \
   && [ -n "$(ls -A "$SNAP/shared_prefs" 2>/dev/null)" ]; then
  UID_APP=$(dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*userId=\([0-9]*\).*/\1/p' | head -1)
  am force-stop "$PKG" >/dev/null 2>&1
  mkdir -p "$DATA/shared_prefs" 2>/dev/null
  cp -a "$SNAP/shared_prefs/." "$DATA/shared_prefs/" 2>/dev/null
  [ -n "$UID_APP" ] && chown -R "$UID_APP:$UID_APP" "$DATA" 2>/dev/null
  restorecon -R "$DATA" >/dev/null 2>&1
  echo "- 已还原应用数据快照"
  log "action: appdata restored"
fi

# 5) microG
if pm path "$GMS" >/dev/null 2>&1; then
  pm disable --user 0 "$GMS_FUSED" >/dev/null 2>&1
  pm disable --user 0 "$GMS_NLP" >/dev/null 2>&1
  pids=$(pidof "$GMS" 2>/dev/null)
  [ -n "$pids" ] && kill $pids >/dev/null 2>&1
  echo "- microG 自带定位组件已禁用"
fi

# 6) 触发一次定位
if [ "$(cmd location is-location-enabled 2>/dev/null)" = "true" ]; then
  echo "- 触发定位…"
  cmd location set-location-enabled false >/dev/null 2>&1
  sleep 2
  cmd location set-location-enabled true >/dev/null 2>&1
  sleep 3
fi

# 状态汇总
echo
echo "- 当前状态："
dumpsys package "$PKG" 2>/dev/null |
  grep -E "ACCESS_FINE_LOCATION: granted|ACCESS_COARSE_LOCATION: granted|ACCESS_BACKGROUND_LOCATION: granted|WRITE_EXTERNAL_STORAGE: granted" |
  sed 's/^ */  /'
echo
dumpsys location 2>/dev/null | sed -n '/network provider:/,/fused provider:/p' | grep -E "identity=|connected=|last location=" | sed 's/^ */  /'
echo
dumpsys uimode 2>/dev/null | grep -E "TwilightState" | sed 's/^ */  /'

echo
if [ $NEED_REBOOT -eq 1 ]; then
  echo ">> 权限库刚被修改，需要重启一次才生效"
else
  echo ">> 完成。若仍不生效，重启一次设备"
fi
