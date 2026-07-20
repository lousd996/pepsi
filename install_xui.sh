#!/bin/bash
set -e

echo "========================================"
echo " x-ui Docker 一键部署脚本"
echo "========================================"

# 停用并删除旧容器
echo "[1/3] 停止并删除旧容器..."
sudo docker stop x-ui 2>/dev/null && sudo docker rm x-ui 2>/dev/null
echo "  - 完成"

# 拉取最新镜像
echo "[2/3] 拉取最新镜像..."
sudo docker pull lousd996/manage-ui
echo "  - 完成"

# 启动新容器
echo "[3/3] 启动新容器..."
sudo docker run -d --net=host \
  --restart always \
  --name x-ui \
  --hostname x-ui \
  -v /etc/x-ui:/etc/x-ui \
  -v /etc/cert:/etc/cert \
  -e QQ=*** \
  -e DOMAIN=infodata.icu \
  -e HOSTNAME=hostname \
  -e WEBPORT=7310 \
  -e PASSWD=aZX4g94R5XLJ \
  lousd996/manage-ui

echo "  - 完成"
echo ""
echo "========================================"
echo " 部署完成！"
echo "========================================"
echo " 访问地址: http://infodata.icu:7310"
echo " 用户名: admin"
echo " 密码: aZX4g94R5XLJ"
echo ""
echo " 提示: 如需修改 QQ 号，请编辑本脚本中 -e QQ=*** 部分"
