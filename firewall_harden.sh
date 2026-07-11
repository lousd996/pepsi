#!/bin/bash
#
# Linux 防火墙加固脚本
# 仅放通 58086 端口，其余全部关闭
# 适用于 CentOS 7/8、Ubuntu 18.04+、Debian 10+
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    error "请以 root 身份运行 (sudo bash firewall_harden.sh)"
    exit 1
fi

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}    Linux 防火墙加固脚本${NC}"
echo -e "${CYAN}    仅放通 58086 端口${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# ========================================
# 检测系统
# ========================================
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        OS=$(uname -s)
    fi
    echo "  系统: $OS $VERSION"
    
    if command -v firewalld &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        FW="firewalld"
    elif command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        FW="ufw"
    elif command -v iptables &>/dev/null; then
        FW="iptables"
    else
        FW="none"
    fi
    echo "  防火墙: $FW"
}

detect_os

# ========================================
# 交互式配置
# ========================================
echo ""
echo -e "${YELLOW}========== 端口配置 ==========${NC}"

read -p "$(echo -e ${CYAN})放通端口${NC} (默认: 58086): " INPUT_PORT
PORT="${INPUT_PORT:-58086}"

read -p "$(echo -e ${CYAN})SSH 端口（用于远程连接，不填则默认关闭）${NC}: " INPUT_SSH
SSH_PORT="${INPUT_SSH}"

echo ""
info "端户口配置:"
echo "  放通端口: $PORT"
if [ -n "$SSH_PORT" ]; then
    echo "  SSH 端口: $SSH_PORT（额外放通）"
else
    echo "  SSH 端口: 不额外放通（请确保操作时已通过 $PORT 连接）"
fi

# ========================================
# 询问是否禁 ping
# ========================================
read -p "$(echo -e ${YELLOW})是否禁 ping？(y/n, 默认 n): ${NC}" DISABLE_PING
DISABLE_PING=${DISABLE_PING:-n}

# ========================================
# firewalld 方案
# ========================================
apply_firewalld() {
    info "使用 firewalld 配置规则..."
    
    if ! command -v firewalld &>/dev/null; then
        info "安装 firewalld..."
        if [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "fedora" ]]; then
            yum install -y firewalld
        elif [[ "$OS" == "rocky" ]] || [[ "$OS" == "almalinux" ]]; then
            dnf install -y firewalld
        fi
    fi
    
    systemctl start firewalld
    systemctl enable firewalld
    
    # 清除所有现有规则
    info "清除现有规则..."
    firewall-cmd --zone=public --list-ports 2>/dev/null | tr ' ' '\n' | while read p; do
        [ -n "$p" ] && firewall-cmd --zone=public --remove-port="$p" --permanent 2>/dev/null || true
    done
    firewall-cmd --zone=public --list-rich-rules 2>/dev/null | while read r; do
        [ -n "$r" ] && firewall-cmd --zone=public --remove-rich-rule="$r" --permanent 2>/dev/null || true
    done
    firewall-cmd --zone=public --list-services 2>/dev/null | tr ' ' '\n' | while read s; do
        [ -n "$s" ] && firewall-cmd --zone=public --remove-service="$s" --permanent 2>/dev/null || true
    done
    
    # 放通已建立连接（否则当前连接会断）
    firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" ctstate related,established accept'
    firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv6" ctstate related,established accept'
    
    # 放通指定端口
    firewall-cmd --permanent --zone=public --add-port=${PORT}/tcp
    
    # 额外放通 SSH 端口
    if [ -n "$SSH_PORT" ]; then
        firewall-cmd --permanent --zone=public --add-port=${SSH_PORT}/tcp
    fi
    
    # 禁 ping
    if [[ "$DISABLE_PING" == "y" || "$DISABLE_PING" == "Y" ]]; then
        firewall-cmd --permanent --zone=public --add-rich-rule='rule protocol value="icmp" reject'
        info "已禁 ping"
    fi
    
    # 应用规则
    firewall-cmd --reload
    
    # 默认拒绝所有入站（确保最后执行）
    firewall-cmd --permanent --zone=public --set-target=DROP
    firewall-cmd --reload
    
    # 保存
    firewall-cmd --runtime-to-permanent 2>/dev/null || true
    
    success "firewalld 规则已应用"
    echo ""
    firewall-cmd --zone=public --list-all
}

# ========================================
# ufw 方案
# ========================================
apply_ufw() {
    info "使用 ufw 配置规则..."
    
    if ! command -v ufw &>/dev/null; then
        info "安装 ufw..."
        apt update -y
        apt install -y ufw
    fi
    
    ufw --force reset
    
    ufw default deny incoming
    ufw default allow outgoing
    
    # 放通已建立连接
    ufw allow out on $(ip route get 8.8.8.8 | awk '{print $5; exit}') 2>/dev/null || true
    
    # 放通指定端口
    ufw allow $PORT/tcp comment 'Application Port'
    
    # 额外放通 SSH
    if [ -n "$SSH_PORT" ]; then
        ufw allow $SSH_PORT/tcp comment 'SSH'
        ufw limit $SSH_PORT/tcp comment 'SSH rate limit'
    fi
    
    # 禁 ping
    if [[ "$DISABLE_PING" == "y" || "$DISABLE_PING" == "Y" ]]; then
        sed -i '/ufw-before-input.*icmp/s/ACCEPT/DROP/' /etc/ufw/before.rules 2>/dev/null || true
    fi
    
    ufw --force enable
    systemctl enable ufw
    
    success "ufw 规则已应用"
    echo ""
    ufw status numbered
}

# ========================================
# iptables 方案
# ========================================
apply_iptables() {
    info "使用 iptables 配置规则..."
    
    if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
        apt install -y iptables-persistent 2>/dev/null || true
    fi
    
    # 清空
    iptables -F
    iptables -X
    iptables -Z
    iptables -t nat -F
    iptables -t mangle -F
    
    # 默认拒绝所有入站
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    
    # loopback
    iptables -A INPUT -i lo -j ACCEPT
    
    # 已建立连接
    iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    
    # 放通指定端口
    iptables -A INPUT -p tcp --dport $PORT -j ACCEPT
    
    # 额外放通 SSH
    if [ -n "$SSH_PORT" ]; then
        iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
    fi
    
    # 禁 ping 或限速
    if [[ "$DISABLE_PING" == "y" || "$DISABLE_PING" == "Y" ]]; then
        iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
    else
        iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 2/second -j ACCEPT
        iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
    fi
    
    # 防扫描
    iptables -A INPUT -p tcp --syn -m limit --limit 100/s --limit-burst 200 -j ACCEPT
    iptables -A INPUT -p tcp --syn -j DROP
    iptables -A INPUT -f -j DROP
    iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
    iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
    
    # 保存
    if [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "rocky" ]] || [[ "$OS" == "almalinux" ]] || [[ "$OS" == "fedora" ]]; then
        iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
    elif [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
        mkdir -p /etc/iptables 2>/dev/null
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    
    success "iptables 规则已应用"
    echo ""
    iptables -L -n -v --line-numbers
}

# ========================================
# 内核加固
# ========================================
extra_hardening() {
    echo ""
    info "========== 内核参数加固 =========="
    
    cat > /etc/sysctl.d/99-firewall.conf <<'EOF'
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.tcp_timestamps = 0
EOF
    
    sysctl -p /etc/sysctl.d/99-firewall.conf 2>/dev/null
    success "内核参数已加固"
}

# ========================================
# 执行
# ========================================
echo ""
info "开始应用防火墙规则..."

case $FW in
    firewalld) apply_firewalld ;;
    ufw)       apply_ufw ;;
    iptables)  apply_iptables ;;
    none)
        warn "未检测到防火墙，尝试安装..."
        if [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "rocky" ]] || [[ "$OS" == "almalinux" ]] || [[ "$OS" == "fedora" ]]; then
            FW="firewalld"; apply_firewalld
        elif [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
            FW="ufw"; apply_ufw
        else
            FW="iptables"; apply_iptables
        fi
        ;;
esac

extra_hardening

# ========================================
# 完成
# ========================================
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  防火墙加固完成!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "放通端口:"
echo "  $PORT/tcp (应用端口)"
[ -n "$SSH_PORT" ] && echo "  $SSH_PORT/tcp (SSH)"
echo ""
echo "其余所有入站端口: 全部关闭"
echo ""
if [[ "$DISABLE_PING" == "y" || "$DISABLE_PING" == "Y" ]]; then
    echo "  ping: 已禁用"
else
    echo "  ping: 已限速 (2次/秒)"
fi
echo ""
warn "⚠ 请确认当前连接未断开！建议另外开一个终端窗口测试确认。"
echo ""
info "如需放通其他端口:"
case $FW in
    firewalld)
        echo "  firewall-cmd --permanent --zone=public --add-port=端口/tcp && firewall-cmd --reload"
        ;;
    ufw)
        echo "  ufw allow 端口/tcp && ufw reload"
        ;;
    iptables)
        echo "  iptables -A INPUT -p tcp --dport 端口 -j ACCEPT && 保存规则"
        ;;
esac
