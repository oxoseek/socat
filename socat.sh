#!/bin/bash
#
# socat/ssh port forward manager with menu
# Requirements: socat, tmux, dialog (or fzf)
#

CONFIG="$HOME/.socat_manager.conf"
SESSION_PREFIX="support_"

# 确保依赖存在
for cmd in socat tmux ssh dialog; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd not found in PATH" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "$CONFIG")"
touch "$CONFIG"

# ---------------- Functions ----------------

list_forwards() {
  echo "当前转发列表："
  cat "$CONFIG" | nl
}

add_forward() {
  dialog --inputbox "请输入 SSH 目标 (例如 user@host):" 8 40 2> /tmp/ssh_target.$$
  SSH_TARGET=$(< /tmp/ssh_target.$$)
  rm -f /tmp/ssh_target.$$

  dialog --inputbox "请输入转发端口号 (默认6000):" 8 40 "6000" 2> /tmp/port.$$
  PORT=$(< /tmp/port.$$)
  rm -f /tmp/port.$$

  SESSION="${SESSION_PREFIX}${PORT}"

  echo "$SSH_TARGET $PORT" >> "$CONFIG"

  ssh -R "${PORT}:localhost:${PORT}" -N "$SSH_TARGET" &
  PID_SSH=$!

  tmux new-session -d -s "$SESSION"
  TTY1=$(tty)
  read rows cols < <(stty size)

  CMD=$(cat <<EOF
stty rows $rows cols $cols
TTY2=\$(tty)
while sleep 1; do
  read r c < <(stty -F "$TTY1" size)
  stty -F "\$TTY2" rows "\$r" cols "\$c"
  kill -WINCH \$$
done
EOF
)

  socat system:"$CMD & tmux attach -t $SESSION",pty,raw,echo=0,stderr,setsid,sigint,sane \
        tcp-listen:"$PORT",bind=localhost,reuseaddr &
  
  dialog --msgbox "转发已建立：$SSH_TARGET:$PORT\nSession: $SESSION" 10 50
}

remove_forward() {
  # 从配置中选择一条删除
  if [ ! -s "$CONFIG" ]; then
    dialog --msgbox "没有可删除的转发。" 6 40
    return
  fi

  CHOICE=$(cat "$CONFIG" | nl | dialog --menu "选择要删除的转发：" 15 50 10 \
    $(nl "$CONFIG" | awk '{print $1 " " $2"_"$3}') 2>&1 >/dev/tty)

  [ -z "$CHOICE" ] && return

  LINE=$(sed -n "${CHOICE}p" "$CONFIG")
  SSH_TARGET=$(echo "$LINE" | awk '{print $1}')
  PORT=$(echo "$LINE" | awk '{print $2}')
  SESSION="${SESSION_PREFIX}${PORT}"

  # kill tmux + socat + ssh
  tmux kill-session -t "$SESSION" 2>/dev/null
  pkill -f "ssh -R ${PORT}:localhost:${PORT} -N $SSH_TARGET"
  pkill -f "socat.*tcp-listen:${PORT}"

  sed -i "${CHOICE}d" "$CONFIG"
  dialog --msgbox "已删除转发：$SSH_TARGET $PORT" 8 40
}

# ---------------- Main Menu ----------------
while true; do
  CHOICE=$(dialog --menu "=== SSH Socat Manager ===" 15 50 6 \
    1 "查看所有转发" \
    2 "新增转发" \
    3 "删除转发" \
    4 "退出" 2>&1 >/dev/tty)

  case "$CHOICE" in
    1) list_forwards | dialog --textbox /dev/stdin 20 60 ;;
    2) add_forward ;;
    3) remove_forward ;;
    4) clear; exit 0 ;;
  esac
done
