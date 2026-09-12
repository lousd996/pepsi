#!/bin/bash
# ============================================
# X-UI 重置脚本：重装并恢复数据库后重启系统
# 使用方式：在服务器上执行  sudo bash xui_reset.sh
# ============================================

echo "==================== 开始执行 X-UI 重置 ===================="

# ---------- 步骤1：停止 x-ui 容器 ----------
echo "[1/6] 停止 x-ui 容器 ..."
if docker ps -a --format '{{.Names}}' | grep -qw "^x-ui$"; then
    docker stop x-ui
    echo "      x-ui 已停止"
else
    echo "      未找到 x-ui 容器，跳过停止"
fi

# ---------- 步骤2：删除 x-ui 容器 ----------
echo "[2/6] 删除 x-ui 容器 ..."
if docker ps -a --format '{{.Names}}' | grep -qw "^x-ui$"; then
    docker rm x-ui
    echo "      x-ui 已删除"
else
    echo "      x-ui 容器不存在，跳过删除"
fi

# ---------- 步骤3：执行安装脚本 ----------
echo "[3/6] 执行安装脚本 install_xui.sh ..."
curl -sL https://raw.githubusercontent.com/lousd996/pepsi/main/install_xui.sh | sudo bash

# ---------- 步骤4：进入 /etc/x-ui 并删除 x-ui.db ----------
echo "[4/6] 删除 /etc/x-ui/x-ui.db ..."
if cd /etc/x-ui 2>/dev/null; then
    rm -f x-ui.db
    echo "      /etc/x-ui/x-ui.db 已删除"
else
    echo "错误：目录 /etc/x-ui 不存在，脚本终止"
    exit 1
fi

# ---------- 步骤5：下载新的 x-ui.db ----------
echo "[5/6] 下载新的 x-ui.db ..."
if wget -O x-ui.db https://raw.githubusercontent.com/lousd996/pepsi/main/x-ui.db; then
    echo "      新 x-ui.db 下载完成"
else
    echo "错误：数据库下载失败，已取消重启，请检查网络或地址"
    exit 1
fi

# ---------- 步骤6：重启系统 ----------
echo "[6/6] 5 秒后重启系统 ..."
sleep 5
echo "重启中 ..."
reboot

echo "==================== X-UI 重置流程结束 ===================="