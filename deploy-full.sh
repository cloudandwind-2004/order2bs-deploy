#!/bin/bash
# ==============================================================================
# deploy-full.sh  —  Pipeline đẩy ứng dụng lên web hoàn chỉnh
#
# Luồng:
#   1. Build & Push ảnh Docker lên Harbor
#   2. Cập nhật tag trong values.yaml
#   3. Git commit & push lên GitHub (ArgoCD tự sync)
#   4. Cập nhật Nginx config lên server 192.168.100.161
#
# Sử dụng:
#   bash deploy-full.sh [branch]   (mặc định: main)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Load .env ─────────────────────────────────────────────────────────────────
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a; source "$SCRIPT_DIR/.env"; set +a
else
    echo "❌ Không tìm thấy .env"; exit 1
fi

BRANCH="${1:-main}"
HARBOR_REGISTRY="${HARBOR_REGISTRY:-harbor.2bsystem.com.vn}"
HARBOR_PROJECT="${HARBOR_PROJECT:-order2bs}"
SOURCE_DIR="${PROJECT_ROOT:-$SCRIPT_DIR/../Order2bs}"
HELM_VALUES="$SCRIPT_DIR/helm/order2bs/values.yaml"

# ── Kiểm tra source code ──────────────────────────────────────────────────────
if [ ! -d "$SOURCE_DIR" ]; then
    echo "❌ Không tìm thấy folder: $SOURCE_DIR"; exit 1
fi

# ── Tạo tag ───────────────────────────────────────────────────────────────────
DATE_TAG=$(date +%Y%m%d)
SHA_TAG=$(git -C "$SOURCE_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
TAG="${DATE_TAG}-${BRANCH}-${SHA_TAG}"

echo "======================================================================"
echo "  🚀 DEPLOY FULL — order2bs"
echo "  Branch : $BRANCH"
echo "  Tag    : $TAG"
echo "  Source : $SOURCE_DIR"
echo "  Harbor : $HARBOR_REGISTRY/$HARBOR_PROJECT"
echo "  Domain : ${APP_DOMAIN:-order2bs.2bsystem.com.vn}"
echo "======================================================================"

# ── Bước 0: Đăng nhập Harbor ──────────────────────────────────────────────────
echo ">>> Bước 0: Đăng nhập Harbor..."
echo "$HARBOR_PASSWORD" | docker login "$HARBOR_REGISTRY" \
    -u "$HARBOR_USER" --password-stdin || { echo "❌ Login Harbor thất bại!"; exit 1; }

# ── Bước 1: Build & Push Backend ─────────────────────────────────────────────
echo ">>> Bước 1: Build & Push Backend..."
BACKEND_IMG="$HARBOR_REGISTRY/$HARBOR_PROJECT/backend:$TAG"
cd "$SOURCE_DIR/backend"
docker build -t "$BACKEND_IMG" .
docker push "$BACKEND_IMG"
echo "    ✅ Backend: $BACKEND_IMG"

# ── Bước 2: Build & Push Frontend ────────────────────────────────────────────
echo ">>> Bước 2: Build & Push Frontend..."
FRONTEND_IMG="$HARBOR_REGISTRY/$HARBOR_PROJECT/frontend:$TAG"
cd "$SOURCE_DIR/frontend"
docker build -t "$FRONTEND_IMG" \
    --build-arg VITE_API_URL="https://${APP_DOMAIN:-order2bs.2bsystem.com.vn}" \
    --build-arg VITE_WS_URL="wss://${APP_DOMAIN:-order2bs.2bsystem.com.vn}/ws" \
    .
docker push "$FRONTEND_IMG"
echo "    ✅ Frontend: $FRONTEND_IMG"

# ── Bước 3: Cập nhật Helm values.yaml ────────────────────────────────────────
echo ">>> Bước 3: Cập nhật Helm values.yaml..."
sed -i "s/backendTag: .*/backendTag: \"$TAG\"/" "$HELM_VALUES"
sed -i "s/frontendTag: .*/frontendTag: \"$TAG\"/" "$HELM_VALUES"
sed -i "s|host: .*|host: ${APP_DOMAIN:-order2bs.2bsystem.com.vn}|" "$HELM_VALUES"
echo "    ✅ Updated values.yaml → tag: $TAG"

# ── Bước 4: Git commit & push (trigger ArgoCD) ───────────────────────────────
echo ">>> Bước 4: Git commit & push deploy repo..."
cd "$SCRIPT_DIR"
git add helm/order2bs/values.yaml
git commit -m "deploy: $TAG" || echo "    ℹ️  Không có thay đổi mới để commit"
git push origin HEAD
echo "    ✅ Đã push lên git — ArgoCD sẽ tự động sync"

# ── Bước 5: Cập nhật Nginx (nếu có thay đổi config) ─────────────────────────
echo ">>> Bước 5: Đẩy Nginx config lên 192.168.100.161..."
bash "$SCRIPT_DIR/nginx/setup-nginx.sh"

echo ""
echo "======================================================================"
echo "  🎉 DEPLOY HOÀN TẤT!"
echo "  🌐 Truy cập: https://${APP_DOMAIN:-order2bs.2bsystem.com.vn}"
echo "  ⏳ ArgoCD sync thường mất 1—3 phút để áp dụng tag mới"
echo "======================================================================"
