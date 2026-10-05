#!/bin/bash
# ==============================================================================
# check_sync_status.sh
# vdirsyncer 同期状態および systemd 監視スクリプト
# ==============================================================================

set -euo pipefail

TOKEN_FILE="${HOME}/.config/vdirsyncer/google_token"
TIMER_NAME="vdirsyncer.timer"
SERVICE_NAME="vdirsyncer.service"

echo "=================================================="
echo " vdirsyncer Health Check Report"
echo " Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="

# 1. systemd タイマーおよびサービスの状態確認
echo -e "\n[1] systemd Status:"
if systemctl is-active --quiet "${TIMER_NAME}"; then
    echo "  - ${TIMER_NAME}: ACTIVE"
    systemctl list-timers "${TIMER_NAME}" --no-legend | awk '{print "    次回実行予定: "$1" "$2" (残り "$3")"}'
else
    echo "  - [警告] ${TIMER_NAME} が停止しています。"
fi

if systemctl is-failed --quiet "${SERVICE_NAME}"; then
    echo "  - [エラー] 直近の ${SERVICE_NAME} 実行が FAILED になっています。"
else
    echo "  - ${SERVICE_NAME}: OK (直近の実行は正常終了)"
fi

# 2. OAuth トークンファイルの生存確認
echo -e "\n[2] Google OAuth Token Status:"
if [ -f "${TOKEN_FILE}" ]; then
    MOD_TIME=$(date -r "${TOKEN_FILE}" '+%Y-%m-%d %H:%M:%S')
    echo "  - トークンファイル存在確認: OK (${TOKEN_FILE})"
    echo "  - 最終更新日時: ${MOD_TIME}"
else
    echo "  - [エラー] トークンファイルが見つかりません: ${TOKEN_FILE}"
fi

# 3. systemd journal から直近ログの確認とエラー判定
echo -e "\n[3] Log Analysis (systemd journal: ${SERVICE_NAME}):"
RECENT_LOGS=$(journalctl -u "${SERVICE_NAME}" -n 10 --no-pager 2>/dev/null || true)

if [ -n "${RECENT_LOGS}" ]; then
    echo "  - 直近の実行ログ 10 行:"
    echo "--------------------------------------------------"
    echo "${RECENT_LOGS}"
    echo "--------------------------------------------------"

    # エラー・例外キーワードの検出
    if echo "${RECENT_LOGS}" | grep -Ei "error|exception|critical|failed" > /dev/null 2>&1; then
        echo "  - [注意] 直近ログ内にエラーまたは警告キーワードが検出されました。"
    else
        echo "  - ログ判定: ALL GREEN (エラー検出なし)"
    fi
else
    echo "  - [警告] 実行ログが journald に見当たりません。"
fi

echo -e "\n=================================================="
echo " Check Complete."
echo "=================================================="