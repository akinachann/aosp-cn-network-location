# 类原生系统的国内网络定位（NLP）

在中国的网络环境下，类原生系统（AOSP / LineageOS / crDroid）往往没有一个能用的**网络定位（Network Location Provider）**：

- 官方 GMS 在国内基本不可用；
- microG 自带的网络定位走的是国外服务器，慢且偏；
- 纯 AOSP 干脆没有网络定位，只能干等 GPS。

结果是定位很慢、精度差，天气 App、「根据日出日落自动切换深色模式」这类依赖定位的功能基本残废。

本模块把 `com.baidu.map.location`（百度网络定位 5.2.0）安装为系统预装应用，让它成为系统的**网络定位提供者**，在国内 WiFi / 基站环境下即可使用。

## 效果

| 项目 | 效果 |
| --- | --- |
| 无 GPS 时的定位 | 秒级出结果，精度约 40 m（WiFi / 基站） |
| 地址反查 | 中文地址正常，例如「上海市, 浦东新区」「张江镇, 孙桥」 |
| 系统 fused provider | 走百度，天气 App、日出日落自动深色模式均正常 |
| GMS / microG 定位 | 自动回落到系统 network provider（模块会禁用 microG 自带的国外 NLP） |

实测环境：

- OnePlus 5T — LineageOS / Android 17 / KernelSU Next / microG：`TwilightState { sunrise=06:24 sunset=16:57 }` 与当地实际一致
- OnePlus 3T — crDroid / Android 11 / APatch：`Location result:[location successful by Baidu] locType=161, NetworkLocationType = wf`

## 安装

1. 需要 root 环境：
   - Magisk：直接安装 zip
   - APatch：`apd module install xxx.zip`
   - KernelSU / KernelSU Next：**必须先装元模块**（如 Magic Mount-rs），否则 systemless 文件不会挂载
2. 安装模块 zip，重启
3. 若天气 App 仍拿不到位置，**再重启一次**——首次安装需要两次开机才能完成权限修复
4. 首次触发定位时百度会弹一次隐私提示，手动点「同意」（无法自动化）

安装位置：

```
/system/priv-app/BaiduNetworkLocation/BaiduNetworkLocation.apk
/system/etc/permissions/privapp-permissions-com.baidu.map.location.xml
/system/etc/default-permissions/baidu-network-location.xml
```

## 验证

```bash
# 应该看到 packages={com.baidu.map.location}、connected=true
adb shell dumpsys location | sed -n '/network provider:/,/fused provider:/p'

# 定位成功后 last location 有值，netType=wf
adb shell logcat -d | grep " NLP " | tail
# Location result:[location successful by Baidu] locType=161, NetworkLocationType = wf
```

想手动触发一次定位（百度会静默丢弃开机后最前面的 3 次系统请求）：

```bash
adb shell cmd location set-location-enabled false
adb shell cmd location set-location-enabled true
```

## 模块做了什么

- 把 APK 放进 `priv-app` 并写 `privapp-permissions` 白名单，使其获得 `INSTALL_LOCATION_PROVIDER` 特权，可注册为网络定位提供者（**不重签 APK**）
- 补 `lib/arm64`、`lib/arm` 的 `libnlocSDK7d.so`（Android 12+ 不再解压系统 APK 内的 `.so`）
- 用 `default-permissions` + `service.sh` 兜底运行时定位权限
- 每次开机自动校验权限：缺哪个补哪个（百度 SDK 缺 `WRITE_EXTERNAL_STORAGE` 会直接返回 `no permission`，一个请求都不发）
- 模块被整体禁用（安全模式）后，系统会删掉这个预装应用及其数据；模块目录里留了一份应用数据快照，恢复后自动还原
- 开机完成后若还没有网络位置，自动触发一次定位（绕过百度 SDK 丢弃开机后前 3 次系统请求的问题）
- 模块「操作」按钮提供一键修复，无需重启
- Android 11+ 的「后台定位」：预装应用没有安装来源，系统会把 `ACCESS_BACKGROUND_LOCATION` 判为受限权限，导致退到后台就读不到 WiFi / 基站。`service.sh` 会自动补安装来源并修正权限库，无需手动操作
- 装了 microG 的设备上，自动禁用其自带的 fused / network 定位服务，让平台和 GMS 的定位都回落到百度

## 关闭自动修补

```bash
adb shell su -c 'touch /data/adb/baidu_nlp_no_autogrant'
```

## 卸载

在 root 管理器里删除模块并重启。若想恢复 microG 的定位服务：

```bash
adb shell su -c 'pm enable com.google.android.gms/org.microg.gms.location.provider.FusedLocationProviderService'
adb shell su -c 'pm enable com.google.android.gms/org.microg.gms.location.network.NetworkLocationService'
```

## 说明

- `com.baidu.map.location` 的版权归百度所有，本仓库只提供安装脚本与打包方式，供个人研究、自用
- 网络定位需要 WiFi 或 SIM 卡；没有 SIM 卡时依赖 WiFi
- 极少数 ROM 用 `config_locationProviderPackageNames` 白名单限制 provider 包名，这种情况单靠模块无法解决
