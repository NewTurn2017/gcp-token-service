#!/bin/bash
# 기본 서비스 계정 문제 해결 스크립트

echo "🔧 Google Cloud 기본 서비스 계정 복구 스크립트"
echo "==========================================="
echo ""

# 프로젝트 ID 확인
PROJECT_ID=$(gcloud config get-value project)
if [ -z "$PROJECT_ID" ]; then
    echo "프로젝트 ID를 입력하세요:"
    read PROJECT_ID
    gcloud config set project $PROJECT_ID
fi

echo "프로젝트: $PROJECT_ID"
echo ""

# 프로젝트 번호 가져오기
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
DEFAULT_SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "기본 서비스 계정: $DEFAULT_SERVICE_ACCOUNT"
echo ""

# API 활성화
echo "1. 필수 API 활성화 중..."
gcloud services enable compute.googleapis.com iam.googleapis.com --quiet

# 서비스 계정 생성 시도
echo ""
echo "2. 기본 서비스 계정 생성 시도..."

# 방법 1: beta 명령으로 서비스 아이덴티티 생성
echo "   방법 1: 서비스 아이덴티티 생성..."
gcloud beta services identity create --service=compute.googleapis.com --quiet || echo "   (이미 존재하거나 실패)"

# 방법 2: 기본 서비스 계정 수동 생성
echo "   방법 2: 수동으로 서비스 계정 생성..."
gcloud iam service-accounts create "compute" \
    --display-name="Compute Engine default service account" \
    --quiet 2>/dev/null || echo "   (이미 존재하거나 실패)"

# 방법 3: Cloud Console 방문 권장
echo ""
echo "3. Cloud Console에서 Compute Engine 활성화"
echo "   다음 링크를 브라우저에서 열어주세요:"
echo "   https://console.cloud.google.com/compute/instances?project=$PROJECT_ID"
echo "   "
echo "   페이지가 로드되면 자동으로 기본 서비스 계정이 생성됩니다."
echo ""
echo "   완료하셨으면 Enter를 누르세요..."
read

# 서비스 계정 확인
echo ""
echo "4. 서비스 계정 상태 확인..."
if gcloud iam service-accounts describe $DEFAULT_SERVICE_ACCOUNT >/dev/null 2>&1; then
    echo "✅ 기본 서비스 계정이 성공적으로 생성되었습니다!"
    
    # 필요한 권한 부여
    echo ""
    echo "5. 권한 부여 중..."
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${DEFAULT_SERVICE_ACCOUNT}" \
        --role="roles/editor" \
        --quiet
    
    echo "✅ 권한 부여 완료"
else
    echo "❌ 기본 서비스 계정이 아직 생성되지 않았습니다."
    echo ""
    echo "대안: Veo 서비스 계정 사용"
    echo "설치 스크립트가 자동으로 Veo 서비스 계정을 사용하도록 설정됩니다."
fi

echo ""
echo "🎯 다음 단계:"
echo "1. 설치 스크립트를 다시 실행하세요:"
echo "   ./setup.sh"
echo ""
echo "2. 여전히 문제가 있다면 이 명령을 실행하세요:"
echo "   gcloud projects add-iam-policy-binding $PROJECT_ID \\"
echo "     --member=\"user:$(gcloud config get-value account)\" \\"
echo "     --role=\"roles/iam.serviceAccountUser\""