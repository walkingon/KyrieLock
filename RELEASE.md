# KyrieLock Release Guide

## 自动构建发布流程

本项目已配置 GitHub Actions 自动构建多平台安装包。

### 如何发布新版本

运行脚本new_release.ps1并传递版本号参数，例如：
```
# 版本号需严格遵守示例格式 v版本号+自增构建号
.\new_release.ps1 v1.1.0+2
```

### 支持的平台

自动构建会生成以下平台的安装包：

- **Android**: `app-release.apk`
- **Windows**: `kyrie-lock-windows.zip` (解压后运行)
- **macOS**: `kyrie-lock-macos.dmg` 或 `kyrie-lock-macos.zip`
- **Linux**: `kyrie-lock-linux.tar.gz` (解压后运行)

### 用户下载方式

用户可以在 GitHub Releases 页面选择对应平台的安装包下载：
```
https://github.com/walkingon/KyrieLock/releases
```

### 注意事项

- tag 必须以 `v` 开头（如 `v1.0.0`）
- 首次运行需要在 GitHub 仓库设置中启用 Actions
- 构建时间约 15-30 分钟（多平台并行）
- 确保 `pubspec.yaml` 中的版本号与 tag 保持一致
