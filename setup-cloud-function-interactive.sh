#!/bin/bash
# Cloud Functions 기반 Veo 토큰 시스템 대화형 설치 스크립트

set -e

echo "🚀 Cloud Functions 기반 Veo 토큰 시스템 설치"
echo "============================================"
echo ""
echo "이 스크립트는 다음을 자동으로 설정합니다:"
echo "✓ Google Cloud 서비스 계정 생성"
echo "✓ 필요한 권한 자동 부여"
echo "✓ Cloud Function 배포"
echo "✓ 매시간 토큰 자동 갱신"
echo ""
echo "준비물:"
echo "• Google Cloud 프로젝트"
echo "• Google Sheets 계정"
echo ""
echo "시작하려면 Enter를 누르세요..."
read

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# TTY 리다이렉션으로 대화형 입력 활성화
exec < /dev/tty

# 1. 프로젝트 ID 확인 또는 입력
echo "📋 Step 1: Google Cloud 프로젝트 설정"
echo "====================================="
echo ""

# 현재 프로젝트 확인
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
if [ ! -z "$CURRENT_PROJECT" ]; then
    echo -e "현재 설정된 프로젝트: ${GREEN}$CURRENT_PROJECT${NC}"
    echo -n "이 프로젝트를 사용하시겠습니까? (Y/n): "
    read USE_CURRENT
    if [[ ! "$USE_CURRENT" =~ ^[Nn]$ ]]; then
        PROJECT_ID=$CURRENT_PROJECT
    fi
fi

# 프로젝트 ID 입력
if [ -z "$PROJECT_ID" ]; then
    echo ""
    echo -e "${YELLOW}Google Cloud 프로젝트 ID를 입력하세요:${NC}"
    echo "프로젝트 ID는 Google Cloud Console에서 확인할 수 있습니다."
    echo -n "Project ID: "
    read PROJECT_ID
    
    if [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}❌ 프로젝트 ID가 필요합니다${NC}"
        exit 1
    fi
    
    # 프로젝트 설정
    echo "프로젝트 설정 중..."
    gcloud config set project $PROJECT_ID
fi

echo ""
echo -e "${GREEN}✅ 프로젝트 설정 완료: $PROJECT_ID${NC}"
echo ""
echo "다음 단계로 진행하려면 Enter를 누르세요..."
read

# 2. 리전 설정
REGION="us-central1"
echo ""
echo "📍 Step 2: 리전 설정"
echo "===================="
echo -e "${GREEN}✅ 리전: $REGION${NC} (Veo 3.0은 현재 이 리전에서만 사용 가능)"
echo ""

# 3. 필수 API 활성화
echo "🔧 Step 3: 필수 API 활성화"
echo "========================="
echo "다음 API들을 활성화합니다:"
echo "• Cloud Functions"
echo "• Cloud Build"
echo "• Cloud Scheduler"
echo "• Vertex AI"
echo "• Google Sheets"
echo ""
echo "활성화 중... (약 1-2분 소요)"

gcloud services enable \
    cloudfunctions.googleapis.com \
    cloudbuild.googleapis.com \
    cloudscheduler.googleapis.com \
    aiplatform.googleapis.com \
    iam.googleapis.com \
    sheets.googleapis.com \
    serviceusage.googleapis.com \
    --quiet

echo -e "${GREEN}✅ API 활성화 완료${NC}"
echo ""
echo "다음 단계로 진행하려면 Enter를 누르세요..."
read

# 4. 서비스 계정 생성
echo ""
echo "🔑 Step 4: 서비스 계정 생성"
echo "=========================="
echo "Veo API와 Google Sheets에 접근할 서비스 계정을 생성합니다."
echo ""

SERVICE_ACCOUNT_NAME="veo-token-sa"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# 서비스 계정이 이미 존재하는지 확인
if gcloud iam service-accounts describe $SERVICE_ACCOUNT_EMAIL >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  서비스 계정이 이미 존재합니다${NC}"
    echo -e "서비스 계정: ${GREEN}$SERVICE_ACCOUNT_EMAIL${NC}"
else
    echo "서비스 계정 생성 중..."
    gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
        --display-name="Veo Token Service Account" \
        --quiet
    echo -e "${GREEN}✅ 서비스 계정 생성 완료${NC}"
    echo -e "서비스 계정: ${GREEN}$SERVICE_ACCOUNT_EMAIL${NC}"
fi
echo ""

# 5. 권한 부여
echo "🔐 Step 5: 권한 부여"
echo "==================="
echo "서비스 계정에 필요한 권한을 부여합니다..."
echo ""

# Vertex AI User
echo "• Vertex AI 사용 권한 부여 중..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/aiplatform.user" \
    --quiet

# Cloud Functions Invoker
echo "• Cloud Functions 실행 권한 부여 중..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/cloudfunctions.invoker" \
    --quiet

echo -e "${GREEN}✅ 권한 부여 완료${NC}"
echo ""
echo "다음 단계로 진행하려면 Enter를 누르세요..."
read

# 6. 서비스 계정 키 생성
echo ""
echo "🔑 Step 6: 서비스 계정 키 생성"
echo "============================="
echo "보안 키를 생성합니다..."
echo ""

TEMP_KEY_FILE="/tmp/veo-key-temp.json"
rm -f $TEMP_KEY_FILE

gcloud iam service-accounts keys create $TEMP_KEY_FILE \
    --iam-account=$SERVICE_ACCOUNT_EMAIL \
    --quiet

# JSON 내용을 변수로 저장
SERVICE_ACCOUNT_JSON=$(cat $TEMP_KEY_FILE)

echo -e "${GREEN}✅ 서비스 계정 키 생성 완료${NC}"
echo ""

# 7. Google Sheets 설정
echo "📊 Step 7: Google Sheets 설정"
echo "============================="
echo ""
echo -e "${BLUE}이제 Google Sheets를 설정해야 합니다.${NC}"
echo ""
echo "📝 다음 단계를 따라주세요:"
echo ""
echo "1️⃣  새 브라우저 탭에서 Google Sheets 열기:"
echo "   ${BLUE}https://sheets.google.com${NC}"
echo ""
echo "2️⃣  '빈 스프레드시트' 클릭하여 새 시트 생성"
echo ""
echo "3️⃣  상단의 '공유' 버튼 클릭"
echo ""
echo "4️⃣  다음 이메일을 복사해서 입력:"
echo "   ${GREEN}${SERVICE_ACCOUNT_EMAIL}${NC}"
echo ""
echo "5️⃣  권한을 '편집자'로 설정"
echo ""
echo "6️⃣  '무시하고 공유' 클릭 (경고가 나타나면)"
echo ""
echo "7️⃣  URL에서 스프레드시트 ID 복사:"
echo "   https://docs.google.com/spreadsheets/d/${YELLOW}이_부분이_ID입니다${NC}/edit"
echo ""
echo "위 단계를 완료하셨으면,"
echo -n "스프레드시트 ID를 입력하세요: "
read SPREADSHEET_ID

if [ -z "$SPREADSHEET_ID" ]; then
    echo -e "${RED}❌ 스프레드시트 ID가 필요합니다${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ 스프레드시트 설정 완료${NC}"
echo "ID: $SPREADSHEET_ID"
echo ""
echo "다음 단계로 진행하려면 Enter를 누르세요..."
read

# 8. Cloud Function 소스 코드 다운로드
echo ""
echo "📦 Step 8: Cloud Function 코드 준비"
echo "==================================="
echo "필요한 코드를 다운로드합니다..."
echo ""

TEMP_DIR="/tmp/veo-cloud-function"
rm -rf $TEMP_DIR
mkdir -p $TEMP_DIR

# main.py 다운로드
curl -sL https://raw.githubusercontent.com/NewTurn2017/gcp-token-service/main/cloud-function/main.py \
    -o $TEMP_DIR/main.py

# requirements.txt 다운로드
curl -sL https://raw.githubusercontent.com/NewTurn2017/gcp-token-service/main/cloud-function/requirements.txt \
    -o $TEMP_DIR/requirements.txt

echo -e "${GREEN}✅ 코드 준비 완료${NC}"
echo ""

# 9. Cloud Function 배포
echo "☁️  Step 9: Cloud Function 배포"
echo "==============================="
echo "이제 Cloud Function을 배포합니다."
echo "이 과정은 약 2-3분 정도 소요됩니다..."
echo ""

FUNCTION_NAME="veo-token-updater"

# 환경 변수 파일 생성 (특수 문자 문제 해결)
ENV_FILE="/tmp/cloud-function-env.yaml"
cat > $ENV_FILE << EOF
SERVICE_ACCOUNT_JSON: '$SERVICE_ACCOUNT_JSON'
SPREADSHEET_ID: '$SPREADSHEET_ID'
EOF

echo "배포 중..."
gcloud functions deploy $FUNCTION_NAME \
    --gen2 \
    --runtime=python311 \
    --region=$REGION \
    --source=$TEMP_DIR \
    --entry-point=update_token \
    --trigger-http \
    --allow-unauthenticated \
    --env-vars-file=$ENV_FILE \
    --memory=256MB \
    --timeout=60s \
    --quiet

# 임시 환경 변수 파일 삭제
rm -f $ENV_FILE

# Function URL 가져오기
FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME --region=$REGION --gen2 --format="value(serviceConfig.uri)")

echo ""
echo -e "${GREEN}✅ Cloud Function 배포 완료!${NC}"
echo ""

# 10. 테스트 실행
echo "🧪 Step 10: 테스트"
echo "=================="
echo "Cloud Function이 정상 작동하는지 테스트합니다..."
echo ""

echo "테스트 실행 중..."
RESPONSE=$(curl -s $FUNCTION_URL)
echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"

echo ""
echo -e "${GREEN}✅ 테스트 완료${NC}"
echo ""
echo "다음 단계로 진행하려면 Enter를 누르세요..."
read

# 11. Cloud Scheduler 설정
echo ""
echo "⏰ Step 11: 자동 실행 설정"
echo "========================="
echo "매시간 자동으로 토큰을 갱신하도록 설정합니다..."
echo ""

SCHEDULER_NAME="veo-token-scheduler"

# App Engine 앱이 없으면 생성 (Cloud Scheduler 필수)
if ! gcloud app describe >/dev/null 2>&1; then
    echo "App Engine 앱 생성 중..."
    gcloud app create --region=$REGION --quiet || true
fi

# 기존 스케줄러가 있다면 삭제
gcloud scheduler jobs delete $SCHEDULER_NAME --location=$REGION --quiet 2>/dev/null || true

# 새 스케줄러 생성 (매시간 5분에 실행)
echo "스케줄러 생성 중..."
gcloud scheduler jobs create http $SCHEDULER_NAME \
    --location=$REGION \
    --schedule="5 * * * *" \
    --uri=$FUNCTION_URL \
    --http-method=GET \
    --description="Veo token updater - runs every hour at 5 minutes past" \
    --quiet

echo -e "${GREEN}✅ 자동 실행 설정 완료${NC}"
echo ""

# 12. 임시 파일 정리
rm -f $TEMP_KEY_FILE
rm -rf $TEMP_DIR

# 13. 완료 메시지
echo ""
echo "🎉 모든 설정이 완료되었습니다!"
echo "=============================="
echo ""
echo -e "${GREEN}📊 Google Sheets 확인:${NC}"
echo "   https://docs.google.com/spreadsheets/d/$SPREADSHEET_ID"
echo "   • A1: Last Updated"
echo "   • B1: Access Token"
echo "   • A2: 업데이트 시간"
echo "   • B2: 현재 토큰"
echo ""
echo -e "${GREEN}☁️  Cloud Function:${NC}"
echo "   $FUNCTION_URL"
echo ""
echo -e "${GREEN}⏰ 자동 갱신:${NC}"
echo "   매시간 5분마다 자동 실행됩니다"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}🔧 n8n 설정 방법:${NC}"
echo ""
echo "1. Google Sheets 노드:"
echo "   • Operation: Read"
echo "   • Spreadsheet ID: $SPREADSHEET_ID"
echo "   • Range: B2"
echo ""
echo "2. HTTP Request 노드:"
echo "   • Method: POST"
echo "   • URL:"
echo "     https://us-central1-aiplatform.googleapis.com/v1/projects/$PROJECT_ID/locations/us-central1/publishers/google/models/veo-3.0-generate-preview:predictLongRunning"
echo "   • Headers:"
echo "     - Authorization: Bearer {{토큰}}"
echo "     - Content-Type: application/json"
echo "   • Body: (Veo 3.0 요청 JSON)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}유용한 명령어:${NC}"
echo ""
echo "• 수동 실행:"
echo "  curl $FUNCTION_URL"
echo ""
echo "• 로그 확인:"
echo "  gcloud functions logs read $FUNCTION_NAME --region=$REGION"
echo ""
echo "• 스케줄러 상태:"
echo "  gcloud scheduler jobs list --location=$REGION"
echo ""