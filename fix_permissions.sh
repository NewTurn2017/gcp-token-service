#!/bin/bash

# Veo 3.0 및 Vertex AI API 권한 문제 해결 스크립트

set -e

echo "🔧 GCP 권한 문제 해결 스크립트"
echo "==============================="

# 프로젝트 ID 가져오기
PROJECT_ID=$(gcloud config get-value project)
if [ -z "$PROJECT_ID" ]; then
    echo "❌ Error: 프로젝트가 설정되지 않았습니다."
    echo "실행: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

echo "📋 프로젝트: $PROJECT_ID"
echo ""

# 프로젝트 정보 가져오기
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
CLOUDBUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
CLOUDRUN_SA="${PROJECT_NUMBER}@gcp-sa-run.iam.gserviceaccount.com"

echo "🔍 서비스 계정 확인:"
echo "  - Compute Engine: $COMPUTE_SA"
echo "  - Cloud Build: $CLOUDBUILD_SA"
echo "  - Cloud Run: $CLOUDRUN_SA"
echo ""

# API 활성화 확인
echo "1️⃣ 필수 API 활성화 중..."
gcloud services enable \
    aiplatform.googleapis.com \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    compute.googleapis.com \
    artifactregistry.googleapis.com \
    iam.googleapis.com \
    --quiet

echo "✅ API 활성화 완료"
echo ""

# IAM 권한 부여
echo "2️⃣ IAM 권한 설정 중..."

# Compute Engine 기본 서비스 계정 권한
echo "  - Compute Engine 서비스 계정 권한 설정..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/aiplatform.user" \
    --quiet

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/aiplatform.predictor" \
    --quiet

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/storage.objectViewer" \
    --quiet

# Cloud Build 서비스 계정 권한
echo "  - Cloud Build 서비스 계정 권한 설정..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${CLOUDBUILD_SA}" \
    --role="roles/run.admin" \
    --quiet

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${CLOUDBUILD_SA}" \
    --role="roles/iam.serviceAccountUser" \
    --quiet

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${CLOUDBUILD_SA}" \
    --role="roles/storage.admin" \
    --quiet

# Cloud Run 서비스 계정 권한 (존재하는 경우)
echo "  - Cloud Run 서비스 계정 권한 설정..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${CLOUDRUN_SA}" \
    --role="roles/aiplatform.user" \
    --quiet || true

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${CLOUDRUN_SA}" \
    --role="roles/aiplatform.predictor" \
    --quiet || true

echo "✅ IAM 권한 설정 완료"
echo ""

# 현재 권한 확인
echo "3️⃣ 현재 권한 확인..."
echo ""
echo "Compute Engine 서비스 계정 역할:"
gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:${COMPUTE_SA}" \
    --format="table(bindings.role)" | grep -E "(aiplatform|storage)" || echo "  권한 없음"

echo ""

# Veo 3.0 할당량 확인
echo "4️⃣ Veo 3.0 사용 가능 여부 확인..."
echo "  ⚠️  Veo 3.0은 제한된 미리보기 기능입니다."
echo "  사용하려면 Google Cloud 콘솔에서 할당량을 요청해야 할 수 있습니다."
echo ""

# 테스트 권한
echo "5️⃣ 권한 테스트..."
echo "  다음 명령으로 토큰 생성을 테스트할 수 있습니다:"
echo ""
echo "  # 기본 토큰 테스트"
echo "  gcloud auth print-access-token"
echo ""
echo "  # Vertex AI 권한 테스트"
echo "  gcloud ai models list --region=us-central1"
echo ""

# 추가 도움말
echo "📝 추가 도움말:"
echo ""
echo "1. Cloud Run 서비스가 이미 배포된 경우:"
echo "   gcloud run services update get-gcp-token \\"
echo "     --service-account=${COMPUTE_SA} \\"
echo "     --region=asia-northeast3"
echo ""
echo "2. 특정 사용자에게 권한 부여:"
echo "   gcloud projects add-iam-policy-binding $PROJECT_ID \\"
echo "     --member='user:YOUR_EMAIL' \\"
echo "     --role='roles/aiplatform.user'"
echo ""
echo "3. Veo 3.0 할당량 요청:"
echo "   https://console.cloud.google.com/iam-admin/quotas"
echo "   'Vertex AI API' → 'Veo video generation requests per minute' 검색"
echo ""

echo "✨ 권한 설정 완료!"
echo "이제 setup.sh를 실행하여 서비스를 배포할 수 있습니다."