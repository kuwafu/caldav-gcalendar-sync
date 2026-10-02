# Secure CalDAV & Google Calendar Bi-directional Sync System

Proxmox VE 上の超軽量 LXC コンテナ環境において、Nextcloud（CalDAV）と Google カレンダーを完全自動で双方向同期する常駐基盤です。  
宅内の外部ポート開放を一切行わず、Tailscale（オーバーレイネットワーク）と Cloudflare DNS-01（ACME）を組み合わせた完全閉域 SSL 通信を実現しています。

---

## 1. システム構成図 (Architecture)

```mermaid
graph TD
    subgraph Home_Environment [宅内オンプレミス基盤 (Proxmox VE)]
        subgraph LXC_Sync [LXC 105: vdirsyncer (256MB RAM)]
            Cron[systemd / cron] -->|15分毎に実行| SyncEngine[vdirsyncer]
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
