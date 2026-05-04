#!/bin/bash
# ==============================================================================
# Order2bs - Auto Build & Deploy Script
# Tác giả: 2B System (Tùy chỉnh cho Order2bs)
# ==============================================================================

set -e

# 1. Load biến từ .env
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    echo ">>> Loading cấu hình từ file .env..."
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
else
    echo "❌ Không tìm thấy file .env. Vui lòng tạo file .env trước."
    exit 1
fi

BRANCH="${1:-main}"

# Cấu hình đường dẫn
HARBOR_REGISTRY="${HARBOR_REGISTRY:-harbor.2bsystem.com.vn}"
HARBOR_PROJECT="${HARBOR_PROJECT:-order2bs}"
# PROJECT_ROOT lấy từ .env, nếu không có thì mặc định cùng cấp
SOURCE_DIR="${PROJECT_ROOT:-$SCRIPT_DIR/../Order2bs}"
HELM_VALUES="$SCRIPT_DIR/helm/order2bs/values.yaml"

# Kiểm tra xem folder source code có tồn tại không
if [ ! -d "$SOURCE_DIR" ]; then
    echo "❌ Không tìm thấy folder dự án tại: $SOURCE_DIR"
    echo "Vui lòng kiểm tra lại PROJECT_ROOT trong file .env"
    exit 1
fi

# Tạo Tag chuyên nghiệp (Ngày-Branch-GitHash)
DATE_TAG=$(date +%Y%m%d)
SHA_TAG=$(git -C "$SOURCE_DIR" rev-parse --short HEAD || echo "unknown")
TAG="${DATE_TAG}-${BRANCH}-${SHA_TAG}"

echo "======================================================================"
echo "  🚀 ORDER2BS AUTO DEPLOY"
echo "  Branch : $BRANCH"
echo "  Tag    : $TAG"
echo "  Source : $SOURCE_DIR"
echo "  Harbor : $HARBOR_REGISTRY/$HARBOR_PROJECT"
echo "======================================================================"

# Bước 0: Đăng nhập Harbor
echo ">>> Bước 0: Đăng nhập Harbor..."
echo "$HARBOR_PASSWORD" | docker login "$HARBOR_REGISTRY" -u "$HARBOR_USER" --password-stdin || {
    echo "❌ Đăng nhập Harbor thất bại (Sai user/pass hoặc registry không phản hồi)!"
    exit 1
}

# Bước 1: Build & Push Backend (Golang)
echo ">>> Bước 1: Build & Push Backend image..."
BACKEND_IMG="$HARBOR_REGISTRY/$HARBOR_PROJECT/backend:$TAG"

cd "$SOURCE_DIR/backend"
docker build -t "$BACKEND_IMG" .
docker push "$BACKEND_IMG"
echo "    ✅ Backend image pushed: $BACKEND_IMG"

# Bước 2: Build & Push Frontend (React)
echo ">>> Bước 2: Build & Push Frontend image..."
FRONTEND_IMG="$HARBOR_REGISTRY/$HARBOR_PROJECT/frontend:$TAG"

cd "$SOURCE_DIR/frontend"
docker build -t "$FRONTEND_IMG" .
docker push "$FRONTEND_IMG"
echo "    ✅ Frontend image pushed: $FRONTEND_IMG"

# Bước 3: Cập nhật Helm Values
echo ">>> Bước 3: Cập nhật tag mới vào Helm values.yaml..."
# Sửa tag ảnh
sed -i "s/backendTag: .*/backendTag: \"$TAG\"/" "$HELM_VALUES"
sed -i "s/frontendTag: .*/frontendTag: \"$TAG\"/" "$HELM_VALUES"
# Sửa host domain
sed -i "s|host: .*|host: $APP_DOMAIN|" "$HELM_VALUES"

echo "    ✅ Updated values.yaml with tag: $TAG"

echo "======================================================================"
echo "  🎉 DEPLOY HOÀN TẤT!"
echo "  Bây giờ bạn chỉ cần commit & push repo này để ArgoCD thực hiện Sync."
echo "======================================================================"
