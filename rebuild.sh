#!/bin/bash
# ==============================================================================
# rebuild.sh – Rebuild Frontend + Backend images và push lên Harbor
# Chạy: bash rebuild.sh
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a; source "$SCRIPT_DIR/.env"; set +a
else
    echo "❌ Không tìm thấy .env"; exit 1
fi

SOURCE_DIR="${PROJECT_ROOT:-$SCRIPT_DIR/../Order2bs}"
HELM_VALUES="$SCRIPT_DIR/helm/order2bs/values.yaml"

# Tạo tag theo timestamp + git hash
DATE_TAG=$(date +%Y%m%d)
SHA_TAG=$(git -C "$SOURCE_DIR" rev-parse --short HEAD 2>/dev/null || echo "fix")
TAG="${DATE_TAG}-main-${SHA_TAG}"

HARBOR_REGISTRY="${HARBOR_REGISTRY:-harbor.2bsystem.com.vn}"
HARBOR_PROJECT="${HARBOR_PROJECT:-order2bs}"
DOMAIN="${APP_DOMAIN:-order2bs.2bsystem.com.vn}"

echo "======================================================"
echo "  🔨 REBUILD & PUSH — order2bs"
echo "  Tag    : $TAG"
echo "  Domain : $DOMAIN"
echo "======================================================"

# Login Harbor
echo ">>> Đăng nhập Harbor..."
echo "$HARBOR_PASSWORD" | docker login "$HARBOR_REGISTRY" \
    -u "$HARBOR_USER" --password-stdin

# ── Build Backend ──────────────────────────────────────────────────────────
echo ""
echo ">>> Build Backend..."
BACKEND_IMG="$HARBOR_REGISTRY/$HARBOR_PROJECT/backend:$TAG"
docker build -t "$BACKEND_IMG" "$SOURCE_DIR/backend/"
docker push "$BACKEND_IMG"
echo "  ✅ Backend: $BACKEND_IMG"

# ── Build Frontend (truyền VITE_API_URL đúng) ─────────────────────────────
echo ""
echo ">>> Build Frontend với VITE_API_URL=/"
FRONTEND_IMG="$HARBOR_REGISTRY/$HARBOR_PROJECT/frontend:$TAG"
docker build \
    --build-arg VITE_API_URL="/" \
    --build-arg VITE_WS_URL="/ws" \
    -t "$FRONTEND_IMG" \
    "$SOURCE_DIR/frontend/"
docker push "$FRONTEND_IMG"
echo "  ✅ Frontend: $FRONTEND_IMG"

# ── Cập nhật Helm values ──────────────────────────────────────────────────
echo ""
echo ">>> Cập nhật values.yaml với tag mới: $TAG"
sed -i "s/backendTag: .*/backendTag: \"$TAG\"/" "$HELM_VALUES"
sed -i "s/frontendTag: .*/frontendTag: \"$TAG\"/" "$HELM_VALUES"

# ── Commit & Push deploy repo ─────────────────────────────────────────────
echo ""
echo ">>> Git commit & push..."
cd "$SCRIPT_DIR"
git add helm/order2bs/values.yaml
git commit -m "rebuild: $TAG — fix CrashLoopBackOff (nginx resolver + initContainer)" || true
git push origin HEAD

echo ""
echo "======================================================"
echo "  🎉 Done! ArgoCD sẽ tự sync trong vài phút."
echo "  Tag mới: $TAG"
echo "======================================================"
