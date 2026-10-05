#!/usr/bin/env python3
"""
get_google_token.py
ヘッドレス環境向け Google OAuth 2.0 リフレッシュトークン直接取得スクリプト
外部依存ライブラリなし（Python 3 標準ライブラリのみ）で動作
"""

import json
import os
import urllib.parse
import urllib.request

# --- 設定項目（実行時に対話入力、または直接書き換え） ---
CLIENT_ID = input("Google Client ID を入力: ").strip()
CLIENT_SECRET = input("Google Client Secret を入力: ").strip()
REDIRECT_URI = "http://127.0.0.1:8080"
TOKEN_FILE = os.path.expanduser("~/.config/vdirsyncer/google_token")

auth_url = (
    "https://accounts.google.com/o/oauth2/v2/auth?"
    + urllib.parse.urlencode({
        "client_id": CLIENT_ID,
        "redirect_uri": REDIRECT_URI,
        "response_type": "code",
        "scope": "https://www.googleapis.com/auth/calendar",
        "access_type": "offline",
        "prompt": "consent",
    })
)

print("\n1. 以下のURLをブラウザで開いてログイン・許可してください:\n")
print(auth_url)
print("\n2. ブラウザが接続エラー（127.0.0.1:8080 になったら、）")
print("   アドレスバーのURL全体、または「code=」の後ろの文字列を貼り付けてEnterを押してください:\n")

raw_input_data = input("入力: ").strip()

# URL全体が貼り付けられた場合と、コード単体が貼り付けられた場合の両方に対応
if "code=" in raw_input_data:
    parsed = urllib.parse.urlparse(raw_input_data)
    code = urllib.parse.parse_qs(parsed.query).get("code", [raw_input_data])[0]
else:
    code = raw_input_data

data = urllib.parse.urlencode({
    "code": code,
    "client_id": CLIENT_ID,
    "client_secret": CLIENT_SECRET,
    "redirect_uri": REDIRECT_URI,
    "grant_type": "authorization_code",
}).encode("utf-8")

req = urllib.request.Request("https://oauth2.googleapis.com/token", data=data)

try:
    with urllib.request.urlopen(req) as resp:
        token_data = json.loads(resp.read().decode("utf-8"))
        os.makedirs(os.path.dirname(TOKEN_FILE), exist_ok=True)
        with open(TOKEN_FILE, "w", encoding="utf-8") as f:
            json.dump(token_data, f, indent=2)
        os.chmod(TOKEN_FILE, 0o600)
        print("\n[成功] トークンが正常に取得され、保存されました:")
        print(TOKEN_FILE)
except urllib.error.HTTPError as e:
    print(f"\n[Google API エラー {e.code}]:")
    print(e.read().decode("utf-8"))