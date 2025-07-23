#!/bin/bash
# 기본 서비스 계정 없이 Cloud Function 배포하는 스크립트

echo "🚀 Cloud Function 배포 (기본 서비스 계정 우회)"
echo "=========================================="
echo ""

# 프로젝트 설정
PROJECT_ID=${PROJECT_ID:-$(gcloud config get-value project)}
if [ -z "$PROJECT_ID" ]; then
    echo -n "프로젝트 ID 입력: "
    read PROJECT_ID
fi

echo "프로젝트: $PROJECT_ID"
echo ""

# 서비스 계정 이메일
SERVICE_ACCOUNT_EMAIL="veo-token-sa@${PROJECT_ID}.iam.gserviceaccount.com"
echo "서비스 계정: $SERVICE_ACCOUNT_EMAIL"
echo ""

# 서비스 계정 키 파일 확인
KEY_FILE="$HOME/veo-key.json"
if [ ! -f "$KEY_FILE" ]; then
    echo "❌ 서비스 계정 키 파일을 찾을 수 없습니다: $KEY_FILE"
    echo "먼저 설치 스크립트를 실행하세요."
    exit 1
fi

# 스프레드시트 ID 입력
if [ -z "$SPREADSHEET_ID" ]; then
    echo -n "Google Sheets ID 입력: "
    read SPREADSHEET_ID
fi

echo ""
echo "준비 완료! 배포를 시작합니다..."
echo ""

# 1. Cloud Build 서비스 계정에 권한 부여
echo "1. Cloud Build 권한 설정..."
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
CLOUD_BUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

# Cloud Build 서비스 계정에 필요한 권한 부여
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/cloudfunctions.developer" \
    --quiet

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/iam.serviceAccountUser" \
    --quiet

echo "✅ Cloud Build 권한 설정 완료"
echo ""

# 2. 서비스 계정 JSON을 Base64로 인코딩
echo "2. 서비스 계정 키 인코딩..."
SERVICE_ACCOUNT_JSON_BASE64=$(cat "$KEY_FILE" | base64 -w 0)
echo "✅ 인코딩 완료"
echo ""

# 3. 소스 코드 준비
echo "3. 소스 코드 준비..."
SOURCE_DIR="./cloud-function-v2"
if [ ! -d "$SOURCE_DIR" ]; then
    echo "소스 코드를 다운로드합니다..."
    mkdir -p $SOURCE_DIR
    
    curl -sL https://raw.githubusercontent.com/NewTurn2017/gcp-token-service/main/cloud-function-v2/main.py \
        -o $SOURCE_DIR/main.py
    
    curl -sL https://raw.githubusercontent.com/NewTurn2017/gcp-token-service/main/cloud-function-v2/requirements.txt \
        -o $SOURCE_DIR/requirements.txt
fi
echo "✅ 소스 코드 준비 완료"
echo ""

# 4. Cloud Function 배포 (1세대로 시도)
echo "4. Cloud Function 배포 중..."
echo "   (기본 서비스 계정을 우회하기 위해 1세대 함수로 배포)"
echo ""

FUNCTION_NAME="veo-token-updater"
REGION="us-central1"

# 기존 함수가 있다면 삭제
gcloud functions delete $FUNCTION_NAME --region=$REGION --quiet 2>/dev/null || true

# 1세대 Cloud Function으로 배포
gcloud functions deploy $FUNCTION_NAME \
    --runtime=python311 \
    --region=$REGION \
    --source=$SOURCE_DIR \
    --entry-point=update_token \
    --trigger-http \
    --allow-unauthenticated \
    --service-account=$SERVICE_ACCOUNT_EMAIL \
    --set-env-vars="SERVICE_ACCOUNT_JSON_BASE64=${SERVICE_ACCOUNT_JSON_BASE64},SPREADSHEET_ID=${SPREADSHEET_ID}" \
    --memory=256MB \
    --timeout=60s \
    --no-gen2

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Cloud Function 배포 성공!"
    
    # Function URL 가져오기
    FUNCTION_URL="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}"
    
    echo ""
    echo "📊 Google Sheets:"
    echo "   https://docs.google.com/spreadsheets/d/$SPREADSHEET_ID"
    echo ""
    echo "☁️  Function URL:"
    echo "   $FUNCTION_URL"
    echo ""
    echo "🧪 테스트:"
    echo "   curl $FUNCTION_URL"
    
    # 테스트 실행
    echo ""
    echo "테스트 실행 중..."
    curl -s $FUNCTION_URL | jq '.' || curl -s $FUNCTION_URL
    
else
    echo ""
    echo "❌ 배포 실패"
    echo ""
    echo "다음을 시도해보세요:"
    echo ""
    echo "1. Cloud Console에서 직접 배포:"
    echo "   https://console.cloud.google.com/functions/add?project=$PROJECT_ID"
    echo ""
    echo "2. 다음 권한 추가:"
    echo "   gcloud projects add-iam-policy-binding $PROJECT_ID \\"
    echo "     --member=\"serviceAccount:${SERVICE_ACCOUNT_EMAIL}\" \\"
    echo "     --role=\"roles/cloudfunctions.serviceAgent\""
fi