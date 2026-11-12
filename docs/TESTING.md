# 在模拟器上验证字体是否生效

真机上模块靠 Magisk 的 overlay 挂载生效；模拟器没有 Magisk，所以测试用 `mount --bind`
把**同样的文件**压到 `/system` 上，等价于模块挂载后的结果：

| | 真机 + 模块 | 模拟器测试 |
| --- | --- | --- |
| 挂载方式 | Magisk 在 `post-fs-data` 阶段 overlay `/system` | `mount --bind` 覆盖 `/system/fonts` 与 `/system/etc/fonts.xml` |
| `system/fonts/MiSans-*.ttf` | 模块目录提供 | `adb push` 到 `/data/local/tmp/misans` |
| `system/etc/fonts.xml` | 模块目录提供 | `adb push` 到 `/data/local/tmp/misans/fonts.xml` |
| 重启后是否保留 | 是（模块在就一直在） | 否，需要重新 bind |
| 验证代价 | 重启 | `stop; start` 重启 framework，约 40 秒 |

> 不要用 `adb remount`：在这台 API 30 AVD 上它会触发 `Disabling verity`，
> 之后的重启会卡在开机动画（overlayfs 写入 `/system` 也会持续报
> `Read-only file system`）。bind mount 不碰分区表，稳定得多。

## 前置

```powershell
sdkmanager "system-images;android-30;default;x86_64"
```

模拟器建议这样启动（`-no-window` 也能截图）：

```powershell
emulator -avd a11-test -wipe-data -no-snapshot -no-snapshot-save `
         -no-audio -no-boot-anim -no-window -gpu swiftshader_indirect
```

## 流程

1. 冷启动，等 `sys.boot_completed=1`；`adb root`。
2. 把系统字体目录整份复制出来当基底，再把模块字体推进去：

   ```sh
   rm -rf /data/local/tmp/misans && mkdir -p /data/local/tmp/misans
   cp -a /system/fonts/. /data/local/tmp/misans/
   chmod 644 /data/local/tmp/misans/*
   chcon -R u:object_r:system_file:s0 /data/local/tmp/misans
   ```

3. 覆盖挂载（`fonts.xml` 单独 bind，因为它是文件不是目录）：

   ```sh
   mount --bind /data/local/tmp/misans            /system/fonts
   mount --bind /data/local/tmp/misans/fonts.xml  /system/etc/fonts.xml
   ```

4. 重启 framework 让 Minikin 重新读字体表：`stop; sleep 2; start`，等
   `pidof com.android.systemui` 有输出。
5. 截图并检查 `logcat`。

## 换字重/换配置时的坑

- 修改 `/data/local/tmp/misans/fonts.xml` 后**必须重新 bind**：直接写入会沿用旧的
  挂载点（inode 已被旧文件占用），`md5sum /system/etc/fonts.xml` 不会变。
  正确顺序是 `umount /system/etc/fonts.xml` → `adb push` → `chcon` → `mount --bind`。
- 只改 `fonts.xml` 而不把对应 ttf 推进 `/data/local/tmp/misans`，Minikin 会静默回退到
  其它字体，截图看起来像“改了没效果”。改配置后先确认
  `ls /system/fonts | grep MiSans` 里有你要的文件。
- 中文界面：`setprop persist.sys.locale zh-CN` 后同样用 `stop; start` 生效，不用重启系统。

## 脚本

```powershell
.\tools\device-test.ps1 -KeepRunning     # 现成的 remount 流程，仅供参考
.\tools\compare-shots.ps1 dist\test\1-before.png dist\test\2-after-settings.png
```

`compare-shots.ps1` 输出改动像素占比：字体整体换掉后设置页应出现明显差异，
若接近 0% 说明 `fonts.xml` 没有生效。

## 判断标准

- 能正常开机进桌面（`fonts.xml` 解析失败会导致 system_server 起不来）
- `logcat` 中没有 `Font asset not found` / `Cannot load font` / `Unable to load font`
- 修改前后截图差异明显，且中文不是豆腐块
- 同一段文字的暗像素数量随字重单调变化（`dist\test\weights-compare.png` 就是这么比出来的）
