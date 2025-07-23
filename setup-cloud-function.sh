#!/bin/bash
# Cloud Functions 기반 Veo 토큰 시스템 완전 자동 설치 스크립트

set -e

echo "🚀 Cloud Functions 기반 Veo 토큰 시스템 설치"
echo "============================================"
echo ""

# 색상 코드 (터미널이 지원하는 경우에만 사용)
if [ -t 1 ] && [ "${TERM}" != "dumb" ] && command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    NC=$(tput sgr0)
else
    # 색상을 지원하지 않는 경우 빈 문자열 사용
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

# TTY 리다이렉션으로 대화형 입력 활성화
exec < /dev/tty

# 1. 프로젝트 ID 확인 또는 입력
echo "📋 Google Cloud 프로젝트 설정"
echo "============================="
echo ""

# 현재 프로젝트 확인
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
if [ ! -z "$CURRENT_PROJECT" ]; then
    echo -e "현재 프로젝트: ${GREEN}$CURRENT_PROJECT${NC}"
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
    echo -n "Project ID: "
    read PROJECT_ID
    
    if [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}❌ 프로젝트 ID가 필요합니다${NC}"
        exit 1
    fi
    
    # 프로젝트 설정
    gcloud config set project $PROJECT_ID
fi

echo -e "${GREEN}✅ 프로젝트: $PROJECT_ID${NC}"
echo ""

# 2. 리전 설정
REGION="us-central1"
echo -e "${GREEN}✅ 리전: $REGION${NC}"
echo ""

# 3. 필수 API 활성화
echo "📋 필수 API 활성화 중..."
gcloud services enable \
    cloudfunctions.googleapis.com \
    cloudbuild.googleapis.com \
    cloudscheduler.googleapis.com \
    aiplatform.googleapis.com \
    iam.googleapis.com \
    sheets.googleapis.com \
    serviceusage.googleapis.com \
    compute.googleapis.com \
    --quiet

echo -e "${GREEN}✅ API 활성화 완료${NC}"
echo ""

# 4. 서비스 계정 생성
echo "🔑 서비스 계정 생성..."
SERVICE_ACCOUNT_NAME="veo-token-sa"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# 서비스 계정이 이미 존재하는지 확인
if gcloud iam service-accounts describe $SERVICE_ACCOUNT_EMAIL >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  서비스 계정이 이미 존재합니다: $SERVICE_ACCOUNT_EMAIL${NC}"
else
    gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
        --display-name="Veo Token Service Account" \
        --quiet
    echo -e "${GREEN}✅ 서비스 계정 생성 완료${NC}"
fi

# 5. 권한 부여
echo "🔐 권한 부여 중..."

# Vertex AI User
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/aiplatform.user" \
    --quiet

# Cloud Functions Invoker
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/cloudfunctions.invoker" \
    --quiet

echo -e "${GREEN}✅ 권한 부여 완료${NC}"
echo ""

# 6. 서비스 계정 키 생성
echo "🔑 서비스 계정 키 생성..."
TEMP_KEY_FILE="/tmp/veo-key-temp.json"

# 기존 키 파일이 있다면 삭제
rm -f $TEMP_KEY_FILE

gcloud iam service-accounts keys create $TEMP_KEY_FILE \
    --iam-account=$SERVICE_ACCOUNT_EMAIL \
    --quiet

# JSON 내용을 변수로 저장
SERVICE_ACCOUNT_JSON=$(cat $TEMP_KEY_FILE)

echo -e "${GREEN}✅ 서비스 계정 키 생성 완료${NC}"
echo ""

# 7. Google Sheets 설정
echo "📊 Google Sheets 설정"
echo "===================="
echo ""

# Google Sheets가 이미 있는지 확인
if [ ! -z "$SPREADSHEET_ID" ]; then
    echo -e "기존 스프레드시트 ID: ${GREEN}$SPREADSHEET_ID${NC}"
    echo -n "이 스프레드시트를 사용하시겠습니까? (Y/n): "
    read USE_EXISTING
    if [[ "$USE_EXISTING" =~ ^[Nn]$ ]]; then
        SPREADSHEET_ID=""
    fi
fi

if [ -z "$SPREADSHEET_ID" ]; then
    echo ""
    echo -e "${YELLOW}새 Google Sheets를 설정해주세요:${NC}"
    echo ""
    echo "📝 단계별 안내:"
    echo "1. 새 스프레드시트 생성: https://sheets.google.com"
    echo "2. 상단의 '공유' 버튼 클릭"
    echo "3. 다음 이메일 추가: ${GREEN}${SERVICE_ACCOUNT_EMAIL}${NC}"
    echo "4. 권한: '편집자' 선택"
    echo "5. '무시하고 공유' 클릭 (경고가 나타나면)"
    echo "6. URL에서 스프레드시트 ID 복사:"
    echo "   https://docs.google.com/spreadsheets/d/${YELLOW}ID_HERE${NC}/edit"
    echo ""
    echo -n "스프레드시트 ID 입력: "
    read SPREADSHEET_ID
    
    if [ -z "$SPREADSHEET_ID" ]; then
        echo -e "${RED}❌ 스프레드시트 ID가 필요합니다${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ 스프레드시트 ID: $SPREADSHEET_ID${NC}"
echo ""

# 8. Cloud Function 소스 코드 다운로드
echo "📦 Cloud Function 코드 준비..."
TEMP_DIR="/tmp/veo-cloud-function"
rm -rf $TEMP_DIR
mkdir -p $TEMP_DIR

# main.py 다운로드
curl -sL https://raw.githubusercontent.com/NewTurn2017/gcp-token-service/main/cloud-function/main.py \
    -o $TEMP_DIR/main.py

# requirements.txt 다운로드
curl -sL https://raw.githubusercontent.com/NewTurn2017/gcp-token-service/main/cloud-function/requirements.txt \
    -o $TEMP_DIR/requirements.txt

echo -e "${GREEN}✅ 소스 코드 준비 완료${NC}"
echo ""

# 9. Cloud Function 배포
echo "☁️  Cloud Function 배포 중..."

# 기본 서비스 계정 확인 및 생성
echo "기본 서비스 계정 확인 중..."
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
DEFAULT_SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# 기본 서비스 계정이 없으면 Compute Engine을 한 번 실행하여 생성
if ! gcloud iam service-accounts describe $DEFAULT_SERVICE_ACCOUNT >/dev/null 2>&1; then
    echo "기본 서비스 계정 생성 중..."
    # 임시 인스턴스 생성 시도 (실패해도 서비스 계정은 생성됨)
    gcloud compute instances create temp-init \
        --zone=${REGION}-a \
        --machine-type=f1-micro \
        --max-run-duration=1s \
        --quiet 2>/dev/null || true
    
    # 인스턴스가 생성되었다면 삭제
    gcloud compute instances delete temp-init \
        --zone=${REGION}-a \
        --quiet 2>/dev/null || true
    
    # 서비스 계정 생성 대기
    sleep 10
fi

FUNCTION_NAME="veo-token-updater"

# 환경 변수 파일 생성
ENV_FILE="/tmp/cloud-function-env.yaml"
cat > $ENV_FILE << EOF
SERVICE_ACCOUNT_JSON: '$SERVICE_ACCOUNT_JSON'
SPREADSHEET_ID: '$SPREADSHEET_ID'
EOF

gcloud functions deploy $FUNCTION_NAME \
    --gen2 \
    --runtime=python311 \
    --region=$REGION \
    --source=$TEMP_DIR \
    --entry-point=update_token \
    --trigger-http \
    --allow-unauthenticated \
    --env-vars-file=$ENV_FILE \
    --service-account=$SERVICE_ACCOUNT_EMAIL \
    --memory=256MB \
    --timeout=60s \
    --quiet

# 임시 환경 변수 파일 삭제
rm -f $ENV_FILE

# Function URL 가져오기
FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME --region=$REGION --gen2 --format="value(serviceConfig.uri)")

echo -e "${GREEN}✅ Cloud Function 배포 완료${NC}"
echo -e "${GREEN}URL: $FUNCTION_URL${NC}"
echo ""

# 10. 테스트 실행
echo "🧪 테스트 실행..."
curl -s $FUNCTION_URL | jq '.' || curl -s $FUNCTION_URL

echo ""
echo -e "${GREEN}✅ 테스트 완료${NC}"
echo ""

# 11. Cloud Scheduler 설정
echo "⏰ Cloud Scheduler 설정..."
SCHEDULER_NAME="veo-token-scheduler"

# App Engine 앱이 없으면 생성 (Cloud Scheduler 필수)
if ! gcloud app describe >/dev/null 2>&1; then
    echo "App Engine 앱 생성 중..."
    gcloud app create --region=$REGION --quiet || true
fi

# 기존 스케줄러가 있다면 삭제
gcloud scheduler jobs delete $SCHEDULER_NAME --location=$REGION --quiet 2>/dev/null || true

# 새 스케줄러 생성 (매시간 5분에 실행)
gcloud scheduler jobs create http $SCHEDULER_NAME \
    --location=$REGION \
    --schedule="5 * * * *" \
    --uri=$FUNCTION_URL \
    --http-method=GET \
    --description="Veo token updater - runs every hour at 5 minutes past" \
    --quiet

echo -e "${GREEN}✅ Cloud Scheduler 설정 완료${NC}"
echo ""

# 12. 임시 파일 정리
rm -f $TEMP_KEY_FILE
rm -rf $TEMP_DIR

# 13. 완료 메시지
echo ""
echo "🎉 설치 완료!"
echo "============"
echo ""
echo -e "${GREEN}📊 Google Sheets:${NC}"
echo "   https://docs.google.com/spreadsheets/d/$SPREADSHEET_ID"
echo ""
echo -e "${GREEN}☁️  Cloud Function URL:${NC}"
echo "   $FUNCTION_URL"
echo ""
echo -e "${GREEN}⏰ 자동 갱신:${NC}"
echo "   매시간 5분마다 자동 실행"
echo ""
echo -e "${GREEN}🔧 n8n 설정:${NC}"
echo "1. Google Sheets 노드:"
echo "   - Operation: Read"
echo "   - Spreadsheet ID: $SPREADSHEET_ID"
echo "   - Range: B2"
echo ""
echo "2. HTTP Request 노드:"
echo "   - Method: POST"
echo "   - URL: https://us-central1-aiplatform.googleapis.com/v1/projects/$PROJECT_ID/locations/us-central1/publishers/google/models/veo-3.0-generate-preview:predictLongRunning"
echo "   - Headers:"
echo "     - Authorization: Bearer {{토큰}}"
echo "     - Content-Type: application/json"
echo ""
echo -e "${GREEN}📝 수동 실행:${NC}"
echo "   curl $FUNCTION_URL"
echo ""
echo -e "${GREEN}📊 스케줄러 상태 확인:${NC}"
echo "   gcloud scheduler jobs list --location=$REGION"
echo ""