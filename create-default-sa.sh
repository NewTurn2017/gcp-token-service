#!/bin/bash
# 기본 서비스 계정 생성 스크립트

echo "🔧 기본 서비스 계정 생성 스크립트"
echo "================================"
echo ""

PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
DEFAULT_SA_EMAIL="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "프로젝트: $PROJECT_ID"
echo "프로젝트 번호: $PROJECT_NUMBER"
echo "기본 서비스 계정: $DEFAULT_SA_EMAIL"
echo ""

# 1. Compute Engine API 활성화
echo "1. Compute Engine API 활성화 중..."
gcloud services enable compute.googleapis.com --quiet

# 2. 기본 서비스 계정 수동 생성
echo ""
echo "2. 기본 서비스 계정 생성 시도..."

# 옵션 1: beta identity create
echo "   방법 1: Service Identity 생성..."
gcloud beta services identity create \
    --service=compute.googleapis.com \
    --project=$PROJECT_ID \
    --quiet 2>/dev/null || echo "   (실패 또는 이미 존재)"

# 옵션 2: 수동으로 서비스 계정 생성
echo "   방법 2: 수동 서비스 계정 생성..."
gcloud iam service-accounts create "${PROJECT_NUMBER}-compute" \
    --display-name="Compute Engine default service account" \
    --project=$PROJECT_ID \
    --quiet 2>/dev/null || echo "   (실패 또는 이미 존재)"

# 3. 브라우저로 Compute Engine 활성화
echo ""
echo "3. 브라우저에서 Compute Engine 페이지 방문"
echo "   다음 URL을 브라우저에서 열어주세요:"
echo ""
echo "   https://console.cloud.google.com/compute/instances?project=$PROJECT_ID"
echo ""
echo "   페이지가 로드되면 기본 서비스 계정이 자동 생성됩니다."
echo "   완료 후 Enter를 누르세요..."
read

# 4. 서비스 계정 확인
echo ""
echo "4. 서비스 계정 확인 중..."
if gcloud iam service-accounts describe $DEFAULT_SA_EMAIL >/dev/null 2>&1; then
    echo "✅ 기본 서비스 계정이 존재합니다!"
    
    # 필요한 권한 부여
    echo ""
    echo "5. 권한 부여 중..."
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${DEFAULT_SA_EMAIL}" \
        --role="roles/cloudbuild.builds.builder" \
        --quiet
    
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${DEFAULT_SA_EMAIL}" \
        --role="roles/editor" \
        --quiet
    
    echo "✅ 권한 부여 완료"
    echo ""
    echo "이제 다시 배포를 시도하세요:"
    echo "./complete-setup.sh"
else
    echo "❌ 기본 서비스 계정이 아직 생성되지 않았습니다."
    echo ""
    echo "대안: 수동으로 Cloud Console에서 함수를 배포하거나"
    echo "      App Engine 기반 솔루션을 사용하세요."
fi