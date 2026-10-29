# BarMatrix

一个极简的 macOS 菜单栏整理工具：把不常用的菜单栏图标折叠起来，需要时一点就展开。

## 用法

1. 启动后菜单栏会多出一个折叠按钮 `‹` 和一条细竖线 `│`。
2. 按住 ⌘ 拖动菜单栏图标，把不常用的放到竖线**左边**。
3. 点击 `‹` 在菜单栏里收起或展开它们，展开后会按设置自动收起。
4. 右键 `‹` 打开设置：自动折叠、折叠延迟、分隔线、登录时启动。

原理：折叠时把分隔线的宽度撑到很大，把它左边的图标挤出屏幕。不需要任何系统权限。

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
