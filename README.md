# CXW focus

轻量级原生 macOS（Swift / AppKit + SwiftUI）沉浸式专注 Dock 工具，支持 Apple Silicon（`arm64`）与 Intel（`x86_64`）双架构。

## 下载与安装

1. 前往本仓库右侧 **Releases** 页面下载最新版 `CXW-focus-1.0.0.dmg`（或 `CXW-focus-1.0.0.zip`）。
2. 打开 `.dmg` 后将 **`CXW focus.app`** 拖入 **`Applications（应用程序）`** 文件夹。
3. 由于本项目为个人本地编译签名（未使用付费 Apple 开发者证书公证），首次打开若系统提示「无法验证开发者」或「已损坏」，请在「终端」中运行一次以下命令后再打开：

```bash
xattr -cr "/Applications/CXW focus.app"
```

## 核心功能

- **分档白名单与临时插槽**：内置「开发 / 写作 / 学习」初始档位，支持自由增删预设软件；沉浸过程中可随时点击 Dock 右侧 `+` 临时加入软件（带橙色圆点标记，退出沉浸后自动清空）。
- **原生透明磨砂悬浮 Dock**：四边连续圆角通透毛玻璃样式，支持在设置或状态栏菜单中切换 **常驻显示** 或 **自动隐藏（指针移至屏幕底部呼出）**。
- **最小化窗口区**：点击白名单应用黄色最小化按钮后，窗口缩略图会收拢在 Dock 右侧分隔线后方，点击即可恢复。
- **纯净桌面与极简顶部状态栏**：进入沉浸模式时自动屏蔽系统原生 Dock、遮蔽桌面文件与小组件，并隐藏菜单栏右侧多余图标（仅保留当前档位与日期时间）。
- **按档位静音通知**：支持为每个档位和退出动作绑定 macOS「快捷指令」，自动切换对应的系统专注模式。
- **命令行工具 `cxwfocus`**：内置 `cxwfocus status / list / enter / exit / add / remove / save-layout`，方便接入自动化脚本或 AI 工作流。

## 权限与可选配置

- **辅助功能权限**：如需使用「Dock 右侧显示最小化窗口」与「记住 / 还原窗口布局」，在菜单栏弹窗或偏好设置「权限与联动」页点击「授权」并勾选 `CXW focus`。
- **通知静音**：在系统「快捷指令」App 中创建包含「设定专注模式」动作的指令，并在 `CXW focus` 偏好设置中绑定对应档位。

## 从源码构建与导出

要求 macOS 14+ 与 Xcode / Swift 命令行工具：

```bash
# 本地编译打包到 build/CXW focus.app
./scripts/build-app.sh

# 运行核心单元测试
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# 导出双架构通用版 .dmg 与 .zip 到 dist/
./scripts/export-release.sh
```
