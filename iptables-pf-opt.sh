cat << 'EOF' > iptables-pf-opt.sh
#!/usr/bin/env bash
# 极致优化版 Linux 端口转发管理 (终极版)

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

optimize_system() {
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-iptables-forward.conf
    echo "net.netfilter.nf_conntrack_max = 1048576" >> /etc/sysctl.d/99-iptables-forward.conf
    echo "net.netfilter.nf_conntrack_tcp_timeout_established = 1200" >> /etc/sysctl.d/99-iptables-forward.conf
    sysctl -p /etc/sysctl.d/99-iptables-forward.conf >/dev/null 2>&1
    
    if [ -f /etc/debian_version ]; then
        dpkg -l | grep -qw iptables-persistent || apt-get install -y iptables-persistent netfilter-persistent
    elif [ -f /etc/redhat-release ]; then
        rpm -qa | grep -qw iptables-services || yum install -y iptables-services
        systemctl enable iptables >/dev/null 2>&1
    fi
}

save_rules() {
    if [ -f /etc/debian_version ]; then
        netfilter-persistent save >/dev/null 2>&1
    elif [ -f /etc/redhat-release ]; then
        service iptables save >/dev/null 2>&1
    fi
    echo -e "[\033[32mOK\033[0m] 规则已持久化。"
}

add_rule() {
    local lport=$1
    local rip=$2
    local rport=$3

    if ! iptables -t nat -C PREROUTING -p tcp --dport "$lport" -j DNAT --to-destination "$rip:$rport" 2>/dev/null; then
        iptables -t nat -A PREROUTING -p tcp --dport "$lport" -j DNAT --to-destination "$rip:$rport"
        iptables -t nat -A PREROUTING -p udp --dport "$lport" -j DNAT --to-destination "$rip:$rport"
    fi

    if ! iptables -t nat -C POSTROUTING -p tcp -d "$rip" --dport "$rport" -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -p tcp -d "$rip" --dport "$rport" -j MASQUERADE
        iptables -t nat -A POSTROUTING -p udp -d "$rip" --dport "$rport" -j MASQUERADE
    fi
    
    if ! iptables -C FORWARD -p tcp -d "$rip" --dport "$rport" -j ACCEPT 2>/dev/null; then
        iptables -A FORWARD -p tcp -d "$rip" --dport "$rport" -j ACCEPT
        iptables -A FORWARD -p udp -d "$rip" --dport "$rport" -j ACCEPT
    fi
}

install_shortcut() {
    local target="/usr/local/bin/i"
    cp -f "$0" "$target"
    # 核心机制：在生成快捷命令时，强制清洗可能残留的 Windows 换行符
    sed -i 's/\r$//' "$target"
    chmod +x "$target"
    echo -e "[\033[32mSuccess\033[0m] 快捷命令安装完成！"
    echo -e "以后在任何目录下，直接输入 \033[33mi\033[0m 并回车，即可启动本脚本。"
}

clear
echo -e "================================================="
echo -e " 优化版 iptables 端口转发管理"
echo -e "================================================="
echo -e " 1. 添加 端口转发"
echo -e " 2. 查看 现有规则 (NAT表)"
echo -e " 3. 清空 所有转发规则"
echo -e " 4. 安装 快捷命令 (输入 i 即可启动)"
echo -e "================================================="
read -p "请输入数字 (1-4): " num

case "$num" in
    1)
        optimize_system
        read -p "请输入本机监听端口 (如 8080): " local_port
        read -p "请输入远程目标 IP: " remote_ip
        read -p "请输入远程目标端口: " remote_port
        
        if [[ ! "$local_port" =~ ^[0-9]+$ || ! "$remote_port" =~ ^[0-9]+$ || -z "$remote_ip" ]]; then
            echo -e "[\033[31mError\033[0m] 参数格式错误！"
            exit 1
        fi
        
        add_rule "$local_port" "$remote_ip" "$remote_port"
        save_rules
        echo -e "[\033[32mSuccess\033[0m] 转发建立：本机 :$local_port -> 目标 $remote_ip:$remote_port"
        ;;
    2)
        echo -e "\n入站规则 (PREROUTING):"
        iptables -t nat -nL PREROUTING --line-numbers
        echo -e "\n出站规则 (POSTROUTING):"
        iptables -t nat -nL POSTROUTING --line-numbers
        ;;
    3)
        iptables -t nat -F PREROUTING
        iptables -t nat -F POSTROUTING
        iptables -F FORWARD
        save_rules
        echo -e "[\033[32mOK\033[0m] 规则已清空。"
        ;;
    4)
        install_shortcut
        ;;
    *)
        echo "输入错误。"
        exit 1
        ;;
esac
EOF