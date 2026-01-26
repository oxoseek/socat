#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 定义路径
REALM_BIN="/usr/local/bin/realm"
CONFIG_FILE="/root/realm.toml"
SYSTEMD_FILE="/etc/systemd/system/realm.service"
OPENRC_FILE="/etc/init.d/realm"
SHORTCUT_PATH="/usr/bin/realm-helper"
UPDATE_URL="https://raw.githubusercontent.com/RomanovCaesar/realm-helper/main/realm_helper.sh"

# 检查是否为 root 用户
[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}" && exit 1

# 检测系统类型
if [ -f /etc/alpine-release ]; then
    IS_ALPINE=1
    SYS_TYPE="Alpine (OpenRC)"
else
    IS_ALPINE=0
    SYS_TYPE="Debian/Ubuntu (Systemd)"
fi

# 检查系统依赖
check_dependencies() {
    if [ "$IS_ALPINE" -eq 0 ]; then
        # Debian/Ubuntu
        # 增加检查 nano
        if ! command -v curl &> /dev/null || ! command -v tar &> /dev/null || ! command -v nano &> /dev/null; then
            apt-get update && apt-get install -y curl tar nano
        fi
    else
        # Alpine
        if ! command -v curl &> /dev/null; then
            apk add curl
        fi
        if ! command -v tar &> /dev/null; then
            apk add tar
        fi
        if ! command -v nano &> /dev/null; then
            apk add nano
        fi
    fi
}

# 检查并安装快捷方式
check_shortcut() {
    if [ ! -f "$SHORTCUT_PATH" ] || [[ "$(realpath "$0")" != "$(realpath "$SHORTCUT_PATH")" ]]; then
        cp "$0" "$SHORTCUT_PATH"
        chmod +x "$SHORTCUT_PATH"
    fi
}

# 获取系统架构和类型
get_arch_os() {
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        REALM_ARCH="x86_64"
    elif [[ "$ARCH" == "aarch64" ]]; then
        REALM_ARCH="aarch64"
    else
        echo -e "${RED}不支持的架构: $ARCH${PLAIN}"
        exit 1
    fi

    if [ "$IS_ALPINE" -eq 1 ]; then
        REALM_OS="unknown-linux-musl"
    else
        REALM_OS="unknown-linux-gnu"
    fi
}

# 获取 Realm 状态
get_status() {
    # 1. 安装状态
    if [ -f "$REALM_BIN" ]; then
        local ver=$($REALM_BIN --version | awk '{print $2}')
        INSTALL_STATUS="${GREEN}已安装 (版本: $ver)${PLAIN}"
    else
        INSTALL_STATUS="${RED}未安装${PLAIN}"
    fi

    # 2. 运行状态
    RUN_STATUS="${RED}未运行${PLAIN}"
    
    if [ "$IS_ALPINE" -eq 1 ]; then
        # OpenRC 检测
        if [ -f "$OPENRC_FILE" ]; then
            if rc-service realm status 2>/dev/null | grep -q "started"; then
                RUN_STATUS="${GREEN}运行中${PLAIN}"
            fi
        fi
    else
        # Systemd 检测
        if command -v systemctl &> /dev/null; then
            if systemctl is-active --quiet realm; then
                RUN_STATUS="${GREEN}运行中${PLAIN}"
            fi
        fi
    fi
}

# 任意键返回
wait_for_key() {
    echo ""
    echo -e "${YELLOW}按下任意键返回主菜单...${PLAIN}"
    read -n 1 -s -r
    main_menu
}

# 安装或更新 Realm
install_realm() {
    get_arch_os
    
    echo -e "${GREEN}正在获取 GitHub 最新版本信息...${PLAIN}"
    LATEST_TAG=$(curl -s "https://api.github.com/repos/zhboner/realm/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [[ -z "$LATEST_TAG" ]]; then
        echo -e "${RED}获取版本信息失败，请检查网络连接。${PLAIN}"
        wait_for_key
        return
    fi

    echo -e "最新版本为: ${GREEN}$LATEST_TAG${PLAIN}"

    if [ -f "$REALM_BIN" ]; then
        CURRENT_VER=$($REALM_BIN --version | awk '{print $2}')
        TAG_NUM=$(echo $LATEST_TAG | sed 's/^v//')
        CUR_NUM=$(echo $CURRENT_VER | sed 's/^v//')
        
        if [[ "$TAG_NUM" == "$CUR_NUM" ]]; then
            echo -e "${YELLOW}当前已是最新版本，无需更新。${PLAIN}"
            wait_for_key
            return
        else
            echo -e "${YELLOW}发现新版本 (当前: $CURRENT_VER, 最新: $LATEST_TAG)${PLAIN}"
            read -p "是否更新？[y/n]: " choice
            if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
                wait_for_key
                return
            fi
        fi
    fi

    DOWNLOAD_URL="https://github.com/zhboner/realm/releases/download/${LATEST_TAG}/realm-${REALM_ARCH}-${REALM_OS}.tar.gz"
    
    rm -f /tmp/realm.tar.gz
    rm -f /tmp/realm

    echo -e "${GREEN}正在下载: realm-${REALM_ARCH}-${REALM_OS}.tar.gz ...${PLAIN}"
    curl -L -o /tmp/realm.tar.gz "$DOWNLOAD_URL"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}下载失败！${PLAIN}"
        wait_for_key
        return
    fi

    echo -e "${GREEN}正在安装...${PLAIN}"
    tar -xzvf /tmp/realm.tar.gz -C /tmp
    
    if [ ! -f "/tmp/realm" ]; then
        echo -e "${RED}解压失败或文件不存在！请检查下载文件是否完整。${PLAIN}"
        wait_for_key
        return
    fi

    mv /tmp/realm "$REALM_BIN"
    chmod +x "$REALM_BIN"
    rm -f /tmp/realm.tar.gz

    echo -e "${GREEN}Realm 安装/更新成功！${PLAIN}"
    wait_for_key
}

# 初始化配置文件
init_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" <<EOF
[log]
level = "warn"

[dns]
# ipv4_then_ipv6, ipv6_then_ipv4, ipv4_only, ipv6_only
# mode = "ipv6_then_ipv4"

[network]
no_tcp = false
use_udp = true
EOF
    fi
}

# 添加转发规则
add_rule() {
    init_config
    echo -e "${YELLOW}=== 添加转发规则 ===${PLAIN}"
    
    read -p "请输入监听 IP (默认 0.0.0.0): " listen_ip
    [[ -z "$listen_ip" ]] && listen_ip="0.0.0.0"

    read -p "请输入监听端口 (必填): " listen_port
    if [[ -z "$listen_port" ]]; then
        echo -e "${RED}错误：监听端口不能为空，退出操作。${PLAIN}"
        wait_for_key
        return
    fi

    if grep -q "listen = \"$listen_ip:$listen_port\"" "$CONFIG_FILE" || grep -q "listen = \".*:$listen_port\"" "$CONFIG_FILE"; then
        echo -e "${RED}错误：该端口已在配置文件中存在，退出脚本。${PLAIN}"
        exit 1
    fi

    read -p "请输入转发目标 IP (必填): " remote_ip
    if [[ -z "$remote_ip" ]]; then
        echo -e "${RED}错误：目标 IP 不能为空，退出脚本。${PLAIN}"
        exit 1
    fi

    read -p "请输入转发目标端口 (必填): " remote_port
    if [[ -z "$remote_port" ]]; then
        echo -e "${RED}错误：目标端口 不能为空，退出脚本。${PLAIN}"
        exit 1
    fi

    cat >> "$CONFIG_FILE" <<EOF

[[endpoints]]
listen = "$listen_ip:$listen_port"
remote = "$remote_ip:$remote_port"
EOF

    echo -e "${GREEN}规则添加成功！${PLAIN}"
    echo -e "已添加: $listen_ip:$listen_port -> $remote_ip:$remote_port"
    echo -e "${YELLOW}注意：请重启 Realm (选项 9) 使配置生效。${PLAIN}"
    wait_for_key
}

# 查看现有规则
view_rules() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}配置文件不存在。${PLAIN}"
        wait_for_key
        return
    fi

    echo -e "${YELLOW}=== 现有转发规则 ===${PLAIN}"
    echo -e "格式: 监听地址 -> 目标地址"
    echo "--------------------------------"
    awk '/\[\[endpoints\]\]/{flag=1; next} flag && /listen/{l=$3} flag && /remote/{r=$3; print l " -> " r; flag=0}' "$CONFIG_FILE" | tr -d '"'
    echo "--------------------------------"
    wait_for_key
}

# 修改现有转发规则
edit_rule() {
    init_config
    echo -e "${GREEN}正在打开配置文件...${PLAIN}"
    echo -e "${YELLOW}提示：修改完成后，按 Ctrl+O 保存，Enter 确认，然后按 Ctrl+X 退出。${PLAIN}"
    sleep 2
    nano "$CONFIG_FILE"
    echo -e "${GREEN}修改完成。${PLAIN}"
    echo -e "${YELLOW}注意：请重启 Realm (选项 9) 使配置生效。${PLAIN}"
    wait_for_key
}

# 服务管理统一入口
manage_service() {
    action=$1
    
    if [ "$IS_ALPINE" -eq 1 ]; then
        # Alpine (OpenRC) 逻辑
        case "$action" in
            enable)
                if [ ! -f "$OPENRC_FILE" ]; then
                    cat > "$OPENRC_FILE" <<EOF
#!/sbin/openrc-run
name="realm"
description="Realm Network Relay"
command="$REALM_BIN"
command_args="-c $CONFIG_FILE"
command_background=true
pidfile="/run/realm.pid"

depend() {
    need net
    use dns logger
}
EOF
                    chmod +x "$OPENRC_FILE"
                fi
                rc-update add realm default
                echo -e "${GREEN}已设置开机自启 (OpenRC)。${PLAIN}"
                ;;
            disable)
                rc-update del realm default
                echo -e "${GREEN}已取消开机自启 (OpenRC)。${PLAIN}"
                ;;
            start)
                if rc-service realm status 2>/dev/null | grep -q "started"; then
                    echo -e "${YELLOW}Realm 已经在运行中，跳过启动。${PLAIN}"
                else
                    rc-service realm start
                    echo -e "${GREEN}Realm 已启动。${PLAIN}"
                fi
                ;;
            stop)
                if ! rc-service realm status 2>/dev/null | grep -q "started"; then
                    echo -e "${YELLOW}Realm 已经停止，跳过停止。${PLAIN}"
                else
                    rc-service realm stop
                    echo -e "${GREEN}Realm 已停止。${PLAIN}"
                fi
                ;;
            restart)
                rc-service realm restart
                echo -e "${GREEN}Realm 已重启。${PLAIN}"
                ;;
        esac
    else
        # Debian/Ubuntu (Systemd) 逻辑
        case "$action" in
            enable)
                if [ ! -f "$SYSTEMD_FILE" ]; then
                    cat > "$SYSTEMD_FILE" <<EOF
[Unit]
Description=realm
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$REALM_BIN -c $CONFIG_FILE
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
                    systemctl daemon-reload
                fi
                systemctl enable realm
                echo -e "${GREEN}已设置开机自启 (Systemd)。${PLAIN}"
                ;;
            disable)
                systemctl disable realm
                echo -e "${GREEN}已取消开机自启 (Systemd)。${PLAIN}"
                ;;
            start)
                if systemctl is-active --quiet realm; then
                    echo -e "${YELLOW}Realm 已经在运行中，跳过启动。${PLAIN}"
                else
                    systemctl start realm
                    echo -e "${GREEN}Realm 已启动。${PLAIN}"
                fi
                ;;
            stop)
                if ! systemctl is-active --quiet realm; then
                    echo -e "${YELLOW}Realm 已经停止，跳过停止。${PLAIN}"
                else
                    systemctl stop realm
                    echo -e "${GREEN}Realm 已停止。${PLAIN}"
                fi
                ;;
            restart)
                systemctl restart realm
                echo -e "${GREEN}Realm 已重启。${PLAIN}"
                ;;
        esac
    fi
    wait_for_key
}

# 卸载 Realm
uninstall_realm() {
    read -p "确定要卸载 Realm 吗？这会删除程序和服务配置 [y/n]: " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        if [ "$IS_ALPINE" -eq 1 ]; then
            rc-service realm stop 2>/dev/null
            rc-update del realm default 2>/dev/null
            rm -f "$OPENRC_FILE"
        else
            systemctl stop realm 2>/dev/null
            systemctl disable realm 2>/dev/null
            rm -f "$SYSTEMD_FILE"
            systemctl daemon-reload
        fi
        
        rm -f "$REALM_BIN"
        rm -f "$SHORTCUT_PATH"
        
        echo -e "${GREEN}Realm 程序及服务已卸载。${PLAIN}"
        read -p "是否保留配置文件 ($CONFIG_FILE)? [y/n]: " keep_conf
        if [[ "$keep_conf" != "y" && "$keep_conf" != "Y" ]]; then
            rm -f "$CONFIG_FILE"
            echo -e "${GREEN}配置文件已删除。${PLAIN}"
        else
            echo -e "${YELLOW}配置文件已保留。${PLAIN}"
        fi
    else
        echo -e "${YELLOW}取消卸载。${PLAIN}"
    fi
    wait_for_key
}

# 更新脚本
update_script() {
    echo -e "${GREEN}正在检查脚本更新...${PLAIN}"
    curl -L -o /tmp/realm_helper_new.sh "$UPDATE_URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}更新失败，无法连接到 GitHub。${PLAIN}"
        wait_for_key
        return
    fi

    if ! grep -q "#!/bin/bash" /tmp/realm_helper_new.sh; then
        echo -e "${RED}下载的文件无效，请检查 URL 或网络。${PLAIN}"
        rm -f /tmp/realm_helper_new.sh
        wait_for_key
        return
    fi

    mv /tmp/realm_helper_new.sh "$0"
    chmod +x "$0"
    
    if [[ "$(realpath "$0")" != "$(realpath "$SHORTCUT_PATH")" ]]; then
        cp "$0" "$SHORTCUT_PATH"
        chmod +x "$SHORTCUT_PATH"
    fi

    echo -e "${GREEN}脚本更新成功！正在重启脚本...${PLAIN}"
    sleep 2
    exec "$0"
}

# 主菜单
main_menu() {
    clear
    get_status
    echo -e "################################################"
    echo -e "#              Realm 管理脚本                  #"
    echo -e "#            系统: ${SYS_TYPE}        #"
    echo -e "################################################"
    echo -e "Realm 安装状态: ${INSTALL_STATUS}"
    echo -e "Realm 运行状态: ${RUN_STATUS}"
    echo -e "提示: 输入 realm-helper 可快速启动本脚本"
    echo -e "################################################"
    echo -e " 1. 下载并安装 / 更新 Realm"
    echo -e " 2. 添加转发规则"
    echo -e " 3. 查看现有转发规则"
    echo -e " 4. 修改现有转发规则 (nano)"
    echo -e "------------------------------------------------"
    echo -e " 5. 设置开机自启 (enable)"
    echo -e " 6. 取消开机自启 (disable)"
    echo -e " 7. 启动服务 (start)"
    echo -e " 8. 停止服务 (stop)"
    echo -e " 9. 重启服务 (restart)"
    echo -e "------------------------------------------------"
    echo -e " 10. 卸载 Realm"
    echo -e " 99. 更新本脚本"
    echo -e " 0. 退出脚本"
    echo -e "################################################"
    read -p "请输入数字: " num

    case "$num" in
        1) install_realm ;;
        2) add_rule ;;
        3) view_rules ;;
        4) edit_rule ;;
        5) manage_service enable ;;
        6) manage_service disable ;;
        7) manage_service start ;;
        8) manage_service stop ;;
        9) manage_service restart ;;
        10) uninstall_realm ;;
        99) update_script ;;
        0) echo -e "${GREEN}谢谢使用本脚本，再见。${PLAIN}"; exit 0 ;;
        *) echo -e "${RED}请输入正确的数字！${PLAIN}"; sleep 1; main_menu ;;
    esac
}

# 脚本入口
check_dependencies
check_shortcut
main_menu
