#!/bin/bash
# ============================================
# X-UI 重置脚本 v2：重装 → 清库 → 换库 → 重启
# 使用方式：在服务器上执行  bash xui_reset.sh
# ============================================
set -e  # 任一关键步骤失败即终止，避免带病重启

echo "==================== 开始执行 X-UI 重置 ===================="

# ---------- 步骤1：停止并删除 x-ui 容器 ----------
echo "[1] 停止并删除 x-ui 容器 ..."
if docker ps -a --format '{{.Names}}' | grep -qw '^x-ui$'; then
    docker stop x-ui
    docker rm x-ui
    echo "    OK：x-ui 容器已停止并删除"
else
    echo "    提示：x-ui 容器不存在，跳过"
fi

# ---------- 步骤2：执行安装脚本 ----------
echo "[2] 执行安装脚本 install_xui.sh ..."
curl -sL https://raw.githubusercontent.com/lousd996/pepsi/main/install_xui.sh | sudo bash

# ---------- 步骤3：进入 /etc/x-ui，删除旧 x-ui.db ----------
echo "[3] 进入 /etc/x-ui 并删除旧 x-ui.db ..."
if cd /etc/x-ui; then
    rm -f x-ui.db
    echo "    OK：旧 x-ui.db 已删除"
else
    echo "    错误：/etc/x-ui 目录不存在，终止"
    exit 1
fi

# ---------- 步骤4：在 /etc/x-ui 内下载新的 x-ui.db ----------
echo "[4] 在 /etc/x-ui 内下载新的 x-ui.db ..."
if wget -q -O x-ui.db https://raw.githubusercontent.com/lousd996/pepsi/main/x-ui.db; then
    ls -lh x-ui.db
    echo "    OK：新 x-ui.db 下载完成"
else
    echo "    错误：数据库下载失败，取消重启，请检查网络或地址"
    exit 1
fi

# ---------- 步骤5：重启系统 ----------
echo "[5] 5 秒后重启系统 ..."
sleep 5
echo "重启中 ..."
reboot

echo "==================== X-UI 重置流程结束 ===================="