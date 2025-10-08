#!/usr/bin/env bash
# reprovision_pi5_trixie_min_allyes.sh
# Raspberry Pi 5 + Debian 13 (Trixie) 最小セットアップ（全自動・全てYES）
# - APT更新
# - 日本語入力 fcitx5-mozc
# - カメラ rpicam-apps / Picamera2 + /boot/firmware/config.txt 変更
# - GPIO (RPi.GPIO / gpiozero)
# - VS Code
# - Python3.13 venv（再作成・--system-site-packages）+ OpenCV(non-contrib GUI) + pillow/numpy
# - eth0 を IPv4 Link-Local（NetworkManager 必須、設定/有効化まで）
# - WayVNC は必ず削除
# - OpenCV contrib 系は入れない＆残っていれば削除
# - ビルド系（build-essential, cmake, *-dev…）は入れない＆残っていれば削除
# - ユーティリティ（net-tools/htop/unzip）は入れない＆残っていれば削除

set -euo pipefail

# ===== 固定設定 =====
USER_NAME="${SUDO_USER:-$USER}"
VENV_DIR="/home/${USER_NAME}/venv313"
LINKLOCAL_IFACE="eth0"
# ====================

log()  { echo -e "\033[1;32m==>\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }

log "OS/ユーザー確認"
CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-unknown}")"
echo " user=${USER_NAME}, codename=${CODENAME}"

# 1) APT 更新
log "APT 更新/アップグレード"
sudo apt update
sudo apt -y full-upgrade


# 2) 必要最小の基本ツール（Python系＋最低限）
log "基本ツール（最小構成）をインストール"
sudo apt install -y git curl python3 python3-venv python3-pip

# 3) 日本語入力
log "日本語入力（fcitx5 + mozc）"
sudo apt install -y fcitx5 fcitx5-mozc im-config
sudo -u "${USER_NAME}" im-config -n fcitx5 || true

# 4) カメラ
log "カメラ（rpicam-apps / Picamera2）"
sudo apt install -y rpicam-apps python3-picamera2
command -v rpicam-hello >/dev/null 2>&1 && echo " rpicam: $(rpicam-hello --version || true)"

# 4.1) /boot/firmware/config.txt を更新
log "カメラ設定（/boot/firmware/config.txt を更新
CFG="/boot/firmware/config.txt"
if [[ -f "$CFG" ]]; then
  TS="$(date +%Y%m%d%H%M%S)"
  sudo cp -a "$CFG" "${CFG}.bak-${TS}"
  # 既存の camera_auto_detect=1 を見やすくコメントアウト
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

# 5) GPIO
log "GPIO（RPi.GPIO / gpiozero）"
# 競合回避：rpi-lgpio があれば削除
dpkg -l | grep -q '^ii\s\+python3-rpi-lgpio' && sudo apt -y remove python3-rpi-lgpio || true
sudo apt install -y python3-rpi.gpio python3-gpiozero

# 6) VS Code
log "VS Code"
sudo apt install -y code || true

# 7) Python venv
log "Python venv 作成: ${VENV_DIR}"
rm -rf "${VENV_DIR}" || true
sudo -u "${USER_NAME}" python3 -m venv --system-site-packages "${VENV_DIR}"
sudo -u "${USER_NAME}" bash -lc "source '${VENV_DIR}/bin/activate' && pip install -q --upgrade pip"
sudo -u "${USER_NAME}" bash -lc "source '${VENV_DIR}/bin/activate' && pip install -r requirements.txt"
# sudo -u "${USER_NAME}" bash -lc "source '${VENV_DIR}/bin/activate' && python -c 'import cv2; print(\"[OK] cv2\", cv2.__version__)'"

# 8) eth0 を IPv4 Link-Local に固定（NetworkManager）
log "eth0 を IPv4 Link-Local（NetworkManager）へ固定"
sudo apt install -y network-manager || true
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

# 9) 最終チェック
log "簡易チェック"
echo " Python: $(python3 -V)"
echo " Picamera2 import テスト（venv外）:"
python3 - <<'PY' || true
from picamera2 import Picamera2
print(" Picamera2 OK")
PY

log "完了！ /boot/firmware/config.txt の変更を反映するには再起動してください:"
echo "  sudo reboot"
echo
echo "【次のステップ】"
echo "  source '${VENV_DIR}/bin/activate'"
echo "  python - <<'PY'"
echo "import cv2; print('cv2', cv2.__version__)"
echo "PY"
