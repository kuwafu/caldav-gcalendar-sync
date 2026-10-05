#!/bin/sh
# /etc/letsencrypt/renewal-hooks/deploy/reload-apache.sh
# 証明書自動更新後にWebサーバー（Apache）をリロード
systemctl reload apache2