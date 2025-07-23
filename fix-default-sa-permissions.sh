#!/bin/bash
# 기본 서비스 계정 권한 수정 스크립트

echo "🔧 기본 서비스 계정 권한 수정"
echo "============================"
echo ""

PROJECT_ID="warmtalentai"
PROJECT_NUMBER="227871897464"
DEFAULT_SA_EMAIL="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "프로젝트: $PROJECT_ID"
echo "기본 서비스 계정: $DEFAULT_SA_EMAIL"
echo ""

# 1. 서비스 계정이 비활성화되어 있는지 확인
echo "1. 서비스 계정 상태 확인..."
SA_STATUS=$(gcloud iam service-accounts describe $DEFAULT_SA_EMAIL --format="value(disabled)" 2>/dev/null)

if [ "$SA_STATUS" == "True" ]; then
    echo "⚠️  서비스 계정이 비활성화되어 있습니다. 활성화 중..."
    gcloud iam service-accounts enable $DEFAULT_SA_EMAIL
    echo "✅ 서비스 계정 활성화 완료"
else
    echo "✅ 서비스 계정이 이미 활성화되어 있습니다"
fi
echo ""

# 2. 필수 권한 부여
echo "2. 필수 권한 부여..."

# Editor 권한
echo "   - Editor 권한 부여..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${DEFAULT_SA_EMAIL}" \
    --role="roles/editor" \
    --quiet

# Service Account User 권한
echo "   - Service Account User 권한 부여..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${DEFAULT_SA_EMAIL}" \
    --role="roles/iam.serviceAccountUser" \
    --quiet

# Cloud Functions Developer 권한
echo "   - Cloud Functions Developer 권한 부여..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${DEFAULT_SA_EMAIL}" \
    --role="roles/cloudfunctions.developer" \
    --quiet

echo "✅ 권한 부여 완료"
echo ""

# 3. Cloud Functions 서비스 에이전트 권한 설정
echo "3. Cloud Functions 서비스 에이전트 설정..."
CF_AGENT="service-${PROJECT_NUMBER}@gcf-admin-robot.iam.gserviceaccount.com"

# Cloud Functions 서비스 에이전트가 기본 SA를 사용할 수 있도록 권한 부여
gcloud iam service-accounts add-iam-policy-binding $DEFAULT_SA_EMAIL \
    --member="serviceAccount:${CF_AGENT}" \
    --role="roles/iam.serviceAccountUser" \
    --quiet 2>/dev/null || true

echo "✅ 서비스 에이전트 설정 완료"
echo ""

# 4. Cloud Build 권한 설정
echo "4. Cloud Build 권한 설정..."
CB_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${CB_SA}" \
    --role="roles/cloudfunctions.developer" \
    --quiet 2>/dev/null || true

echo "✅ Cloud Build 권한 설정 완료"
echo ""

# 5. API 재활성화 (권한 갱신)
echo "5. API 상태 갱신..."
gcloud services disable cloudfunctions.googleapis.com --force --quiet 2>/dev/null || true
sleep 5
gcloud services enable cloudfunctions.googleapis.com --quiet
echo "✅ API 갱신 완료"
echo ""

echo "🎉 모든 설정이 완료되었습니다!"
echo ""
echo "이제 다시 배포를 시도해보세요:"
echo "./deploy-gen2-final.sh"