#!/bin/sh
# ==============================================================================
# LuCI Theme GL.iNet 一键生成 .ipk 打包脚本 (无需 OpenWrt SDK)
# 兼容环境: Debian / Ubuntu / OpenWrt 路由器终端 (BusyBox)
# ==============================================================================

set -e

PKG_NAME="luci-theme-glinet"
PKG_VERSION="1.3-1"
PKG_ARCH="all"
IPK_FILE="${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.ipk"

WORK_DIR="/tmp/ipk_build_$$"
DATA_DIR="${WORK_DIR}/data"
CTRL_DIR="${WORK_DIR}/control"

echo "==> [1/5] 初始化打包工作目录: ${WORK_DIR}"
rm -rf "${WORK_DIR}"
mkdir -p "${DATA_DIR}/www/luci-static/glinet"
mkdir -p "${DATA_DIR}/usr/lib/lua/luci/view/themes/glinet"
mkdir -p "${DATA_DIR}/etc/uci-defaults"
mkdir -p "${CTRL_DIR}"

echo "==> [2/5] 收集主题核心文件..."
# 如果在路由器上直接运行，自动从系统目录提取你刚改好的文件；
# 如果在 Debian 服务器运行，请将文件放在当前目录的 ./glinet_src 下
if [ -f "/www/luci-static/glinet/cascade.css" ]; then
    cp -r /www/luci-static/glinet/* "${DATA_DIR}/www/luci-static/glinet/"
    cp -r /usr/lib/lua/luci/view/themes/glinet/* "${DATA_DIR}/usr/lib/lua/luci/view/themes/glinet/"
elif [ -d "./glinet_src" ]; then
    cp -r ./glinet_src/htdocs/luci-static/glinet/* "${DATA_DIR}/www/luci-static/glinet/"
    cp -r ./glinet_src/luasrc/view/themes/glinet/* "${DATA_DIR}/usr/lib/lua/luci/view/themes/glinet/"
else
    echo "❌ 错误: 未找到主题源文件！请在已部署该主题的路由器上运行，或将源文件放入 ./glinet_src 目录。"
    exit 1
fi

echo "==> [3/5] 生成 uci-defaults 自动注册脚本..."
cat << 'EOF' > "${DATA_DIR}/etc/uci-defaults/30_luci-theme-glinet"
#!/bin/sh
uci batch <<-EOT
    set luci.themes.GLiNet='/luci-static/glinet'
    set luci.main.mediaurlbase='/luci-static/glinet'
    commit luci
EOT
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache*
exit 0
EOF
chmod 0755 "${DATA_DIR}/etc/uci-defaults/30_luci-theme-glinet"

echo "==> [4/5] 生成 OPKG 控制信息 (control & postinst & prerm)..."
# 计算安装大小 (KB)
INSTALLED_SIZE=$(du -sk "${DATA_DIR}" | awk '{print $1}')

cat << EOF > "${CTRL_DIR}/control"
Package: ${PKG_NAME}
Version: ${PKG_VERSION}
Depends: libc, luci-base
Section: luci
Architecture: ${PKG_ARCH}
Installed-Size: ${INSTALLED_SIZE}
Maintainer: Custom GL.iNet UI
Description: GL.iNet Admin v4.x Style Theme for OpenWrt/LEDE/QWRT (with Dark Mode & Toggle Switch)
EOF

# 安装后自动触发脚本（让 opkg install 后立即激活主题并清缓存）
cat << 'EOF' > "${CTRL_DIR}/postinst"
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
    ( . /etc/uci-defaults/30_luci-theme-glinet ) && rm -f /etc/uci-defaults/30_luci-theme-glinet
    /etc/init.d/uhttpd restart >/dev/null 2>&1
    exit 0
}
EOF
chmod 0755 "${CTRL_DIR}/postinst"

# 卸载前恢复默认主题脚本（防止卸载主题后 LuCI 报错进不去后台）
cat << 'EOF' > "${CTRL_DIR}/prerm"
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
    uci delete luci.themes.GLiNet 2>/dev/null
    if [ "$(uci get luci.main.mediaurlbase 2>/dev/null)" = "/luci-static/glinet" ]; then
        uci set luci.main.mediaurlbase='/luci-static/bootstrap'
    fi
    uci commit luci
    rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache*
}
EOF
chmod 0755 "${CTRL_DIR}/prerm"

echo "==> [5/5] 封装标准 OpenWrt .ipk 归档..."
echo "2.0" > "${WORK_DIR}/debian-binary"

# 兼容 GNU tar 与 BusyBox tar 的打包参数
TAR_OPTS="--numeric-owner --owner=0 --group=0"
tar --help 2>&1 | grep -q "numeric-owner" || TAR_OPTS=""

(cd "${CTRL_DIR}" && tar ${TAR_OPTS} -czf "${WORK_DIR}/control.tar.gz" ./*)
(cd "${DATA_DIR}" && tar ${TAR_OPTS} -czf "${WORK_DIR}/data.tar.gz" ./*)

OUT_DIR="$(pwd)"
(cd "${WORK_DIR}" && tar ${TAR_OPTS} -czf "${OUT_DIR}/${IPK_FILE}" ./debian-binary ./control.tar.gz ./data.tar.gz)

rm -rf "${WORK_DIR}"
echo "✅ 打包完成！输出文件: ${OUT_DIR}/${IPK_FILE}"