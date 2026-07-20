#!/bin/bash
set -e

echo "========================================"
echo " Ubuntu 20.04 (Focal) Docker 一键安装"
echo "========================================"

# 1. 修复 apt 源（Focal 已 EOL，切换到 old-releases）
echo "[1/5] 修复 apt 软件源..."
sudo sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
sudo sed -i 's/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list
sudo apt-get update -qq

# 2. 安装前置依赖
echo "[2/5] 安装前置依赖..."
sudo apt-get install -y -qq ca-certificates curl

# 3. 添加 Docker 官方源
echo "[3/5] 添加 Docker 官方软件源..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu focal stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -qq

# 4. 安装 Docker 组件
echo "[4/5] 安装 Docker 组件..."
sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-ce-rootless-extras

# 5. 启动 Docker 并验证
echo "[5/5] 启动 Docker 服务..."
sudo service docker start 2>/dev/null || sudo dockerd &

echo ""
echo "========================================"
echo " 安装完成！验证中..."
echo "========================================"
sudo docker --version
sudo docker compose version
echo ""
echo "运行 hello-world 测试..."
sudo docker run hello-world 2>&1 | tail -5

echo ""
echo "提示：如需免 sudo 运行 Docker，请执行："
echo "  sudo usermod -aG docker \$USER"
echo "  然后退出终端重新登录"
