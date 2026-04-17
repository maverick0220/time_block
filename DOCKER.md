# Flutter Docker 测试指南

本项目已配置 Docker 构建，可以在没有 Flutter SDK 的环境下测试代码编译。

## 🚀 快速开始

### 方式一：使用构建脚本（推荐）

```bash
cd ~/Downloads/time_block
./build-docker.sh
```

菜单选项：
- `1` 快速检查 - 仅验证代码编译（最快）
- `2` Web 构建 - 在浏览器中测试功能
- `3` Linux 构建 - 测试桌面端（非 macOS）
- `4` 完整测试 - Web + Linux 构建
- `5` 清理 - 删除 Docker 镜像和缓存

### 方式二：手动执行 Docker 命令

#### 快速编译检查
```bash
docker run --rm \
    -v "$PWD:/app" \
    -w /app \
    cirrusci/flutter:stable \
    sh -c "flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter analyze"
```

#### 构建 Web 版本
```bash
docker run --rm \
    -v "$PWD:/app" \
    -w /app \
    cirrusci/flutter:stable \
    sh -c "flutter pub get && dart run build_runner build && flutter build web --release"
```

构建完成后，启动本地服务器：
```bash
cd build/web
python3 -m http.server 8080
```
然后打开浏览器访问：`http://localhost:8080`

#### 使用 Docker Compose
```bash
docker-compose up builder
```

---

## 📦 构建产物说明

### Web 构建
- **位置**: `build/web/`
- **用途**: 测试核心逻辑、UI 渲染、Hive 数据存储（使用 IndexedDB）
- **运行方式**:
  ```bash
  cd build/web
  python3 -m http.server 8080
  ```
  或使用任何静态文件服务器

### Linux 构建
- **位置**: `build/linux/x64/release/`
- **注意**: 这是 Linux x64 可执行文件，无法在 macOS 上直接运行
- **用途**: 验证桌面端代码编译，测试非 macOS 平台的 Hive 路径逻辑

---

## 🔍 测试重点

### 1. Hive 跨平台初始化
由于我们在 Docker 中构建 Linux 版本，可以验证：
- `Hive.initFlutter()` 在 Linux 上的路径是否正确
- 代码中的 `Platform.isX` 检查是否正常工作

### 2. window_manager 平台检查
虽然无法在 Docker 中运行桌面 GUI，但可以验证编译：
- `window_manager` 依赖不会导致移动端编译失败
- 代码中的 `if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)` 块正常工作

### 3. 数据迁移功能
虽然 Docker 环境中没有旧数据，但可以验证：
- `migrateOldData.dart` 导入和函数调用不会报错
- `main.dart` 中注释/取消注释迁移代码不影响编译

---

## ⚙️ 架构支持

### Apple Silicon (M1/M2/M3)
脚本会自动检测并使用 `linux/arm64` 平台：
```bash
docker run --platform linux/arm64 ...
```

### Intel Mac
脚本会自动检测并使用 `linux/amd64` 平台：
```bash
docker run --platform linux/amd64 ...
```

---

## 🐛 常见问题

### 1. Docker 镜像下载慢
- 使用国内镜像源：
  ```bash
  # 编辑 Docker daemon 配置（macOS: Docker Desktop > Settings > Docker Engine）
  {
    "registry-mirrors": [
      "https://docker.mirrors.ustc.edu.cn",
      "https://hub-mirror.c.163.com"
    ]
  }
  ```

### 2. 权限错误
```bash
chmod +x build-docker.sh
```

### 3. 端口被占用
如果 Web 服务器端口 8080 被占用，修改为其他端口：
```bash
cd build/web
python3 -m http.server 3000  # 使用 3000 端口
```

### 4. Flutter 版本不匹配
Docker 镜像使用的是稳定版 Flutter，如果项目有特殊的 Flutter 版本要求，修改 Dockerfile：
```dockerfile
FROM cirrusci/flutter:3.19.6  # 指定版本
```

---

## 📊 macOS 真实编译

在 Mac 上直接编译（需要安装 Flutter SDK）：

```bash
# 安装 Flutter（如果还没有）
# curl -fsSL https://flutter.dev/install.sh | bash

# 进入项目目录
cd ~/Downloads/time_block

# 获取依赖
flutter pub get

# 生成 Hive 适配器
dart run build_runner build --delete-conflicting-outputs

# macOS 桌面编译
flutter build macos --release

# 运行
open build/macos/Build/Products/Release/time_block.app
```

---

## ✅ 验证清单

- [ ] 快速编译检查通过（选项 1）
- [ ] Web 构建成功
- [ ] Linux 构建成功
- [ ] 在浏览器中打开 Web 版本，UI 正常显示
- [ ] 测试选择时间块功能
- [ ] 测试事件记录功能
- [ ] 检查控制台日志，确认 Hive 路径正确

---

## 📝 技术细节

### Docker 镜像
- **基础镜像**: `cirrusci/flutter:stable`
- **包含工具**: Flutter SDK, Dart, build_runner
- **大小**: 约 2-3 GB

### 构建流程
1. 复制 `pubspec.yaml` 和 `analysis_options.yaml`
2. 运行 `flutter pub get`（缓存依赖）
3. 复制所有源代码
4. 运行 `dart run build_runner build`（生成 Hive 适配器）
5. 运行 `flutter build`（构建目标平台）

---

有任何问题，请查看日志输出或检查 Docker 状态：
```bash
docker ps -a
docker logs <container_id>
```
