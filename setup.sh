#!/usr/bin/env bash
# reprovision_pi5_trixie.sh (camera config edit added)
# Raspberry Pi 5 + Debian 13(Trixie) をゼロから再構成
# - APT更新/基本ツール
# - 日本語入力 fcitx5-mozc
# - カメラ rpicam-apps / Picamera2
# - (追加) /boot/firmware/config.txt を編集: camera_auto_detect=0, [all] 直下に dtoverlay=imx219,cam0
# - GPIO (RPi.GPIO / gpiozero) + pinctrl
# - VS Code
# - Python3.13 venv (--system-site-packages) + OpenCV(contrib) + ONNX Runtime
# - eth0 を IPv4 リンクローカル化 (NetworkManager)
# - WayVNC をユーザーサービスとして自動起動

set -euo pipefail

### ===== ユーザー設定（必要なら変更） =====
USER_NAME="${SUDO_USER:-$USER}"         # 対象ユーザー
VENV_DIR="/home/${USER_NAME}/venv313"   # Python venv の場所
FORCE_REBUILD_VENV="yes"                # 既存 venv を削除して作り直す
INSTALL_GUI_OPENCV="yes"                # "yes" なら GUI 付き OpenCV
ENABLE_WAYVNC="yes"                     # WayVNC を有効化
WAYVNC_BIND="0.0.0.0"                   # 待受アドレス
WAYVNC_PORT="5900"                      # 待受ポート
CONFIG_LINKLOCAL="yes"                  # 有線LAN(eth0) を Link-Local に
LINKLOCAL_IFACE="eth0"                  # 対象IF名
### =====================================

log() { echo -e "\033[1;32m==>\033[0m $*"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }

# 0) 情報
log "OS/ユーザー確認"
CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-unknown}")"
echo " user=${USER_NAME}, codename=${CODENAME}"
[[ "${CODENAME}" != "trixie" ]] && warn "Debian 13 (trixie) 以外です。続行は可能ですが結果は保証できません。"

# 1) APT 更新
log "APT 更新/アップグレード"
sudo apt update
sudo apt -y full-upgrade

# 2) 基本ツール
log "基本ツール・ビルド系"
sudo apt install -y \
  git curl unzip net-tools htop \
  build-essential \
  python3 python3-venv python3-pip \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
  libffi-dev liblzma-dev tk-dev

# 3) 日本語入力
log "日本語入力（fcitx5 + mozc）"
sudo apt install -y fcitx5 fcitx5-mozc im-config
sudo -u "${USER_NAME}" im-config -n fcitx5 || true

# 4) カメラ（rpicam-apps / Picamera2）
log "カメラ（rpicam-apps / Picamera2）"
sudo apt install -y rpicam-apps python3-picamera2
command -v rpicam-hello >/dev/null 2>&1 && echo " rpicam: $(rpicam-hello --version || true)"

# 4.1) カメラ設定（/boot/firmware/config.txt を更新）
log "カメラ設定（/boot/firmware/config.txt を更新: camera_auto_detect=0, dtoverlay=imx219,cam0）"
CFG="/boot/firmware/config.txt"
if [[ -f "$CFG" ]]; then
  TS="$(date +%Y%m%d%H%M%S)"
  sudo cp -a "$CFG" "${CFG}.bak-${TS}"

  # 既存の camera_auto_detect=1 をコメントアウト（視認性のため、上書きでも良いが重複回避）
  sudo sed -i -E 's/^(\s*)camera_auto_detect\s*=\s*1(\s*)$/# \0 (disabled by setup)/' "$CFG"

  # 既存有無の判定
  need_auto=1
  need_overlay=1
  grep -Eq '^\s*camera_auto_detect\s*=\s*0\s*$' "$CFG" && need_auto=0
  grep -Eq '^\s*dtoverlay\s*=\s*imx219,cam0\s*$' "$CFG" && need_overlay=0

  if [[ $need_auto -eq 0 && $need_overlay -eq 0 ]]; then
    echo "  -> 既に目的の設定が入っています。変更なし。"
  else
    if grep -q '^\[all\]' "$CFG"; then
      # [all] の最初の出現直後に、足りない行をだけ差し込む
      TMP="$(mktemp)"
      sudo awk -v add_auto="$need_auto" -v add_ov="$need_overlay" '
        BEGIN{added=0}
        {
          print
          if (!added && $0 ~ /^\[all\]/) {
            if (add_auto==1) print "camera_auto_detect=0"
            if (add_ov==1)   print "dtoverlay=imx219,cam0"
            added=1
          }
        }' "$CFG" > "$TMP"
      sudo install -m 644 "$TMP" "$CFG"
      rm -f "$TMP"
    else
      # [all] セクションが無い場合は末尾に新設
      {
        echo ""
        echo "[all]"
        [[ $need_auto -eq 1 ]]   && echo "camera_auto_detect=0"
        [[ $need_overlay -eq 1 ]]&& echo "dtoverlay=imx219,cam0"
      } | sudo tee -a "$CFG" >/dev/null
    fi
  fi

  echo "  -> 反映後の抜粋:"
  sudo grep -n -E '^\[all\]|^\s*camera_auto_detect|^\s*dtoverlay=' "$CFG" | sed 's/^/     /'
else
  warn "config.txt が見つかりませんでした: $CFG"
fi

# 5) GPIO
log "GPIO（RPi.GPIO / gpiozero）"
# rpi-lgpio が入っていたら削除（競合回避）
dpkg -l | grep -q '^ii\s\+python3-rpi-lgpio' && sudo apt -y remove python3-rpi-lgpio || true
sudo apt install -y python3-rpi.gpio python3-gpiozero

# pinctrl（raspi-gpio の置き換えツール）導入
if ! command -v pinctrl >/dev/null 2>&1; then
  log "pinctrl をビルドして導入"
  sudo apt install -y --no-install-recommends git cmake device-tree-compiler libfdt-dev
  sudo -u "${USER_NAME}" mkdir -p "/home/${USER_NAME}/src"
  [[ -d "/home/${USER_NAME}/src/utils" ]] || sudo -u "${USER_NAME}" git clone --depth 1 https://github.com/raspberrypi/utils.git "/home/${USER_NAME}/src/utils"
  cd "/home/${USER_NAME}/src/utils/pinctrl"
  sudo -u "${USER_NAME}" mkdir -p build
  cd build
  sudo -u "${USER_NAME}" cmake .. -DCMAKE_BUILD_TYPE=Release
  make -j"$(nproc)"
  sudo install -m 755 pinctrl /usr/local/bin/pinctrl
  /usr/local/bin/pinctrl -v || true
else
  echo " pinctrl は既に存在: $(command -v pinctrl)"
fi

# 6) VS Code
log "VS Code"
sudo apt install -y code || true

# 7) Python venv + OpenCV + ONNX Runtime（--system-site-packages）
log "Python venv 構築: ${VENV_DIR}"
if [[ -d "${VENV_DIR}" && "${FORCE_REBUILD_VENV}" == "yes" ]]; then
  rm -rf "${VENV_DIR}"
fi
sudo -u "${USER_NAME}" python3 -m venv --system-site-packages "${VENV_DIR}"
sudo -u "${USER_NAME}" bash -lc "source '${VENV_DIR}/bin/activate' && pip install -q --upgrade pip"
if [[ "${INSTALL_GUI_OPENCV}" == "yes" ]]; then
  log "OpenCV (GUI版) をインストール"
  sudo -u "${USER_NAME}" bash -lc "source '${VENV_DIR}/bin/activate' && pip install -q numpy opencv-contrib-python"
else
  log "OpenCV (headless/contrib) をインストール"
  sudo -u "${USER_NAME}" bash -lc "source '${VENV_DIR}/bin/activate' && pip install -q numpy opencv-contrib-python-headless"
fi
log "ONNX Runtime をインストール（tflite-runtime 代替）"
sudo -u "${USER_NAME}" bash -lc "source '${VENV_DIR}/bin/activate' && pip install -q --upgrade onnxruntime && python - <<'PY'\nimport onnxruntime as ort; print('[OK] onnxruntime', ort.__version__)\nPY"

# 8) 有線LANをリンクローカル (NetworkManager) に
if [[ "${CONFIG_LINKLOCAL}" == "yes" ]]; then
  log "eth0 を IPv4 リンクローカルへ（NetworkManager）"
  sudo apt install -y network-manager || true
  if systemctl is-active --quiet NetworkManager; then
    CON=$(sudo nmcli -t -f NAME,DEVICE con show | awk -F: -v dev="${LINKLOCAL_IFACE}" '$2==dev{print $1; exit}')
    if [[ -z "${CON}" ]]; then
      CON="${LINKLOCAL_IFACE}-linklocal"
      sudo nmcli con add type ethernet ifname "${LINKLOCAL_IFACE}" con-name "${CON}" \
        ipv4.method link-local ipv6.method ignore
    else
      sudo nmcli con mod "${CON}" ipv4.method link-local ipv4.addresses "" ipv4.gateway "" ipv4.dns "" ipv4.never-default yes
      sudo nmcli con mod "${CON}" ipv6.method ignore
    fi
    sudo nmcli con down "${CON}" || true
    sudo nmcli con up "${CON}"   || true
    echo " 確認: $(ip -4 a show dev ${LINKLOCAL_IFACE} | grep -o '169\.254[^/ ]*' || echo '未割当')"
  else
    warn "NetworkManager が起動していません。リンクローカル設定はスキップしました。"
  fi
else
  log "リンクローカル設定はスキップ（CONFIG_LINKLOCAL=no）"
fi

# 9) WayVNC（ユーザーサービスを自動生成）
if [[ "${ENABLE_WAYVNC}" == "yes" ]]; then
  log "WayVNC を導入し、自前の user unit を作成"
  sudo apt install -y wayvnc
  sudo -u "${USER_NAME}" mkdir -p "/home/${USER_NAME}/.config/systemd/user"
  sudo -u "${USER_NAME}" tee "/home/${USER_NAME}/.config/systemd/user/wayvnc.service" >/dev/null <<EOF
[Unit]
Description=WayVNC server (user)
After=graphical-session.target

[Service]
Type=simple
ExecStartPre=/bin/sleep 2
ExecStart=/usr/bin/wayvnc ${WAYVNC_BIND}:${WAYVNC_PORT}
Restart=on-failure

[Install]
WantedBy=graphical-session.target
EOF

  # user manager を常駐（ログインなしでも有効化可能に）
  sudo loginctl enable-linger "${USER_NAME}" || true
  # 有効化＆起動（GUIセッション後に起動される想定）
  sudo -u "${USER_NAME}" systemctl --user daemon-reload || true
  sudo -u "${USER_NAME}" systemctl --user enable --now wayvnc || true || \
    warn "GUI ログイン後に次を実行:  systemctl --user enable --now wayvnc"
else
  log "WayVNC 設定はスキップ（ENABLE_WAYVNC=no）"
fi

# 10) 簡易チェック
log "簡易チェック"
echo " Python: $(python3 -V)"
echo " Picamera2 import テスト（venv外）:"
python3 - <<'PY' || true
from picamera2 import Picamera2
print(" Picamera2 OK")
PY
echo " pinctrl テスト:"
sudo pinctrl get 4 || true

log "すべて完了！config.txt の変更を反映するには再起動してください:  sudo reboot"
echo
echo "【次のステップ例】"
echo "  source '${VENV_DIR}/bin/activate'    # venv 有効化"
echo "  python - <<'PY'"
echo "import cv2, onnxruntime as ort; print('cv2', cv2.__version__, '| onnxruntime', ort.__version__)"
echo "PY"
