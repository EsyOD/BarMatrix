# BarMatrix

一个极简的 macOS 菜单栏整理工具：把不常用的菜单栏图标折叠起来，需要时一点就展开。

## 用法

1. 启动后菜单栏会多出一个折叠按钮 `‹` 和一条细竖线 `│`。
2. 按住 ⌘ 拖动菜单栏图标，把不常用的放到竖线**左边**。
3. 收起后点击 `‹` 会在下方弹出小面板，列出被隐藏的图标，左键点哪个，就像 Bartender 一样把它临时挪到 `‹` 旁边并打开它的菜单，用完后自动放回隐藏区；右键则直接打开它所属的应用。
4. 按住 ⌥ 点击 `‹` 则直接在菜单栏里展开（可在设置里对调这两种方式）。
5. 右键折叠按钮打开设置：点击方式、自动折叠、折叠延迟、登录时启动、权限状态。

原理：折叠时把分隔线的宽度撑到很大，把它左边的图标挤出屏幕。

## 权限

只用折叠和展开不需要任何权限。弹出面板需要两项：

- **屏幕录制**：截取隐藏图标的画面，显示在面板里
- **辅助功能**：点击面板里的图标时，替你点一下菜单栏里真正的图标

都可以在设置窗口的「权限」一栏一键前往授权。测试版没有正式签名，每次更新版本后 macOS 可能要求重新授权。

## 下载

到 [Releases](https://github.com/EsyOD/BarMatrix/releases) 下载 `BarMatrix.zip`（`latest` 是 main 分支的最新构建），解压后拖进「应用程序」。

应用没有经过 Apple 公证，第一次打开如果提示“已损坏”或“无法验证开发者”，在终端运行：

```sh
xattr -dr com.apple.quarantine /Applications/BarMatrix.app
```

## 从源码运行

需要 macOS 14+ 和 Xcode 15+（或 Swift 5.9 工具链）。

```sh
swift run                 # 直接运行
./scripts/bundle.sh       # 打包成 build/BarMatrix.app
open build/BarMatrix.app
```

「登录时启动」需要用打包后的 .app 运行才生效。

应用图标由 `scripts/make_icon.py`（需要 Pillow）生成到 `Resources/AppIcon.png`，打包时自动转换为 `.icns`。
