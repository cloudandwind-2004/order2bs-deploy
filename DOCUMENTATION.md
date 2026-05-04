# Tài Liệu Dự Án Order2bs — Deploy Repository

> **Phiên bản:** 1.0.0 | **Cập nhật lần cuối:** 26/04/2026  
> **GitHub:** [Anab821/order2bs-deploy](https://github.com/Anab821/order2bs-deploy)

---

## Mục Lục

1. [Tổng Quan](#1-tổng-quan)
2. [Kiến Trúc Hệ Thống](#2-kiến-trúc-hệ-thống)
3. [Cấu Trúc Thư Mục](#3-cấu-trúc-thư-mục)
4. [Mô Tả Chi Tiết Từng Thành Phần](#4-mô-tả-chi-tiết-từng-thành-phần)
   - 4.1 [File `.env`](#41-file-env)
   - 4.2 [Script `deploy.sh`](#42-script-deploysh)
   - 4.3 [Script `deploy-full.sh`](#43-script-deploy-fullsh)
   - 4.4 [Helm Chart](#44-helm-chart)
   - 4.5 [Nginx Reverse Proxy](#45-nginx-reverse-proxy)
5. [Luồng Triển Khai (CI/CD)](#5-luồng-triển-khai-cicd)
6. [Hướng Dẫn Sử Dụng](#6-hướng-dẫn-sử-dụng)
7. [Lưu Ý Bảo Mật](#7-lưu-ý-bảo-mật)
8. [Xuất Tài Liệu Ra File DOCX](#8-xuất-tài-liệu-ra-file-docx)

---

## 1. Tổng Quan

**Order2bs** là hệ thống quản lý đặt món ăn trưa dành cho doanh nghiệp, bao gồm:

| Thành phần | Công nghệ |
|---|---|
| Backend | Go (Golang), REST API + WebSocket |
| Frontend | React (Vite), TypeScript |
| Cơ sở dữ liệu | PostgreSQL 16 |
| Đóng gói | Docker, Harbor Registry |
| Triển khai | Kubernetes (bare-metal), Helm, ArgoCD |
| Reverse Proxy | Nginx (server gateway) |

Repository này (`order2bs-deploy`) **chỉ chứa cấu hình triển khai** — không chứa source code ứng dụng. Source code ứng dụng nằm ở repository [Order2bs](https://github.com/Anab821/Order2bs).

---

## 2. Kiến Trúc Hệ Thống

```
Internet
   │
   ▼
┌──────────────────────────────────┐
│   Nginx Reverse Proxy            │
│   192.168.100.161 (Gateway)     │
│   Domain: order2bs.2bsystem.     │
│           com.vn                 │
└──────────────┬───────────────────┘
               │ forward đến port 80
               ▼
┌──────────────────────────────────┐
│   Kubernetes Cluster             │
│   192.168.100.170                │
│                                  │
│  ┌─────────────────────────┐     │
│  │  NGINX Ingress           │     │
│  │  /api, /ws, /uploads     │──▶ backend-svc:8080
│  │  /                       │──▶ frontend-svc:80
│  └─────────────────────────┘     │
│                                  │
│  ┌──────────┐  ┌─────────────┐   │
│  │ Backend  │  │  Frontend   │   │
│  │  :8080   │  │   :80       │   │
│  └────┬─────┘  └─────────────┘   │
│       │                          │
│  ┌────▼──────────────────────┐   │
│  │  PostgreSQL :5432          │   │
│  │  (hostPath /data/...)      │   │
│  └───────────────────────────┘   │
└──────────────────────────────────┘
```

---

## 3. Cấu Trúc Thư Mục

```
order2bs-deploy/
├── .env                          # Biến môi trường cho các script
├── deploy.sh                     # Script build + push Docker images
├── deploy-full.sh                # Script full pipeline (build → push → git push → nginx)
├── rebuild.sh                    # Script build lại khi cần (không push git)
├── helm/
│   └── order2bs/
│       ├── Chart.yaml            # Metadata của Helm chart
│       ├── values.yaml           # Giá trị cấu hình mặc định
│       └── templates/
│           ├── namespace.yaml    # Tạo Kubernetes Namespace
│           ├── secrets.yaml      # ConfigMap và Secret (DB credentials, JWT, ...)
│           ├── postgres.yaml     # Deployment + Service cho PostgreSQL
│           └── ingress.yaml      # Ingress để expose backend/frontend ra ngoài
└── nginx/
    ├── order2bs.conf             # Cấu hình Nginx reverse proxy
    └── setup-nginx.sh            # Script đẩy cấu hình Nginx lên server gateway
```

---

## 4. Mô Tả Chi Tiết Từng Thành Phần

### 4.1 File `.env`

**Mục đích:** Lưu toàn bộ biến môi trường dùng chung cho các script deploy. File này **không được commit** lên git.

| Biến | Ví dụ | Mô tả |
|---|---|---|
| `HARBOR_REGISTRY` | `harbor.2bsystem.com.vn` | URL của private Docker registry (Harbor) |
| `HARBOR_PROJECT` | `order2bs` | Tên project trong Harbor |
| `HARBOR_USER` | `robot$order2bs+deploy-bot` | Tài khoản robot có quyền push image |
| `HARBOR_PASSWORD` | `VPnfz...` | Mật khẩu của robot account |
| `PROJECT_ROOT` | `/home/.../Order2bs` | Đường dẫn tuyệt đối đến source code |
| `REPO_URL` | `https://github.com/...` | URL git của repository source code |
| `APP_DOMAIN` | `order2bs.2bsystem.com.vn` | Domain chính của ứng dụng |

> ⚠️ **Lưu ý bảo mật:** File `.env` chứa mật khẩu thực. Đảm bảo file này đã được thêm vào `.gitignore`.

---

### 4.2 Script `deploy.sh`

**Mục đích:** Script deploy cơ bản — chỉ build và push Docker images, sau đó cập nhật `values.yaml`. Người dùng cần tự commit và push git để ArgoCD sync.

**Các bước thực hiện:**

| Bước | Hành động |
|---|---|
| 0 | Load biến từ `.env` |
| 1 | Đăng nhập vào Harbor Registry |
| 2 | Build Docker image cho **Backend** (Go) và push lên Harbor |
| 3 | Build Docker image cho **Frontend** (React) và push lên Harbor |
| 4 | Cập nhật `backendTag` và `frontendTag` trong `values.yaml` bằng tag mới |

**Quy tắc đặt tag image:**

```
TAG = <ngày>-<branch>-<git-short-sha>
Ví dụ: 20260425-main-0d76410
```

**Cách sử dụng:**

```bash
# Deploy từ branch main (mặc định)
bash deploy.sh

# Deploy từ branch cụ thể
bash deploy.sh develop
```

---

### 4.3 Script `deploy-full.sh`

**Mục đích:** Pipeline tự động hoàn chỉnh — thực hiện toàn bộ luồng từ build đến cập nhật Nginx.

**Các bước thực hiện:**

| Bước | Hành động |
|---|---|
| 0 | Đăng nhập Harbor |
| 1 | Build & Push Backend Docker image |
| 2 | Build & Push Frontend Docker image (kèm build-arg `VITE_API_URL`, `VITE_WS_URL`) |
| 3 | Cập nhật `values.yaml` với tag mới và domain mới |
| 4 | `git commit` + `git push` → trigger ArgoCD tự động sync |
| 5 | Đẩy cấu hình Nginx lên server gateway `192.168.100.161` |

> 💡 Bước 2 truyền `VITE_API_URL` và `VITE_WS_URL` qua `--build-arg` để frontend biết địa chỉ API và WebSocket khi build production.

**Cách sử dụng:**

```bash
bash deploy-full.sh          # Deploy branch main
bash deploy-full.sh develop  # Deploy branch develop
```

---

### 4.4 Helm Chart

#### 4.4.1 `Chart.yaml` — Metadata của Chart

```yaml
name: order2bs
description: A Helm chart for Order2bs Food Ordering System
version: 0.1.0
appVersion: "1.0.0"
```

Đây là file mô tả Helm chart. Khi đóng gói hoặc publish chart, Helm sẽ đọc thông tin từ file này.

---

#### 4.4.2 `values.yaml` — Giá Trị Cấu Hình

File trung tâm chứa **toàn bộ cấu hình có thể tùy chỉnh** của Helm chart. Các script deploy sẽ tự động cập nhật file này.

```yaml
backend:
  repository: harbor.2bsystem.com.vn/order2bs/backend
  backendTag: "20260425-main-0d76410"   # ← Script tự động cập nhật
  replicaCount: 1
  service:
    port: 8080
  resources:
    limits:
      cpu: 500m
      memory: 512Mi

frontend:
  repository: harbor.2bsystem.com.vn/order2bs/frontend
  frontendTag: "20260425-main-0d76410"  # ← Script tự động cập nhật
  replicaCount: 1
  service:
    port: 80

database:
  enabled: true
  image: postgres:16-alpine
  storage: 1Gi

ingress:
  enabled: true
  className: nginx
  host: order2bs.2bsystem.com.vn        # ← Script tự động cập nhật
  tls: false
```

---

#### 4.4.3 `templates/namespace.yaml` — Kubernetes Namespace

**Mục đích:** Tạo một Namespace riêng biệt để cô lập toàn bộ tài nguyên của dự án Order2bs trong cluster.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: {{ .Release.Namespace }}
  labels:
    name: {{ .Release.Namespace }}
```

> Namespace được truyền vào khi cài Helm, ví dụ: `helm install order2bs ./helm/order2bs -n order2bsbs --create-namespace`.

---

#### 4.4.4 `templates/secrets.yaml` — ConfigMap và Secret

File này tạo **2 tài nguyên Kubernetes**:

**1. ConfigMap (`order2bs-config`)** — lưu cấu hình không nhạy cảm:

| Key | Giá trị | Mô tả |
|---|---|---|
| `APP_ENV` | `production` | Môi trường chạy ứng dụng |
| `APP_PORT` | `8080` | Port của backend |
| `DB_HOST` | `order2bs-postgres` | Hostname của PostgreSQL (tên Service trong K8s) |
| `DB_PORT` | `5432` | Port PostgreSQL |
| `DB_NAME` | `lunchorder` | Tên database |
| `DB_USER` | `postgres` | Tên user database |
| `DB_SSLMODE` | `disable` | Tắt SSL (môi trường nội bộ) |
| `VITE_API_URL` | `https://<domain>` | URL API cho frontend |
| `CORS_ORIGIN` | `https://<domain>` | Nguồn được phép gọi CORS |

**2. Secret (`order2bs-secrets`)** — lưu thông tin nhạy cảm (mã hóa Base64):

| Key | Mô tả |
|---|---|
| `DB_PASSWORD` | Mật khẩu PostgreSQL |
| `JWT_SECRET` | Khóa bí mật để ký JWT token |

> ⚠️ **Lưu ý:** Hiện tại `DB_PASSWORD` và `JWT_SECRET` đang dùng giá trị mặc định (`postgres`, `supersecret`). Cần thay bằng giá trị thực trong môi trường production.

---

#### 4.4.5 `templates/postgres.yaml` — PostgreSQL Deployment & Service

**Mục đích:** Triển khai cơ sở dữ liệu PostgreSQL trong Kubernetes.

**Chi tiết cấu hình:**

| Thông số | Giá trị | Mô tả |
|---|---|---|
| `kind` | `Deployment` | Dùng Deployment thay vì StatefulSet vì lưu trữ qua hostPath |
| `strategy.type` | `Recreate` | Đảm bảo chỉ 1 pod ghi vào hostPath tại một thời điểm |
| `image` | `postgres:16-alpine` | Phiên bản PostgreSQL nhẹ |
| `containerPort` | `5432` | Port PostgreSQL tiêu chuẩn |
| `POSTGRES_DB` | `lunchorder` | Tên database được tạo tự động |
| `POSTGRES_USER` | `postgres` | Tên superuser |
| `POSTGRES_PASSWORD` | Lấy từ Secret | Mật khẩu đọc từ `order2bs-secrets` |
| `PGDATA` | `/var/lib/postgresql/data/pgdata` | Phải là subdirectory của mountPath |
| Volume | `hostPath` | Lưu dữ liệu trực tiếp tại `/data/order2bs-postgres` trên node |

**Lý do dùng hostPath thay vì PVC:**
> Cluster bare-metal không được cài StorageClass mặc định nên không thể dùng `PersistentVolumeClaim` động. `hostPath` gắn trực tiếp vào thư mục trên node worker `192.168.100.170`.

**Init Container:**
- Tên: `init-pgdata`
- Hình ảnh: `busybox:1.36`
- Nhiệm vụ: Tạo thư mục `/data/order2bs-postgres` và cấp quyền `777` trước khi PostgreSQL khởi động.

**Health Checks:**

| Probe | Lệnh kiểm tra | Thời gian chờ khởi đầu |
|---|---|---|
| `readinessProbe` | `pg_isready -U postgres -d lunchorder` | 15 giây |
| `livenessProbe` | `pg_isready -U postgres` | 30 giây |

**Service PostgreSQL:**
- Loại: `ClusterIP` (chỉ truy cập được từ trong cluster)
- Port: `5432`

---

#### 4.4.6 `templates/ingress.yaml` — Kubernetes Ingress

**Mục đích:** Định tuyến HTTP request từ bên ngoài vào đúng Service backend hoặc frontend trong cluster.

**Ingress Controller:** NGINX Ingress Controller

**Các annotation được cấu hình:**

| Annotation | Giá trị | Mô tả |
|---|---|---|
| `proxy-body-size` | `10m` | Giới hạn kích thước tệp upload tối đa 10MB |
| `proxy-read-timeout` | `600` | Timeout đọc response 600 giây (hỗ trợ request dài) |
| `proxy-send-timeout` | `600` | Timeout gửi request 600 giây |
| `proxy-connect-timeout` | `60` | Timeout kết nối 60 giây |
| `enable-cors` | `true` | Bật hỗ trợ CORS |
| `cors-allow-origin` | `https://<domain>` | Chỉ cho phép origin từ domain chính |
| `cors-allow-methods` | `GET, POST, PUT, PATCH, DELETE, OPTIONS` | Các HTTP method được phép |
| `cors-allow-headers` | `Authorization, Content-Type` | Các header được phép |
| `cors-allow-credentials` | `true` | Cho phép gửi cookie/credentials |

**Quy tắc định tuyến (Routing Rules):**

| Path | Service đích | Port | Mô tả |
|---|---|---|---|
| `/api` | `backend-svc` | `8080` | Toàn bộ API REST |
| `/ws` | `backend-svc` | `8080` | Kết nối WebSocket |
| `/uploads` | `backend-svc` | `8080` | File upload/download |
| `/` | `frontend-svc` | `80` | Giao diện người dùng (SPA React) |

---

### 4.5 Nginx Reverse Proxy

#### 4.5.1 `nginx/order2bs.conf` — Cấu Hình Nginx Gateway

**Mục đích:** Nginx chạy trên server gateway (`192.168.100.161`) đóng vai trò **reverse proxy** — nhận request từ Internet và chuyển tiếp vào Kubernetes Ingress trên `192.168.100.170:80`.

**Upstream:**

```nginx
upstream k8s_ingress {
    server 192.168.100.170:80;
    keepalive 64;
}
```

> `keepalive 64` giữ tối đa 64 kết nối idle đến K8s Ingress, giúp giảm overhead tạo kết nối TCP mới.

**Server Block 1 — HTTP (port 80):**
- Lắng nghe tất cả request HTTP trên domain `order2bs.2bsystem.com.vn`
- Chuyển hướng 301 toàn bộ sang HTTPS

**Server Block 2 — HTTPS (port 443):**

| Cấu hình | Chi tiết |
|---|---|
| Giao thức TLS | TLSv1.2, TLSv1.3 |
| SSL session cache | 10 phút, 10MB bộ nhớ |
| Kích thước request tối đa | 10MB |
| Timeout connect/send/read | 60s / 600s / 600s |

**Security Headers:**

| Header | Giá trị | Mục đích |
|---|---|---|
| `X-Frame-Options` | `SAMEORIGIN` | Chống clickjacking |
| `X-Content-Type-Options` | `nosniff` | Chống MIME sniffing |
| `X-XSS-Protection` | `1; mode=block` | Bật XSS filter trình duyệt |

**Định tuyến trong Nginx:**

| Location | Hành động | Ghi chú |
|---|---|---|
| `/ws` | forward đến `k8s_ingress` với upgrade header | Hỗ trợ WebSocket, timeout 3600s |
| `/api`, `/uploads` | forward đến `k8s_ingress` | API và file |
| `/` | forward đến `k8s_ingress` | Giao diện frontend (SPA) |

---

#### 4.5.2 `nginx/setup-nginx.sh` — Script Cập Nhật Cấu Hình Nginx

**Mục đích:** Tự động copy file `order2bs.conf` lên server gateway `192.168.100.161` qua SSH và reload Nginx.

Script này được gọi tự động ở **Bước 5** của `deploy-full.sh`.

---

## 5. Luồng Triển Khai (CI/CD)

```
Developer máy local
       │
       │ bash deploy-full.sh
       ▼
┌─────────────────────────────────┐
│ 1. docker build backend         │
│ 2. docker push → Harbor         │
│ 3. docker build frontend        │
│    (với VITE_API_URL, VITE_WS)  │
│ 4. docker push → Harbor         │
│ 5. Cập nhật values.yaml (tag)   │
│ 6. git commit + git push        │
└──────────────┬──────────────────┘
               │ webhook / polling
               ▼
     ┌──────────────────┐
     │     ArgoCD        │
     │  (tự động sync)   │
     └────────┬─────────┘
              │ helm upgrade
              ▼
     ┌──────────────────┐
     │  Kubernetes       │
     │  Cluster          │
     │  (K8s resources   │
     │   được cập nhật)  │
     └──────────────────┘
```

**ArgoCD** theo dõi repository `order2bs-deploy`. Mỗi khi có commit mới (cập nhật tag image), ArgoCD tự động phát hiện và chạy `helm upgrade` để cập nhật các Pod lên image mới — không cần can thiệp thủ công.

---

## 6. Hướng Dẫn Sử Dụng

### Lần đầu cài đặt

```bash
# 1. Clone deploy repository
git clone https://github.com/Anab821/order2bs-deploy.git
cd order2bs-deploy

# 2. Tạo và điền file .env
cp .env.example .env   # hoặc tạo mới
nano .env

# 3. Đảm bảo kubectl đang kết nối đúng cluster
kubectl config current-context

# 4. Cài Helm chart lần đầu (qua ArgoCD hoặc thủ công)
helm install order2bs ./helm/order2bs \
  -n order2bsbs \
  --create-namespace
```

### Deploy phiên bản mới

```bash
# Sử dụng pipeline đầy đủ (khuyến nghị)
bash deploy-full.sh

# Hoặc chỉ build & push images, tự commit sau
bash deploy.sh
git add helm/order2bs/values.yaml
git commit -m "deploy: <mô tả>"
git push origin main
```

### Kiểm tra trạng thái sau deploy

```bash
# Xem các Pod đang chạy
kubectl get pods -n order2bsbs

# Xem logs backend
kubectl logs -n order2bsbs deployment/order2bs-backend -f

# Xem logs frontend
kubectl logs -n order2bsbs deployment/order2bs-frontend -f

# Xem trạng thái PostgreSQL
kubectl exec -n order2bsbs deployment/order2bs-postgres -- pg_isready -U postgres
```

---

## 7. Lưu Ý Bảo Mật

| Vấn đề | Khuyến Nghị |
|---|---|
| File `.env` chứa mật khẩu | Thêm vào `.gitignore`, không bao giờ commit |
| `DB_PASSWORD` mặc định là `postgres` | Đổi sang mật khẩu mạnh trong production |
| `JWT_SECRET` mặc định là `supersecret` | Thay bằng chuỗi ngẫu nhiên ≥ 32 ký tự |
| TLS/HTTPS | Hiện `ingress.tls: false` — nên bật và cấu hình cert thực |
| `hostPath` volume | Gắn chặt với 1 node, không có HA — cân nhắc dùng NFS hoặc Longhorn |
| Harbor robot account | Chỉ cấp quyền push/pull cho project `order2bs`, không cấp quyền admin |

---

## 8. Xuất Tài Liệu Ra File DOCX

Sử dụng **Pandoc** để chuyển đổi file Markdown này sang DOCX hoặc PDF:

```bash
# Cài đặt Pandoc (nếu chưa có)
sudo apt-get install -y pandoc

# Xuất ra DOCX
pandoc DOCUMENTATION.md -o Order2bs_Documentation.docx

# Xuất ra PDF (cần cài thêm LaTeX)
pandoc DOCUMENTATION.md -o Order2bs_Documentation.pdf

# Xuất ra DOCX với template tùy chỉnh
pandoc DOCUMENTATION.md --reference-doc=template.docx -o Order2bs_Documentation.docx
```

> 💡 Bạn cũng có thể dùng extension **Markdown PDF** trong VS Code để xuất trực tiếp mà không cần cài Pandoc.

---

*Tài liệu được tạo tự động bởi Antigravity — AI Coding Assistant.*
