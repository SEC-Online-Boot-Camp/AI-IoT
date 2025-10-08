#!/usr/bin/env bash

set -euo pipefail

USER_NAME="${SUDO_USER:-$USER}"
VENV_DIR="./venv313"
LINKLOCAL_IFACE="eth0"

log()  { echo -e "\n\033[1;32m==>\033[0m $*\n"; }
warn() { echo -e "\n\033[1;33m[WARN]\033[0m $*\n"; }

log "OS/ユーザー確認"
CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-unknown}")"
echo " user=${USER_NAME}, codename=${CODENAME}"

log "APT 更新/アップグレード"
sudo apt update
sudo apt -y full-upgrade
sudo apt install -y git curl python3 python3-venv python3-pip
sudo apt install -y fcitx5 fcitx5-mozc im-config
sudo -u "${USER_NAME}" im-config -n fcitx5 || true
dpkg -l | grep -q '^ii\s\+python3-rpi-lgpio' && sudo apt -y remove python3-rpi-lgpio || true
sudo apt install -y python3-rpi.gpio python3-gpiozero
sudo apt install -y rpicam-apps python3-picamera2
command -v rpicam-hello >/dev/null 2>&1 && echo " rpicam: $(rpicam-hello --version || true)"
sudo apt install -y code || true
sudo apt install -y network-manager || true
sudo apt install -y wayvnc


log "eth0 を IPv4 Link-Local（NetworkManager）へ固定"
if systemctl is-active --quiet NetworkManager; then
  CON=$(sudo nmcli -t -f NAME,DEVICE con show | awk -F: -v dev="${LINKLOCAL_IFACE}" '$2==dev{print $1; exit}')
  if [[ -z "${CON}" ]]; then
    CON="${LINKLOCAL_IFACE}-linklocal"
    sudo nmcli con add type ethernet ifname "${LINKLOCAL_IFACE}" con-name "${CON}" ipv4.method link-local ipv6.method ignore
  else
    sudo nmcli con mod "${CON}" ipv4.method link-local ipv4.addresses "" ipv4.gateway "" ipv4.dns "" ipv4.never-default yes
    sudo nmcli con mod "${CON}" ipv6.method ignore
  fi
  sudo nmcli con down "${CON}" || true
  sudo nmcli con up   "${CON}" || true
  echo " 確認: $(ip -4 a show dev ${LINKLOCAL_IFACE} | grep -o '169\.254[^/ ]*' || echo '未割当')"
else
  warn "NetworkManager が未起動のためスキップ。"
fi


log "WayVNC を有効化＆起動"
sudo systemctl disable --now vncserver-x11-serviced 2>/dev/null || true
sudo systemctl enable --now wayvnc.service
sudo systemctl status wayvnc.service --no-pager || true


log "カメラの設定変更"
CFG="/boot/firmware/config.txt"
if [[ -f "$CFG" ]]; then
  TS="$(date +%Y%m%d%H%M%S)"
  sudo cp -a "$CFG" "${CFG}.bak-${TS}"
  sudo sed -i -E 's/^(\s*)camera_auto_detect\s*=\s*1(\s*)$/# \0 (disabled by setup)/' "$CFG"
  need_auto=1; need_overlay=1
  grep -Eq '^\s*camera_auto_detect\s*=\s*0\s*$' "$CFG" && need_auto=0
  grep -Eq '^\s*dtoverlay\s*=\s*imx219,cam0\s*$' "$CFG" && need_overlay=0
  if [[ $need_auto -eq 0 && $need_overlay -eq 0 ]]; then
    echo "  -> 既に目的の設定が入っています。変更なし。"
  else
    if grep -q '^\[all\]' "$CFG"; then
      TMP="$(mktemp)"
      sudo awk -v add_auto="$need_auto" -v add_ov="$need_overlay" '
        BEGIN{added=0}
        { print; if (!added && $0 ~ /^\[all\]/) {
            if (add_auto==1) print "camera_auto_detect=0";
            if (add_ov==1)   print "dtoverlay=imx219,cam0";
            added=1
        } }' "$CFG" > "$TMP"
      sudo install -m 644 "$TMP" "$CFG"; rm -f "$TMP"
    else
      { echo ""; echo "[all]";
        [[ $need_auto -eq 1 ]]   && echo "camera_auto_detect=0";
        [[ $need_overlay -eq 1 ]]&& echo "dtoverlay=imx219,cam0"; } | sudo tee -a "$CFG" >/dev/null
    fi
  fi
  echo "  -> 反映後の抜粋:"; sudo grep -n -E '^\[all\]|^\s*camera_auto_detect|^\s*dtoverlay=' "$CFG" | sed 's/^/     /'
else
  warn "config.txt が見つかりませんでした: $CFG"
fi


log "Python venv 作成: ${VENV_DIR}"
rm -rf "${VENV_DIR}" || true
sudo -u "${USER_NAME}" python3 -m venv --system-site-packages "${VENV_DIR}"
sudo -u "${USER_NAME}" bash -lc "source '${VENV_DIR}/bin/activate' && pip install -q --upgrade pip"
sudo -u "${USER_NAME}" bash -lc "source '${VENV_DIR}/bin/activate' && pip install -r requirements.txt"


log "Setup successfully completed."
echo " - Python: $(${VENV_DIR}/bin/python --version 2>&1)"
echo " - Pip:    $(${VENV_DIR}/bin/pip --version 2>&1)"
echo " - Venv:   ${VENV_DIR}"
echo " - User:   ${USER_NAME}"
echo " - OS:     ${CODENAME}"
echo ""

log "Run 'sudo reboot' to apply settings."
