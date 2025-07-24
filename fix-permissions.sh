#!/bin/bash
# 권한 문제 해결 스크립트

echo "🔧 권한 문제 해결 스크립트"
echo "========================"
echo ""

PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
SA_NAME="veo-token-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
FUNCTION_NAME="veo-token-updater"
REGION="us-central1"

echo "프로젝트: $PROJECT_ID ($PROJECT_NUMBER)"
echo ""

# 1. Cloud Scheduler 서비스 계정 권한 추가
echo "📋 Cloud Scheduler 서비스 계정 권한 설정..."
SCHEDULER_SA="service-${PROJECT_NUMBER}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"

# Cloud Function invoker 권한 부여
echo "- Cloud Function 호출 권한 부여..."
gcloud functions add-iam-policy-binding $FUNCTION_NAME \
    --region=$REGION \
    --member="serviceAccount:${SCHEDULER_SA}" \
    --role="roles/cloudfunctions.invoker" \
    --quiet 2>/dev/null || {
    echo "Gen2 함수로 시도..."
    gcloud run services add-iam-policy-binding $FUNCTION_NAME \
        --region=$REGION \
        --member="serviceAccount:${SCHEDULER_SA}" \
        --role="roles/run.invoker" \
        --quiet
}

# 2. 서비스 계정 권한 재확인
echo ""
echo "🔐 서비스 계정 권한 재설정..."
for role in "roles/aiplatform.user" "roles/editor" "roles/sheets.editor"; do
    echo "- $role 권한 부여..."
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="$role" \
        --quiet
done

# 3. Cloud Functions 서비스 계정에도 권한 부여
echo ""
echo "☁️ Cloud Functions 서비스 계정 권한..."
CF_SA="${PROJECT_ID}@appspot.gserviceaccount.com"
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${CF_SA}" \
    --role="roles/cloudfunctions.invoker" \
    --quiet

# 4. 기본 서비스 계정 권한 (있는 경우)
DEFAULT_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
if gcloud iam service-accounts describe $DEFAULT_SA >/dev/null 2>&1; then
    echo ""
    echo "🔧 기본 서비스 계정 권한..."
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${DEFAULT_SA}" \
        --role="roles/cloudfunctions.invoker" \
        --quiet
fi

# 5. 스케줄러 작업 재생성
echo ""
echo "⏰ Cloud Scheduler 재설정..."
FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME --region=$REGION --gen2 --format="value(serviceConfig.uri)" 2>/dev/null || \
               gcloud functions describe $FUNCTION_NAME --region=$REGION --format="value(httpsTrigger.url)")

# 기존 작업 삭제
gcloud scheduler jobs delete veo-token-refresh --location=$REGION --quiet 2>/dev/null || true

# 새 작업 생성
gcloud scheduler jobs create http veo-token-refresh \
    --location=$REGION \
    --schedule="*/30 * * * *" \
    --uri=$FUNCTION_URL \
    --http-method=GET \
    --time-zone="Asia/Seoul" \
    --oidc-service-account-email=$SCHEDULER_SA \
    --quiet

echo ""
echo "✅ 권한 설정 완료!"
echo ""
echo "🧪 테스트 방법:"
echo "1. Cloud Scheduler 수동 실행:"
echo "   gcloud scheduler jobs run veo-token-refresh --location=$REGION"
echo ""
echo "2. Cloud Function 직접 호출:"
echo "   curl $FUNCTION_URL"
echo ""
echo "⚠️ Google Sheets 권한도 확인하세요:"
echo "   스프레드시트 → 공유 → $SA_EMAIL (편집자 권한)"