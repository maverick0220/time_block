# ==============================================================================
# TimeBlock 服务端 Docker 镜像
# ==============================================================================
#
# 【打包方式】
# 在项目根目录执行：
#   docker build -t timeblock-server:latest -f server/Dockerfile .
#
# 【运行方式】
#
# 方式一：快速启动（使用默认配置）
#   docker run -d \
#     --name timeblock-server \
#     -p 5001:5001 \
#     -v $(pwd)/server:/app \
#     timeblock-server:latest
#
# 方式二：指定端口（如果宿主机 5001 被占用）
#   docker run -d \
#     --name timeblock-server \
#     -p 8888:8888 \
#     -e PORT=8888 \
#     -v $(pwd)/server:/app \
#     timeblock-server:latest
#
# 方式三：完整数据持久化（数据库单独挂载，防止容器删除后数据丢失）
#   mkdir -p ./data/timeblock
#   docker run -d \
#     --name timeblock-server \
#     -p 5001:5001 \
#     -v $(pwd)/server:/app \
#     -v $(pwd)/data/timeblock:/app/data \
#     timeblock-server:latest
#
# 【CI/CD 部署示例】
#
# GitHub Actions workflow (deploy.yml):
#   jobs:
#     deploy:
#       runs-on: ubuntu-latest
#       steps:
#         - uses: actions/checkout@v4
#         - name: Build Docker image
#           run: docker build -t timeblock-server:${{ github.sha }} -f server/Dockerfile .
#         - name: Stop old container
#           run: docker stop timeblock-server || true
#         - name: Remove old container
#           run: docker rm timeblock-server || true
#         - name: Run new container
#           run: |
#             docker run -d \
#               --name timeblock-server \
#               -p 5001:5001 \
#               -v $(pwd)/server:/app \
#               -v ${{ secrets.HOST_DATA_PATH }}:/app/data \
#               timeblock-server:${{ github.sha }}
#
# 【挂载说明】
#   - /app        → 源代码挂载点（修改代码后无需重新构建镜像）
#   - /app/data   → 数据库数据目录（建议持久化，避免数据丢失）
#
# 【端口说明】
#   - 内部端口: 5001（默认）
#   - 可通过环境变量 PORT 覆盖
#
# ==============================================================================

FROM python:3.11-slim

LABEL maintainer="TimeBlock"
LABEL description="TimeBlock Flutter App Sync Server"

WORKDIR /app

# 安装依赖
COPY server/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 复制源码（代码通过挂载覆盖）
COPY server/ .

# 创建数据目录
RUN mkdir -p /app/data

# 暴露端口（默认 5001，兼容 macOS AirPlay 占用的 5000）
EXPOSE 5001

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:${PORT:-5001}/ping')" || exit 1

# 启动命令（支持 PORT 环境变量）
CMD ["sh", "-c", "python app.py"]
