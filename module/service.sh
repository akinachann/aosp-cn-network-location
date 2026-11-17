#!/system/bin/sh
# service.sh —— 每次开机（late_start service 阶段）执行
#
# 1) 给百度网络定位补齐运行时定位权限（兜底）。
#    正常情况下 system/etc/default-permissions 已经处理，这里只是兜底
#    （部分 ROM 不读取 default-permissions，或者用户清过应用数据）。
#
# 2) 给百度补一个「安装来源」。
#    /system/priv-app 预装应用没有 installerPackageName，Android 11+ 会对它
#    套用 APPLY_RESTRICTION，把 ACCESS_BACKGROUND_LOCATION 变成受限权限：
#    设置里不显示「始终允许」、AppOps UID 模式被钉在 foreground，
#    百度退到后台就取不到 WiFi/基站，天气 App 刷新定位会失败。
#    设成一个系统自带的安装器（com.android.packageinstaller）后，
#    权限标记会变成 RESTRICTION_INSTALLER_EXEMPT，后台定位就能保留。
#    同时这里会把 runtime-permissions.xml 里那条改成已授权；
#    这一步在开机完成后才执行，所以改完需要再重启一次才会被系统采用。
#
# 3) 让系统 fused provider 回到 AOSP 实现。
#    microG 自带的 FusedLocationProviderService 会走它自己的国外 NLP，
#    完全绕过系统 network provider（百度）。禁用它之后，系统会改用
#    /system/priv-app/FusedLocation 的 com.android.location.fused，
#    它只依赖系统的 gps + network provider，
#    于是「根据日出日落切换深色模式」、天气 App 等都能用上百度的国内定位。
#
# 4) 关掉 microG 自带的网络定位服务，让 GMS Location API（Google 地图等）
#    也回落到系统 network provider（百度）。
#    microG 的 LocationManager 用静态标志 hasNetworkLocationServiceBuiltIn
#    判断是否使用自带 NLP，禁用该组件后 queryIntentServices 返回空，
#    标志变为 false，于是改走 requestSystemProviderUpdates("network")。

PKG=com.baidu.map.location
GMS=com.google.android.gms
GMS_FUSED="$GMS/org.microg.gms.location.provider.FusedLocationProviderService"
GMS_NLP="$GMS/org.microg.gms.location.network.NetworkLocationService"
LOG=/data/local/tmp/baidu_nlp_boot.log
MARK=/data/adb/baidu_nlp_no_autogrant

log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null; }

# 等 PackageManager 能查到该包
i=0
while [ $i -lt 30 ]; do
  if pm path "$PKG" >/dev/null 2>&1; then
    break
  fi
  sleep 2
  i=$((i + 1))
done

pm grant "$PKG" android.permission.ACCESS_FINE_LOCATION >/dev/null 2>&1
pm grant "$PKG" android.permission.ACCESS_COARSE_LOCATION >/dev/null 2>&1

# 2) 安装来源：必须是「系统安装器」，否则后台定位会被 restriction 撤销。
#    注意 pm set-installer 不接受 UID 0 调用（SecurityException: Unknown calling UID: 0），
#    所以用 su 2000 切到 shell 再执行。
CUR_INST=$(dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*installerPackageName=\(.*\)/\1/p' | head -1)

if [ ! -f "$MARK" ] && [ "$CUR_INST" != "com.android.packageinstaller" ]; then
  if pm list packages 2>/dev/null | grep -q "^package:com.android.packageinstaller$"; then
    WANT_INST=com.android.packageinstaller
  else
    WANT_INST=com.google.android.packageinstaller
  fi
  if [ "$CUR_INST" != "$WANT_INST" ]; then
    set_installer() {
      su 2000 -c "pm set-installer $PKG $WANT_INST" 2>&1 | grep -qi -e Success -e "$WANT_INST" && return 0
      pm set-installer "$PKG" "$WANT_INST" >/dev/null 2>&1 && return 0
      return 1
    }
    if set_installer; then
      log "installer set to $WANT_INST"
    else
      log "installer NOT set (target $WANT_INST)"
    fi
  fi
fi

# ACCESS_BACKGROUND_LOCATION：作为兜底在开机完成后再改一次权限库
# （如果这一步才改成功，需要再重启一次才生效）。
pm grant "$PKG" android.permission.ACCESS_BACKGROUND_LOCATION >/dev/null 2>&1
if [ ! -f "$MARK" ] && ! dumpsys package "$PKG" 2>/dev/null | grep -A1 "ACCESS_BACKGROUND_LOCATION:" | grep -q "granted=true"; then
  for F in \
    /data/misc/apexdata/com.android.permission/runtime-permissions.xml \
    /data/misc_de/0/apexdata/com.android.permission/runtime-permissions.xml
  do
    [ -f "$F" ] || continue
    T=/data/local/tmp/.baidu_rp_svc.new
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
      cat "$T" > "$F" && log "patched (late, needs reboot): $F"
    fi
    rm -f "$T"
  done
fi

# 3) 4) 只对装了 microG 的设备有意义，GMS / 无 GMS 设备会自动跳过。
#    注意：必须用 pm disable，pm disable-user 在部分 ROM（LineageOS / Android 17）上会静默失败。
if pm path "$GMS" >/dev/null 2>&1; then
  pm disable --user 0 "$GMS_FUSED" >/dev/null 2>&1
  pm disable --user 0 "$GMS_NLP" >/dev/null 2>&1

  # 清掉 microG 的 hasNetworkLocationServiceBuiltIn 静态缓存（只在进程已启动时需要）。
  pids=$(pidof "$GMS" 2>/dev/null)
  if [ -n "$pids" ]; then
    kill $pids >/dev/null 2>&1
  fi
fi

exit 0
