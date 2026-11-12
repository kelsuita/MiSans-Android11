# MiSans System Font for Android 11 (Magisk)

把 Android 11 类原生 ROM 的默认字体整体替换为小米 **MiSans**，包含多字重，并保留
Noto Sans CJK 作为缺字回退。

- 模块 ID：`misans_font`
- 目标：Android 11（SDK 30），AOSP / LineageOS 等类原生 ROM
- 需要：Magisk 20.4 及以上

## 两个版本，按手感选一个

同一个字体，只是默认字重不同。刷入后想换，直接刷另一个版本覆盖即可。

| Release 文件 | 默认字重（400） | 观感 |
| --- | --- | --- |
| `MiSans-Android11-v1.0.0-Bold.zip` | MiSans **Demibold** (450) | **加粗版**，正文明显厚实，接近 MIUI |
| `MiSans-Android11-v1.0.0-Stock.zip` | MiSans **Regular** (330) | **不加粗版**，贴近 MiSans 官方命名，最轻 |

为什么要单独做“加粗版”：MiSans 的 Regular(330) 与 Medium(380) 笔画差太小，在 1080p
屏上实测渲染结果**像素级相同**，所以“把 Medium 设成默认”看起来就像没换字体。
真正肉眼可辨的第一档是 Demibold(450)，这就是加粗版的默认值。

两者共用同一张 `fonts.xml`，区别只在 `weight="400"` / `weight="500"` 指向哪个文件。

## 它会改什么

| 系统字体族 | 原来 | 现在 |
| --- | --- | --- |
| `sans-serif`（默认字体） | Roboto | MiSans（见下表字重） |
| `sans-serif-condensed`（部分桌面、系统组件） | Roboto Condensed | MiSans（同上，非压缩字宽） |
| `zh-Hans`（简体中文） | Noto Sans CJK SC | **先** MiSans，**再** 回退到 Noto Sans CJK SC |
| `zh-Hant` / `ja` / `ko` | Noto Sans CJK | 不变 |
| `serif` / `monospace` | Noto Serif / Droid Sans Mono | 不变 |
| Emoji、符号、其它语种 | Noto / 系统原字体 | 不变 |

具体做法只有两件事：往 `/system/fonts` 放入 MiSans 字体文件，并覆盖
`/system/etc/fonts.xml`（以 AOSP 11 官方字体表为底本，仅改动上面几处）。
Magisk 以 systemless 方式挂载，不会真的修改 `/system` 分区。

保留 Noto 回退的原因是 MiSans 商用版约 2.9 万个字形，生僻汉字、韩文等未被覆盖的
字符仍然能从 Noto Sans CJK 取到，不会出现“豆腐块”。

## 字重

`fonts.xml` 里的 `weight` 是“声明值”，真正渲染的粗细来自字体文件本身。
两个版本的阶梯：

| 声明值 | 加粗版 | 不加粗版 | 内部 usWeightClass |
| --- | --- | --- | --- |
| 300 | MiSans-Light | MiSans-Light | 250 |
| **400（正文默认）** | **MiSans-Demibold** | **MiSans-Regular** | 450 / 330 |
| 500 | MiSans-Semibold | MiSans-Medium | 520 / 380 |
| 700 | MiSans-Bold | MiSans-Bold | 630 |
| 900 | MiSans-Heavy | MiSans-Heavy | 700 |

斜体槽位故意留空：MiSans 没有真斜体，让 Minikin 回退到最接近的直立字重，
比合成一个歪斜的字形好看。

想自定义：改 `system/etc/fonts.xml` 里的文件名后重新打包。`weight="400"` 一共三处
（`sans-serif`、`sans-serif-condensed`、`zh-Hans`）。

## 安装

1. 从 [Releases](../../releases) 下载 `-Bold` 或 `-Stock` 的 zip。
2. Magisk App → 模块 → 从本地安装 → 选择 zip。
3. 重启。首次开机后系统界面、设置、浏览器、第三方 App 的拉丁字母与简体中文都会是 MiSans。

Magisk 会保留系统原文件，卸载模块（Magisk 里移除并重启）即完全恢复，无需备份。

## 出问题怎么办

- **开机后字体异常 / 界面错乱**：Magisk 连续两次启动失败会自动停用模块；也可以进
  Recovery 删除 `/data/adb/modules/misans_font`（或在该目录建一个 `disable` 空文件）。
- 只想要拉丁字母是 MiSans、中文保持系统字体：删掉 `system/etc/fonts.xml` 中
  `<family lang="zh-Hans">` 的 MiSans 那一段，重新打包。
- 觉得中文太粗/太细：换另一个版本；或按上面「字重」一节改文件名。
- 显示偏大或偏挤：MiSans 与 Roboto 的度量不同，属于正常差异；需要精确对齐时可以
  用 RobotoFake 之类保持行高的思路自行微调。

## 目录结构

```
module.prop
customize.sh
system/etc/fonts.xml          # AOSP 11 fonts.xml，改为 MiSans（加粗版）
system/fonts/MiSans-*.ttf     # 两个版本合计 7 个字重
META-INF/...                  # Magisk 安装脚本
build.ps1                     # 打包脚本（Windows PowerShell）
docs/TESTING.md               # 模拟器验证方法
docs/screenshots/             # 实机截图
```

## 重新打包

```powershell
.\build.ps1            # 加粗版 -> dist\MiSans-Android11-v1.0.0-Bold.zip
.\build.ps1 -Profile stock   # 不加粗版 -> dist\MiSans-Android11-v1.0.0-Stock.zip
.\build.ps1 -All             # 两个都打
```

`build.ps1` 会检查 `fonts.xml` 引用到的每个 ttf 是否存在，并且只把当前版本用到的
字体放进 zip。

## 在模拟器上验证

`docs/TESTING.md` 记录了完整流程：API 30 AOSP 镜像 + `mount --bind` 把模块文件压到
`/system`（等价于 Magisk 的挂载结果），`stop; start` 重启 framework 后截图对比，
并检查 logcat 有无字体报错。

## 字体许可

MiSans 由小米发布，可免费商用，版权归小米所有；本模块只做系统字体替换，未修改字形。
许可说明见 <https://hyperos.mi.com/font>。请勿将字体文件单独售卖。
