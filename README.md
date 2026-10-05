# Secure CalDAV & Google Calendar Bi-directional Sync System

Proxmox VE 上の超軽量 LXC コンテナ環境において、Nextcloud（CalDAV）と Google カレンダーを完全自動で双方向同期する常駐基盤です[cite: 3]。  
宅内の外部ポート開放を一切行わず、Tailscale（オーバーレイネットワーク）と Cloudflare DNS-01（ACME）を組み合わせた完全閉域 SSL 通信を実現しています[cite: 3]。

---

## 1. システム構成図 (Architecture)

```mermaid
graph TD
    subgraph Home_Environment [宅内オンプレミス基盤 (Proxmox VE)]
        subgraph LXC_Sync [LXC 105: vdirsyncer (256MB RAM)]
            Cron[systemd timer] -->|15分毎に実行| SyncEngine[vdirsyncer]
        end

        subgraph LXC_NC [LXC 100: Nextcloud Hub]
            NCP[Nextcloud Server]
            Certbot[Certbot DNS-01] -->|正規証明書更新| NCP
        end
    end

    subgraph Overlay_Network [Tailscale メッシュ閉域網]
        Tailnet((Tailnet 100.64.0.0/10))
    end

    subgraph External_Services [外部クラウドサービス]
        GCloud[Google Calendar API]
        CF_DNS[Cloudflare DNS (DNS-01)]
    end

    SyncEngine -->|TUNパススルー| Tailnet
    Tailnet -->|HTTPS / 閉域通信| NCP
    SyncEngine -->|OAuth 2.0 / 永続トークン| GCloud
    Certbot -.->|TXTレコード更新| CF_DNS
```

---

## 2. 設計判断とアーキテクチャ選定 (Design Decisions)

| 検討項目 | 採用方式 | 却下した方式と理由 |
| :--- | :--- | :--- |
| **同期方式** | サーバー間常駐同期 (`vdirsyncer`) | **URL購読（iCal）**: 最大24hのキャッシュ遅延があり片道通行[cite: 3]。<br>**端末同期（DAVx⁵）**: クライアント端末依存となり自律インフラ化できない[cite: 3]。 |
| **ネットワーク** | Tailscale CGNAT + DNS-01 | **生グローバルIPv6露出**: ファイアウォール透過時のセキュリティリスク大[cite: 3]。<br>**Cloudflare Tunnel**: 宅内データが外部CDNを経由するため閉域主義に反する[cite: 3]。 |
| **SSL検証** | 正規 Let's Encrypt 証明書 | **自己署名証明書（オレオレ）**: `vdirsyncer` が仕様上 SSL 検証の無効化（`verify=false`）を禁止しており、保守性が悪化するため[cite: 3]。 |
| **OAuth運用** | Google Cloud 本番環境昇格 | **テスト環境運用**: 7日間でリフレッシュトークンが強制失効し、同期が恒久停止する仕様を回避[cite: 3]。 |

---

## 3. 直面した技術課題と解決策 (Technical Challenges)

### ① 非特権 LXC コンテナにおける TUN デバイス制約
* **事象**: vdirsyncer 専用コンテナ（Debian 最小構成）を Tailscale 閉域網へ参加させる際、`tstun.New("tailscale0") failed` が発生し起動不能[cite: 3]。
* **原因**: Proxmox VE の非特権コンテナはセキュリティ制約上、ホストの `/dev/net/tun` デバイスへのアクセス権限を持たない[cite: 3]。
* **解決**: Proxmox ホスト側（`/etc/pve/lxc/<VMID>.conf`）に cgroup デバイス許可およびバインドマウント設定を投入し、最小権限を維持したまま TUN パススルーを確立[cite: 3]。

### ② ヘッドレス環境における動的ポート OAuth 2.0 のデッドロック
* **事象**: `vdirsyncer discover` 実行時、コンテナ内の一時 Web サーバーがローカル動的ポート（例: `http://127.0.0.1:52107`）でリダイレクト待機状態となり、外部ブラウザからのアクセスが届かずセッションがスタック[cite: 3]。
* **解決**: 認証用リダイレクト URL から認可コードを抽出し、標準ライブラリ（`urllib`）のみで完結するトークン交換スクリプト（`scripts/get_token.py`）を自作して直接 `google_token` を生成[cite: 3, 5, 7]。

### ③ ポート全閉環境における正規 SSL/TLS 証明書の維持
* **事象**: プライベート IP 直打ちではブラウザ警告および SSL 検証エラーが発生するが、自宅ルーターの 80/443 ポートを開放できない[cite: 3]。
* **解決**: Cloudflare API による DNS-01 チャレンジを採用[cite: 3]。TXT レコードの自動書き換えによって外部ポート開放ゼロのまま正規証明書を発行し、OS ルート証明書バンドル（`ca-certificates`）経由で安全に検証を通過[cite: 3]。

---

## 4. クイックスタート (Setup)

### 1. 依存パッケージの導入
```bash
apt update && apt install -y vdirsyncer ca-certificates
```

### 2. 設定ファイルの配備
```bash
cp config/vdirsyncer/config.example ~/.config/vdirsyncer/config
chmod 600 ~/.config/vdirsyncer/config
# config 内の URL、ユーザー名、パスワード、クライアント情報を編集
```

### 3. Google OAuth トークンの取得
```bash
python3 scripts/get_token.py
```

### 4. コレクション検出と初回同期
```bash
vdirsyncer discover
vdirsyncer sync
```

### 5. 自動化の有効化 (systemd)
```bash
cp systemd/vdirsyncer.* /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now vdirsyncer.timer
```
## 5. ライセンス (License)
MIT License
