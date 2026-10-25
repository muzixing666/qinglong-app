# 从源码构建

当前验证环境：Flutter 3.47.7、Dart 3.13.5、JDK 17、Android SDK 36。Android 最低版本为 8.0（API 26）。

```bash
git clone https://github.com/muzixing666/qinglong-app.git
cd qinglong-app/flutter_app
flutter pub get
flutter test
flutter analyze
flutter build apk --debug
```

生成的调试包位于 `flutter_app/build/app/outputs/flutter-apk/app-debug.apk`。

仓库不包含发行签名密钥、面板连接数据或本地 SDK 路径。没有发行密钥时，调试构建使用开发者自己的 Android 调试签名，不能覆盖安装官方签名包。构建正式发行版前请在 `flutter_app/android/app/build.gradle.kts` 中配置自己的签名；不要提交密钥或密码。

`flutter_app/android/app/src` 已包含本版本同步后的原生服务。修改 `app/src/main/java` 后，可在仓库根目录运行 `python scripts/prepare-flutter.py` 重新同步。离线编辑器源文件位于 `editor/src`；修改后在 `editor` 目录执行 `npm ci && node build.mjs`，再同步原生资源。

目录说明：

- `flutter_app/lib`：Flutter 页面、状态与交互。
- `flutter_app/android`：Android 平台工程与离线编辑器组件。
- `app/src/main/java`：面板接口、加密连接、文件导入等原生服务源文件。
- `editor`：离线代码编辑器及语法高亮。
- `docs/screenshots`：演示数据的软件截图。

平台功能验证应使用本地演示模式。执行集成测试前请确认设备数据已备份，并避免使用卸载或清除数据的命令。
