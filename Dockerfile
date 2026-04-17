# Flutter Docker 镜像用于构建和测试
# 支持 macOS（Intel 和 Apple Silicon）、Linux

FROM --platform=linux/amd64 cirrusci/flutter:stable AS builder

# 设置工作目录
WORKDIR /app

RUN adduser --disabled-password --gecos "" builder \
    && chown -R builder:builder /app
USER builder

# 复制项目文件
COPY pubspec.yaml ./
COPY analysis_options.yaml ./

# 先获取依赖（利用 Docker 缓存层）
RUN flutter pub get

# 复制源代码
COPY . .

# 生成 Hive 适配器代码
RUN dart run build_runner build --delete-conflicting-outputs

# Web 构建（用于快速测试）
RUN flutter build web --release

# Linux 构建（用于桌面端测试）
RUN flutter build linux --release

# ==================== 最终镜像（可选） ====================
# FROM alpine:latest
# WORKDIR /app
# COPY --from=builder /app/build/web ./web
# COPY --from=builder /app/build/linux ./linux
# EXPOSE 80
# CMD ["python3", "-m", "http.server", "80"]
