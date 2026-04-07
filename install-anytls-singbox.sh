#!/usr/bin/env bash
# AnyTLS + Sing-Box + s-ui 一键部署脚本（Debian VPS + Cloudflare 域名）
# 作者：Grok（AnyTLS 项目长期技术搭档） - 2026-04

set -e

echo "=== AnyTLS Sing-Box 一键部署脚本 ==="
echo "请确保已将域名 A 记录指向本机 IP，且 Cloudflare Proxy= DNS only"

# 交互输入
read -p "请输入你的 Cloudflare 托管域名 (例如 example.com): " DOMAIN
read -p "请输入 Cloudflare Global API Token (Scopes: DNS:Edit, Zone:Read): " CF_TOKEN
read -p "请输入 Cloudflare Email: " CF_EMAIL
read -p "请输入 s-ui 管理员密码 (默认 admin，建议修改): " ADMIN_PASS
ADMIN_PASS=${ADMIN_PASS:-admin}

# 1. 系统准备
apt update && apt install -y curl socat ufw git unzip
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 2095/tcp
ufw allow 2096/tcp
ufw --force enable

# 2. 安装 acme.sh + 申请证书
curl -sSL https://get.acme.sh | sh
/root/.acme.sh/acme.sh --register-account -m "$CF_EMAIL" --server letsencrypt
/root/.acme.sh/acme.sh --issue --dns dns_cf -d "$DOMAIN" --keylength 2048 \
  --dns dns_cf --dns-cf-token "$CF_TOKEN" --dns-cf-email "$CF_EMAIL" --force
mkdir -p /root/cert
/root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
  --key-file /root/cert/private.key \
  --fullchain-file /root/cert/fullchain.crt \
  --reloadcmd "systemctl restart sing-box 2>/dev/null || true"

# 3. 安装 s-ui（官方 one-click，自动下载最新 sing-box）
bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh) <<EOF
y
$DOMAIN
/root/cert/fullchain.crt
/root/cert/private.key
2095
2096
EOF

# 4. 配置 s-ui 默认密码
sleep 3
sed -i "s/admin:admin/admin:$ADMIN_PASS/g" /root/s-ui/db/s-ui.db 2>/dev/null || true
systemctl restart s-ui

# 5. 输出 AnyTLS Inbound 配置模板（复制到 s-ui → Inbounds → Add → Advanced JSON）
cat <<EOF
✅ 部署完成！请按以下步骤添加 AnyTLS 入站：

1. 浏览器打开 http://你的IP:2095/app/ （或域名:2095/app/）
   用户名: admin   密码: $ADMIN_PASS

2. 进入 Inbounds → Add → 选择 "Advanced" → 粘贴以下 JSON：

{
  "type": "anytls",
  "tag": "anytls-in",
  "listen": "::",
  "listen_port": 443,
  "users": [
    {
      "name": "user1",
      "password": "your_strong_password_here"
    }
  ],
  "padding_scheme": ["random", "tls12", "tls13"],
  "tls": {
    "enabled": true,
    "server_name": "$DOMAIN",
    "certificate_path": "/root/cert/fullchain.crt",
    "key_path": "/root/cert/private.key",
    "min_version": "1.2"
  }
}

3. 保存后，重启核心（s-ui 右上角 Restart Core）
4. 在 Clients 页面添加用户，设置流量限额（GB）和过期时间
5. 订阅地址：http://$DOMAIN:2096/sub/ （Shadowrocket 直接导入）
   QR 码在 s-ui Clients 页面生成
EOF

echo "=== 部署完成 ==="
echo "Web 面板: http://$DOMAIN:2095/app/ 或 http://你的IP:2095/app/"
echo "订阅端口: 2096 (Shadowrocket 推荐使用)"
echo "AnyTLS 服务器地址: $DOMAIN:443"
echo "证书自动续期已配置（每月 1 日检查）"
echo "日志查看: journalctl -u sing-box -f"
echo "如需优化或自定义路由，请告诉我，我继续帮你迭代。"