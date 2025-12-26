# KyrieLock Release Guide

## 自动构建发布流程

本项目已配置 GitHub Actions 自动构建多平台安装包。

### 如何发布新版本

1. **更新版本号**
   编辑 `pubspec.yaml` 文件中的版本号：
   ```yaml
   version: 1.0.0+1  # 修改为新版本，如 1.1.0+2
   ```

2. **提交代码**
   ```bash
   git add .
   git commit -m "Release v1.1.0"
   ```

3. **创建并推送 tag**
   ```bash
   git tag v1.1.0
   git push origin main
   git push origin v1.1.0
   ```

4. **自动构建**
   - GitHub Actions 会自动开始构建
   - 构建完成后会自动创建 Release
   - 访问 `https://github.com/your-username/KyrieLock/releases` 查看

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
