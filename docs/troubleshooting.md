# Troubleshooting & Post-Mortem Records

本同期基盤の構築過程において直面した技術的課題、根本原因の分析（Root Cause Analysis）、および恒久対応策の記録です[cite: 3]。

---

## 1. ネットワーク & OS レイヤー

### Case 1-1: LXC コンテナ作成直後の DNS タイムアウト
* **事象**: コンテナ初期セットアップ時、`apt install` が極端に遅延し `Temporary failure resolving 'deb.debian.org'` が発生[cite: 3]。
* **根本原因**: Proxmox のコンテナ作成時にゲートウェイおよび DNS サーバーが未定義だったため、外部名前解決要求がタイムアウトを繰り返していた[cite: 3]。
* **対処**: `/etc/resolv.conf` にパブリック DNS（`1.1.1.1`）を一時設定後、Proxmox ホスト側の「DNS」タブに恒久設定を投入して解決[cite: 3]。

### Case 1-2: Tailscale 導入に伴うローカル IPv4 リースの消失
* **事象**: Nextcloud コンテナに Tailscale を導入した直後、コンテナの `eth0` から宅内ローカル IPv4（`192.168.0.x`）が消失し、IPv6 しか割り当たらない状態となった[cite: 3]。
* **根本原因**: Tailscale のルーティング制御および MagicDNS 導入時、OS 側の DHCP クライアントのリース更新が干渉を受け、デフォルトゲートウェイごとローカル IPv4 が解放されていた[cite: 3]。
* **対処**: 一時的に同一 Proxmox ブリッジ内の IPv6 直通通信で疎通を確保した後、Tailscale の固定プライベート IPv4 空間（`100.64.0.0/10`）へ通信経路を統一[cite: 3]。

### Case 1-3: 非特権 LXC コンテナにおける TUN デバイス作成権限不足
* **事象**: vdirsyncer 専用コンテナ（105）で `tailscale up` を実行した際、`tstun.New("tailscale0") failed` を吐いてデーモンがクラッシュ[cite: 3]。
* **根本原因**: 非特権コンテナの AppArmor / cgroup セキュリティ制限により、ホストのカーネルデバイス `/dev/net/tun` へのアクセスおよび仮想インターフェースの作成が拒否されていた[cite: 3]。
* **対処**: Proxmox ホスト側の設定ファイル（`/etc/pve/lxc/105.conf`）に以下を追記し、明示的に TUN デバイスをパススルー[cite: 3]:
  ```ini
  lxc.cgroup2.devices.allow: c 10:200 rwm
  lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
  ```

---

## 2. 暗号化 & PKI (公開鍵基盤) レイヤー

### Case 2-1: vdirsyncer の仕様による SSL 完全無効化の拒絶
* **事象**: 自己署名証明書（オレオレ証明書）環境下で `verify_ssl = false` または `verify = false` を指定してもエラーとなり接続できない[cite: 3]。
* **根本原因**: `vdirsyncer` の設計思想上、中間者攻撃（MITM）を防止するため「証明書検証の完全無効化（Insecure Skip Verify）」が意図的に実装から排除されている[cite: 3]。
* **対処**: 自己署名証明書（PEM）をクライアントに手動配布して指定するか、正規認証局（Let's Encrypt）から発行された公的証明書を適用する設計へと方針転換[cite: 3]。

### Case 2-2: ルート証明書バンドル (ca-certificates) 不足による検証失敗
* **事象**: Nextcloud に正規 Let's Encrypt 証明書を配備したにもかかわらず、vdirsyncer コンテナ側で `[SSL: CERTIFICATE_VERIFY_FAILED] unable to get local issuer certificate` が発生[cite: 3]。
* **根本原因**: Debian の最小構成（Minimal）テンプレートで構築されたコンテナ内に、公的認証局のルート証明書群（`ca-certificates`）がプリインストールされておらず、Let's Encrypt の中間・ルート CA を検証できなかった[cite: 3]。
* **対処**: `apt install -y ca-certificates` を導入し、設定ファイルの `verify` に `/etc/ssl/certs/ca-certificates.crt` を指定して解決[cite: 3, 5]。

---

## 3. 認証・認可 (OAuth 2.0) レイヤー

### Case 3-1: ヘッドレス環境における一時 Web サーバーの待受デッドロック
* **事象**: `vdirsyncer discover` 実行時、ターミナル上に認可 URL が表示された後、処理が完全に停止（フリーズ）してプロンプトに戻らない[cite: 3]。
* **根本原因**: `vdirsyncer` がコンテナ内のローカル動的ポート（例: `http://127.0.0.1:52107/`）でバックグラウンド HTTP サーバーを立ち上げ、ブラウザからのリダイレクトコールバックを待機していたため。ヘッドレス環境ではクライアント PC のブラウザからコンテナの `127.0.0.1` へアクセスが到達せず、受信待ちのままスタックしていた[cite: 3]。
* **対処**: ブラウザ認可後にアドレスバーに表示されるリダイレクト URL（または `code=` パラメータ）を取得し、標準ライブラリ（`urllib`）のみで直接 Google トークンエンドポイントへ POST して `google_token` を手動生成するスクリプト（`get_google_token.py`）を自作して回避[cite: 3, 5]。

### Case 3-2: Google OAuth テスト環境における 7 日間トークン失効トラップ
* **事象**: 初回同期が成功しても、運用開始から約 7 日後に突然 Google API との通信が `invalid_grant` で停止する仕様上のリスク[cite: 3]。
* **根本原因**: Google Cloud Console の OAuth 同意画面が「テスト中（Testing）」ステータスの場合、セキュリティ仕様により発行されたリフレッシュトークンの有効期限が最大 7 日間に制限される[cite: 3]。
* **対処**: 所有ドメイン（`example.com`）の所有権を Google Search Console で DNS 認証し、OAuth アプリのステータスを「本番環境（In production）」へと昇格させることで、リフレッシュトークンを完全永続化[cite: 3]。