# BarMatrix

一个极简的 macOS 菜单栏整理工具：把不常用的菜单栏图标折叠起来，需要时一点就展开。

## 用法

1. 启动后菜单栏会多出一个折叠按钮 `‹` 和一条细竖线 `│`。
2. 右键 `‹` 打开设置，在「菜单栏图标」列表里关掉不常用的图标，它们就会被挪到竖线**左边**收起来。也可以按住 ⌘ 直接拖动图标。
3. 点击 `‹` 在菜单栏里展开或收起隐藏的图标，展开后会按设置自动收起。

原理：折叠时把分隔线的宽度撑到很大，把它左边的图标挤出屏幕。

## 权限

只用折叠和展开不需要任何权限。在设置里切换图标的隐藏或显示需要**辅助功能**权限，用来替你 ⌘ 拖动菜单栏图标。

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
