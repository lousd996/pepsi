#!/bin/bash
#
# 批量开放端口脚本
# 支持 firewalld / ufw / iptables，自动识别
# 用法:
#   sudo bash open_ports.sh 80 443 8080
#   sudo bash open_ports.sh 8000-8100          (连续端口段)
#   sudo bash open_ports.sh --file ports.txt   (从文件读取)
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
    error "请以 root 身份运行 (sudo bash open_ports.sh ...)"
    exit 1
fi

# ========================================
# 检测防火墙
# ========================================
detect_fw() {
    if command -v firewalld &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        echo "firewalld"
    elif command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        echo "ufw"
    elif command -v iptables &>/dev/null; then
        echo "iptables"
    else
        echo "none"
    fi
}

FW=$(detect_fw)

# ========================================
# 解析端口参数
# ========================================
PORTS=()

# 从文件读取
if [[ "$1" == "--file" || "$1" == "-f" ]]; then
    if [ -z "$2" ]; then
        error "请指定端口文件路径"
        exit 1
    fi
    if [ ! -f "$2" ]; then
        error "文件不存在: $2"
        exit 1
    fi
    while IFS= read -r line; do
        line=$(echo "$line" | xargs)
        [ -z "$line" ] && continue
        [[ "$line" =~ ^# ]] && continue
        PORTS+=("$line")
    done < "$2"

# 无参数，交互式输入
elif [ $# -eq 0 ]; then
    echo ""
    echo -e "${YELLOW}========== 批量开放端口 ==========${NC}"
    echo "支持的格式: 80  443  8080   (单个端口，空格分隔)"
    echo "             8000-8100        (连续端口段)"
    echo "             8080/tcp         (指定协议)"
    echo "输入空行结束"
    echo ""
    while true; do
        read -p "$(echo -e ${CYAN})端口: ${NC}" port
        [ -z "$port" ] && break
        PORTS+=("$port")
    done
else
    PORTS=("$@")
fi

if [ ${#PORTS[@]} -eq 0 ]; then
    error "未指定任何端口"
    exit 1
fi

echo ""
info "待开放端口 (${#PORTS[@]} 个):"
for p in "${PORTS[@]}"; do
    echo "  - $p"
done

# ========================================
# 确认执行
# ========================================
echo ""
read -p "$(echo -e ${YELLOW})确认开放以上端口？(y/n, 默认 y): ${NC}" CONFIRM
CONFIRM=${CONFIRM:-y}
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    info "已取消"
    exit 0
fi

# ========================================
# 执行开放
# ========================================
echo ""
case $FW in
    firewalld)
        info "使用 firewalld 开放端口..."
        OPENED=0
        SKIPPED=0
        for p in "${PORTS[@]}"; do
            if [[ "$p" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                start=${BASH_REMATCH[1]}
                end=${BASH_REMATCH[2]}
                for i in $(seq $start $end); do
                    if firewall-cmd --zone=public --add-port=${i}/tcp --permanent 2>/dev/null; then
                        ((OPENED++))
                    else
                        ((SKIPPED++))
                    fi
                done
            elif [[ "$p" =~ ^([0-9]+)/(tcp|udp)$ ]]; then
                if firewall-cmd --zone=public --add-port=$p --permanent 2>/dev/null; then
                    ((OPENED++))
                else
                    ((SKIPPED++))
                fi
            else
                if firewall-cmd --zone=public --add-port=${p}/tcp --permanent 2>/dev/null; then
                    ((OPENED++))
                else
                    ((SKIPPED++))
                fi
            fi
        done
        firewall-cmd --reload
        firewall-cmd --runtime-to-permanent 2>/dev/null || true
        success "firewalld: 已开放 $OPENED 个端口"
        [ $SKIPPED -gt 0 ] && warn "跳过 $SKIPPED 个（可能已存在）"
        echo ""
        info "当前已放通端口:"
        firewall-cmd --zone=public --list-ports
        ;;

    ufw)
        info "使用 ufw 开放端口..."
        OPENED=0
        SKIPPED=0
        for p in "${PORTS[@]}"; do
            if [[ "$p" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                start=${BASH_REMATCH[1]}
                end=${BASH_REMATCH[2]}
                for i in $(seq $start $end); do
                    if ufw allow ${i}/tcp 2>/dev/null; then
                        ((OPENED++))
                    else
                        ((SKIPPED++))
                    fi
                done
            elif [[ "$p" =~ ^([0-9]+)/(tcp|udp)$ ]]; then
                if ufw allow $p 2>/dev/null; then
                    ((OPENED++))
                else
                    ((SKIPPED++))
                fi
            else
                if ufw allow ${p}/tcp 2>/dev/null; then
                    ((OPENED++))
                else
                    ((SKIPPED++))
                fi
            fi
        done
        ufw reload 2>/dev/null || true
        success "ufw: 已开放 $OPENED 个端口"
        [ $SKIPPED -gt 0 ] && warn "跳过 $SKIPPED 个"
        echo ""
        info "当前规则:"
        ufw status numbered
        ;;

    iptables)
        info "使用 iptables 开放端口..."
        OPENED=0
        SKIPPED=0
        for p in "${PORTS[@]}"; do
            if [[ "$p" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                start=${BASH_REMATCH[1]}
                end=${BASH_REMATCH[2]}
                if iptables -C INPUT -p tcp --dport ${start}:${end} -j ACCEPT 2>/dev/null; then
                    ((SKIPPED++))
                else
                    iptables -A INPUT -p tcp --dport ${start}:${end} -j ACCEPT
                    ((OPENED++))
                fi
            elif [[ "$p" =~ ^([0-9]+)/(tcp|udp)$ ]]; then
                proto=${BASH_REMATCH[2]}
                port=${BASH_REMATCH[1]}
                if iptables -C INPUT -p $proto --dport $port -j ACCEPT 2>/dev/null; then
                    ((SKIPPED++))
                else
                    iptables -A INPUT -p $proto --dport $port -j ACCEPT
                    ((OPENED++))
                fi
            else
                if iptables -C INPUT -p tcp --dport $p -j ACCEPT 2>/dev/null; then
                    ((SKIPPED++))
                else
                    iptables -A INPUT -p tcp --dport $p -j ACCEPT
                    ((OPENED++))
                fi
            fi
        done

        if [[ -d /etc/sysconfig ]]; then
            iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
        else
            mkdir -p /etc/iptables 2>/dev/null
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi

        success "iptables: 已开放 $OPENED 个端口"
        [ $SKIPPED -gt 0 ] && warn "跳过 $SKIPPED 个（规则已存在）"
        echo ""
        info "当前 INPUT 规则:"
        iptables -L INPUT -n -v --line-numbers | head -30
        ;;

    none)
        error "未检测到防火墙工具，请先安装:"
        echo "  CentOS: yum install -y firewalld"
        echo "  Ubuntu: apt install -y ufw"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  批量端口开放完成!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
info "快速使用示例:"
echo "  开放指定端口:    sudo bash open_ports.sh 80 443 8080"
echo "  开放端口段:      sudo bash open_ports.sh 10000-10100"
echo "  从文件读取:      sudo bash open_ports.sh -f ports.txt"
echo "  交互式输入:      sudo bash open_ports.sh"
echo ""
echo "支持的端口文件格式 (ports.txt):"
echo "  # 这是注释"
echo "  80"
echo "  443"
echo "  8080-8090"
echo "  53/udp"
