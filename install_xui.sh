#!/bin/bash
#
# X-UI Manager 一键安装脚本
# lousd996/manage-ui
# ============================================

set -e

# ---- Color Output ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ---- Banner ----
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}    X-UI Manager 一键部署脚本${NC}"
echo -e "${CYAN}    镜像: lousd996/manage-ui${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# ---- Step 0: Root check ----
if [[ $EUID -ne 0 ]]; then
    error "请以 root 身份运行此脚本 (sudo bash install_xui.sh)"
    exit 1
fi

# ========================================
# Step 1: 安装 Docker
# ========================================
echo ""
info "========== Step 1/4: 安装 Docker =========="

if command -v docker &>/dev/null; then
    success "Docker 已安装，跳过安装步骤"
else
    info "正在安装 Docker..."
    curl -fsSL https://get.docker.com/ | sh
    success "Docker 安装完成"
fi

# ---- 启动 Docker ----
info "正在启动 Docker 服务..."
if ! systemctl is-active --quiet docker; then
    systemctl start docker
fi
systemctl enable docker
success "Docker 服务已启动并设置为开机自启"

# ---- 验证 Docker 状态 ----
if systemctl is-active --quiet docker; then
    success "Docker 运行正常"
else
    error "Docker 未正常运行，请检查"
    exit 1
fi

# ========================================
# Step 2: 停止并移除旧容器
# ========================================
echo ""
info "========== Step 2/4: 清理旧容器 =========="

if docker ps -a --format '{{.Names}}' | grep -q "^x-ui$"; then
    info "发现旧容器 x-ui，正在停止并移除..."
    docker stop x-ui
    docker rm x-ui
    success "旧容器已清理"
else
    info "未发现旧容器 x-ui，跳过清理"
fi

# ========================================
# Step 3: 拉取最新镜像
# ========================================
echo ""
info "========== Step 3/4: 拉取最新镜像 =========="

docker pull lousd996/manage-ui
success "镜像拉取完成"

# ========================================
# Step 4: 启动新容器
# ========================================
echo ""
info "========== Step 4/4: 启动新容器 =========="

# ---- 交互式配置 ----
echo ""
echo -e "${YELLOW}请配置以下参数（留空则使用默认值）:${NC}"

DEFAULT_QQ="***"
DEFAULT_DOMAIN="infodata.icu"
DEFAULT_HOSTNAME="hostname"
DEFAULT_WEBPORT="7310"
DEFAULT_PASSWD="admin"

read -p "$(echo -e ${CYAN})QQ号${NC} (默认: $DEFAULT_QQ): " INPUT_QQ
QQ="${INPUT_QQ:-$DEFAULT_QQ}"

read -p "$(echo -e ${CYAN})域名${NC} (默认: $DEFAULT_DOMAIN): " INPUT_DOMAIN
DOMAIN="${INPUT_DOMAIN:-$DEFAULT_DOMAIN}"

read -p "$(echo -e ${CYAN})主机名${NC} (默认: $DEFAULT_HOSTNAME): " INPUT_HOSTNAME
HOSTNAME="${INPUT_HOSTNAME:-$DEFAULT_HOSTNAME}"

read -p "$(echo -e ${CYAN})Web 端口${NC} (默认: $DEFAULT_WEBPORT): " INPUT_WEBPORT
WEBPORT="${INPUT_WEBPORT:-$DEFAULT_WEBPORT}"

read -p "$(echo -e ${CYAN})管理密码${NC} (默认: $DEFAULT_PASSWD): " INPUT_PASSWD
PASSWD="${INPUT_PASSWD:-$DEFAULT_PASSWD}"

echo ""
info "配置汇总:"
echo "  QQ       = $QQ"
echo "  DOMAIN   = $DOMAIN"
echo "  HOSTNAME = $HOSTNAME"
echo "  WEBPORT  = $WEBPORT"
echo "  PASSWD   = $PASSWD"
echo ""

# ---- 运行容器 ----
info "正在启动 X-UI 容器..."

docker run -d --net=host \
    --restart always \
    --name x-ui \
    --hostname x-ui \
    -v /etc/x-ui:/etc/x-ui \
    -v /etc/cert:/etc/cert \
    -e QQ="${QQ}" \
    -e DOMAIN="${DOMAIN}" \
    -e HOSTNAME="${HOSTNAME}" \
    -e WEBPORT="${WEBPORT}" \
    -e PASSWD="${PASSWD}" \
    lousd996/manage-ui

success "容器已启动"

# ---- 验证 ----
sleep 2
if docker ps --format '{{.Names}}' | grep -q "^x-ui$"; then
    success "X-UI 容器运行中"
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  部署完成!${NC}"
    echo -e "${GREEN}  管理面板: https://${DOMAIN}:${WEBPORT}${NC}"
    echo -e "${GREEN}  密码:     ${PASSWD}${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
else
    error "容器启动失败，请检查日志: docker logs x-ui"
    exit 1
fi

# ---- 容器状态 ----
echo ""
docker ps -a --filter name=x-ui --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}"
echo ""

info "如需查看实时日志: docker logs -f x-ui"
info "如需重启容器:     docker restart x-ui"
info "如需停止容器:     docker stop x-ui"
