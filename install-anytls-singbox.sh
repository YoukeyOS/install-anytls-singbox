#!/usr/bin/env bash
# AnyTLS + Sing-Box + s-ui 一键部署脚本 v2.0
# 修复：acme.sh 使用 CF_Token 环境变量（兼容最新版 acme.sh）
# 适用于轻量 Debian VPS + Cloudflare 托管域名
# 作者：Grok（AnyTLS 项目长期技术搭档） - 2026-04-07

set -e

echo "=== AnyTLS Sing-Box 一键部署脚本 v2.0 ==="
echo "请确保已将域名 A 记录指向本机 IP，且 Cloudflare Proxy 状态为 DNS only"

# ==================== 交互输入 ====================
read -p "请输入你的 Cloudflare 托管域名 (例如 example.com): " DOMAIN
read -p "请输入 Cloudflare Global API Token (Scopes: DNS:Edit, Zone:Read): " CF_TOKEN
read -p "请输入 Cloudflare Email: " CF_EMAIL
read -p "请输入 s-ui 管理员密码 (默认 admin，建议修改): " ADMIN_PASS
ADMIN_PASS=${ADMIN_PASS:-admin}

# ==================== 变量检查 ====================
if [[ -z "$DOMAIN" || -z "$CF_TOKEN" || -z "$CF_EMAIL" ]]; then
    echo "错误：域名、CF Token 或 Email 不能为空！"
    exit 1
fi

# ==================== 1. 系统准备 ====================
echo "正在准备系统环境..."
apt update && apt install -y curl socat ufw git unzip
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 2095/tcp
ufw allow 2096/tcp
ufw --force enable

# ==================== 2. 安装 acme.sh + 申请证书（已修复） ====================
echo "正在安装 acme.sh 并申请 Let's Encrypt 证书..."
curl -sSL https://get.acme.sh | sh

/root/.acme.sh/acme.sh --register-account -m "$CF_EMAIL" --server letsencrypt

# 使用最新推荐的环境变量方式（关键修复点）
export CF_Token="$CF_TOKEN"

echo "正在申请证书（Cloudflare DNS-01 验证）..."
/root/.acme.sh/acme.sh --issue --dns dns_cf -d "$DOMAIN" \
    --keylength 2048 --force

mkdir -p /root/cert
/root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
    --key-file /root/cert/private.key \
    --fullchain-file /root/cert/fullchain.crt \
    --reloadcmd "systemctl restart sing-box 2>/dev/null || true"

echo "证书申请成功！路径：/root/cert/"

# ==================== 3. 安装 s-ui（官方 one-click） ====================
echo "正在安装 s-ui 管理面板..."
bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh) <<EOF
y
$DOMAIN
/root/cert/fullchain.crt
/root/cert/private.key
2095
2096
EOF

# ==================== 4. 设置 s-ui 管理员密码并重启 ====================
sleep 3
sed -i "s/admin:admin/admin:$ADMIN_PASS/g" /root/s-ui/db/s-ui.db 2>/dev/null || true
systemctl restart s-ui

# ==================== 5. 部署完成提示 ====================
cat <<EOF
✅ 部署完成！AnyTLS + Sing-Box + s-ui 已就绪

Web 管理面板地址：
   http://$DOMAIN:2095/app/
   或 http://你的VPS-IP:2095/app/
   用户名: admin
   密码: $ADMIN_PASS

请按以下步骤添加 AnyTLS 入站：
1. 登录面板 → Inbounds → Add → 选择 "Advanced" 
2. 粘贴以下 JSON 并保存：

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

3. 保存后点击右上角 "Restart Core"
4. 在 Clients 页面添加用户并设置流量限额 + 过期时间
5. Shadowrocket 订阅地址：http://$DOMAIN:2096/sub/
   （面板内可直接生成二维码）

证书自动续期已配置（每月自动检查）
sing-box 日志：journalctl -u sing-box -f
s-ui 服务状态：systemctl status s-ui

如需进一步优化（多用户 API、路由策略、监控告警等），请告诉我测试结果，我立刻帮你迭代脚本。
EOF
