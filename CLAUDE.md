# Whisker - Development Rules

## Version Management

- **每次发布 GitHub Release 必须递增版本号**，绝不重复使用已发布的版本号。
- 发布前先查看最新的 git tag (`git tag --sort=-v:refname | head -5`) 来确认当前最高版本号。
- 新版本号 = 最高已有版本号 + 1（patch 位递增）。
- 需要同步更新的地方：`Info.plist`（CFBundleShortVersionString + CFBundleVersion）、`README.md` 中的 zip 文件名。
