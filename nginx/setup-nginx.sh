#!/bin/bash
# ==============================================================================
# setup-nginx.sh
# Copy Nginx config lên server 192.168.100.161 và reload
# Chạy từ máy local: bash nginx/setup-nginx.sh
# ==============================================================================

set -e

NGINX_SERVER="192.168.100.161"
NGINX_USER="2bs"
NGINX_PASS="taipeiASSASSIN@31"
CONF_SRC="$(dirname "$0")/order2bs.conf"
CONF_DEST="/etc/nginx/sites-available/order2bs.conf"
CONF_LINK="/etc/nginx/sites-enabled/order2bs.conf"

echo "======================================================"
echo "  📤 Đẩy Nginx config lên $NGINX_SERVER ..."
echo "======================================================"

# Dùng sshpass để không cần nhập password thủ công
if ! command -v sshpass &>/dev/null; then
    echo "⚠️  sshpass chưa được cài. Đang cài..."
    sudo apt-get install -y sshpass 2>/dev/null || sudo yum install -y sshpass 2>/dev/null
fi

# Copy file config lên server
sshpass -p "$NGINX_PASS" scp -o StrictHostKeyChecking=no \
    "$CONF_SRC" "${NGINX_USER}@${NGINX_SERVER}:/tmp/order2bs.conf"

# Thực thi các lệnh trên server từ xa
sshpass -p "$NGINX_PASS" ssh -o StrictHostKeyChecking=no \
    "${NGINX_USER}@${NGINX_SERVER}" bash -s << 'EOF'
    set -e

    echo ">>> Di chuyển config vào /etc/nginx/sites-available/ ..."
    sudo mv /tmp/order2bs.conf /etc/nginx/sites-available/order2bs.conf

    echo ">>> Tạo symlink vào sites-enabled (nếu chưa có) ..."
    sudo ln -sf /etc/nginx/sites-available/order2bs.conf /etc/nginx/sites-enabled/order2bs.conf

    echo ">>> Kiểm tra cú pháp Nginx ..."
    sudo nginx -t

    echo ">>> Reload Nginx ..."
    sudo systemctl reload nginx

    echo "✅ Nginx đã được cập nhật thành công!"
EOF

echo ""
echo "======================================================"
echo "  🎉 Hoàn tất! Nginx đã cấu hình cho:"
echo "     http://order2bs.2bsystem.com.vn"
echo "     → Kubernetes Ingress: 192.168.100.170:80"
echo "======================================================"
