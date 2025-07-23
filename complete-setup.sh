#!/bin/bash
# 완전한 설치 스크립트 (서비스 계정 생성부터 시작)

echo "🚀 Veo 토큰 시스템 완전 설치 가이드"
echo "===================================="
echo ""
echo "이 스크립트는 처음부터 끝까지 모든 것을 설정합니다."
echo ""

# 색상 코드
if [ -t 1 ] && [ "${TERM}" != "dumb" ] && command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    NC=$(tput sgr0)
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# 1. 프로젝트 설정
echo "📋 Step 1: 프로젝트 설정"
echo "========================"
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo -n "Google Cloud 프로젝트 ID 입력: "
    read PROJECT_ID
    gcloud config set project $PROJECT_ID
fi
echo -e "${GREEN}프로젝트: $PROJECT_ID${NC}"
echo ""

# 2. API 활성화
echo "🔧 Step 2: 필수 API 활성화"
echo "========================="
echo "활성화 중... (약 1분 소요)"
gcloud services enable \
    cloudfunctions.googleapis.com \
    cloudbuild.googleapis.com \
    aiplatform.googleapis.com \
    iam.googleapis.com \
    sheets.googleapis.com \
    compute.googleapis.com \
    --quiet

echo -e "${GREEN}✅ API 활성화 완료${NC}"
echo ""

# 3. 서비스 계정 생성
echo "🔑 Step 3: 서비스 계정 생성"
echo "=========================="
SERVICE_ACCOUNT_NAME="veo-token-sa"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# 기존 서비스 계정 확인
if gcloud iam service-accounts describe $SERVICE_ACCOUNT_EMAIL >/dev/null 2>&1; then
    echo -e "${YELLOW}서비스 계정이 이미 존재합니다${NC}"
else
    gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
        --display-name="Veo Token Service Account" \
        --quiet
    echo -e "${GREEN}✅ 서비스 계정 생성 완료${NC}"
fi
echo "서비스 계정: $SERVICE_ACCOUNT_EMAIL"
echo ""

# 4. 권한 부여
echo "🔐 Step 4: 권한 부여"
echo "==================="

# Vertex AI 사용 권한
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/aiplatform.user" \
    --quiet

# Cloud Functions 관련 권한
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/cloudfunctions.invoker" \
    --quiet

# Service Account User 권한 (중요!)
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/iam.serviceAccountUser" \
    --quiet

echo -e "${GREEN}✅ 권한 부여 완료${NC}"
echo ""

# 5. 서비스 계정 키 생성
echo "🔑 Step 5: 서비스 계정 키 생성"
echo "=============================="
KEY_FILE="$HOME/veo-key.json"

if [ -f "$KEY_FILE" ]; then
    echo -e "${YELLOW}키 파일이 이미 존재합니다${NC}"
    echo -n "새로 생성하시겠습니까? (y/N): "
    read RECREATE
    if [[ "$RECREATE" =~ ^[Yy]$ ]]; then
        rm -f $KEY_FILE
        gcloud iam service-accounts keys create $KEY_FILE \
            --iam-account=$SERVICE_ACCOUNT_EMAIL \
            --quiet
        echo -e "${GREEN}✅ 새 키 생성 완료${NC}"
    fi
else
    gcloud iam service-accounts keys create $KEY_FILE \
        --iam-account=$SERVICE_ACCOUNT_EMAIL \
        --quiet
    echo -e "${GREEN}✅ 키 파일 생성 완료: $KEY_FILE${NC}"
fi
echo ""

# 6. Python 패키지 설치
echo "📦 Step 6: Python 패키지 설치"
echo "============================="
pip3 install --upgrade --quiet \
    google-auth \
    google-auth-oauthlib \
    google-auth-httplib2 \
    google-api-python-client

echo -e "${GREEN}✅ 패키지 설치 완료${NC}"
echo ""

# 7. Google Sheets 설정
echo "📊 Step 7: Google Sheets 설정"
echo "============================="
echo ""
echo -e "${BLUE}Google Sheets를 준비해주세요:${NC}"
echo ""
echo "1. 새 스프레드시트 생성: https://sheets.google.com"
echo "2. '공유' 버튼 클릭"
echo -e "3. 다음 이메일 추가: ${GREEN}${SERVICE_ACCOUNT_EMAIL}${NC}"
echo "4. '편집자' 권한 선택"
echo "5. '무시하고 공유' 클릭"
echo "6. URL에서 ID 복사 (d/ 와 /edit 사이 부분)"
echo ""
echo -n "스프레드시트 ID 입력: "
read SPREADSHEET_ID

if [ -z "$SPREADSHEET_ID" ]; then
    echo -e "${RED}❌ 스프레드시트 ID가 필요합니다${NC}"
    exit 1
fi
echo ""

# 8. Cloud Build 권한 설정
echo "🔧 Step 8: Cloud Build 권한 설정"
echo "================================"
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
CLOUD_BUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/cloudfunctions.developer" \
    --quiet

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="roles/iam.serviceAccountUser" \
    --quiet

echo -e "${GREEN}✅ Cloud Build 권한 설정 완료${NC}"
echo ""

# 9. Cloud Function 소스 코드 준비
echo "📄 Step 9: Cloud Function 코드 준비"
echo "==================================="
SOURCE_DIR="/tmp/veo-cloud-function"
rm -rf $SOURCE_DIR
mkdir -p $SOURCE_DIR

# Base64로 서비스 계정 JSON 인코딩
SERVICE_ACCOUNT_JSON_BASE64=$(cat "$KEY_FILE" | base64 -w 0)

# main.py 생성
cat > $SOURCE_DIR/main.py << 'EOF'
import json
import functions_framework
from google.oauth2 import service_account
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from datetime import datetime
import os
import base64

# 환경 변수
SERVICE_ACCOUNT_JSON_BASE64 = os.environ.get('SERVICE_ACCOUNT_JSON_BASE64')
SPREADSHEET_ID = os.environ.get('SPREADSHEET_ID')

@functions_framework.http
def update_token(request):
    """Cloud Function entry point"""
    
    # CORS 헤더 설정
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST',
        'Access-Control-Allow-Headers': 'Content-Type',
    }
    
    # Preflight request 처리
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # 서비스 계정 JSON 디코딩
        if not SERVICE_ACCOUNT_JSON_BASE64:
            return (json.dumps({'error': 'Service account JSON not configured'}), 500, headers)
            
        if not SPREADSHEET_ID:
            return (json.dumps({'error': 'Spreadsheet ID not configured'}), 500, headers)
        
        # Base64 디코딩
        service_account_json = base64.b64decode(SERVICE_ACCOUNT_JSON_BASE64).decode('utf-8')
        service_account_info = json.loads(service_account_json)
        
        # Veo API 토큰 생성
        credentials = service_account.Credentials.from_service_account_info(
            service_account_info,
            scopes=['https://www.googleapis.com/auth/cloud-platform']
        )
        credentials.refresh(Request())
        token = credentials.token
        
        # Google Sheets 업데이트
        sheets_creds = service_account.Credentials.from_service_account_info(
            service_account_info,
            scopes=['https://www.googleapis.com/auth/spreadsheets']
        )
        
        service = build('sheets', 'v4', credentials=sheets_creds)
        
        # 업데이트할 데이터
        values = [
            ['Last Updated', 'Access Token'],
            [datetime.now().strftime('%Y-%m-%d %H:%M:%S'), token]
        ]
        
        body = {'values': values}
        
        # Sheets 업데이트
        result = service.spreadsheets().values().update(
            spreadsheetId=SPREADSHEET_ID,
            range='A1:B2',
            valueInputOption='RAW',
            body=body
        ).execute()
        
        response = {
            'status': 'success',
            'message': f"Updated {result.get('updatedCells')} cells",
            'timestamp': datetime.now().isoformat(),
            'token_preview': f"{token[:20]}..." if token else None
        }
        
        return (json.dumps(response), 200, headers)
        
    except Exception as e:
        error_response = {
            'status': 'error',
            'message': str(e),
            'timestamp': datetime.now().isoformat()
        }
        return (json.dumps(error_response), 500, headers)
EOF

# requirements.txt 생성
cat > $SOURCE_DIR/requirements.txt << 'EOF'
functions-framework==3.*
google-auth==2.* 
google-auth-oauthlib==1.*
google-auth-httplib2==0.*
google-api-python-client==2.*
EOF

echo -e "${GREEN}✅ 소스 코드 준비 완료${NC}"
echo ""

# 10. Cloud Function 배포 (1세대)
echo "☁️  Step 10: Cloud Function 배포"
echo "================================"
echo "1세대 Cloud Function으로 배포합니다..."
echo ""

FUNCTION_NAME="veo-token-updater"
REGION="us-central1"

# 기존 함수 삭제
gcloud functions delete $FUNCTION_NAME --region=$REGION --quiet 2>/dev/null || true

# 배포 (기본 서비스 계정 프롬프트 건너뛰기)
echo "Y" | gcloud functions deploy $FUNCTION_NAME \
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
    --no-gen2 \
    --quiet

if [ $? -eq 0 ]; then
    FUNCTION_URL="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}"
    
    echo ""
    echo -e "${GREEN}✅ 배포 성공!${NC}"
    echo ""
    
    # 11. 테스트
    echo "🧪 Step 11: 테스트"
    echo "=================="
    echo "함수 테스트 중..."
    curl -s $FUNCTION_URL | jq '.' 2>/dev/null || curl -s $FUNCTION_URL
    echo ""
    
    # 12. Cloud Scheduler 설정
    echo "⏰ Step 12: 자동 실행 설정 (선택사항)"
    echo "====================================="
    echo -n "매시간 자동 실행을 설정하시겠습니까? (Y/n): "
    read SETUP_SCHEDULER
    
    if [[ ! "$SETUP_SCHEDULER" =~ ^[Nn]$ ]]; then
        # App Engine 확인
        if ! gcloud app describe >/dev/null 2>&1; then
            echo "App Engine 생성 중..."
            gcloud app create --region=$REGION --quiet || true
        fi
        
        SCHEDULER_NAME="veo-token-scheduler"
        
        # 기존 스케줄러 삭제
        gcloud scheduler jobs delete $SCHEDULER_NAME --location=$REGION --quiet 2>/dev/null || true
        
        # 새 스케줄러 생성
        gcloud scheduler jobs create http $SCHEDULER_NAME \
            --location=$REGION \
            --schedule="5 * * * *" \
            --uri=$FUNCTION_URL \
            --http-method=GET \
            --description="Veo token updater - runs every hour" \
            --quiet
        
        echo -e "${GREEN}✅ 자동 실행 설정 완료${NC}"
    fi
    
    # 13. 완료
    echo ""
    echo "🎉 모든 설정이 완료되었습니다!"
    echo "=============================="
    echo ""
    echo -e "${GREEN}📊 Google Sheets:${NC}"
    echo "   https://docs.google.com/spreadsheets/d/$SPREADSHEET_ID"
    echo ""
    echo -e "${GREEN}☁️  Function URL:${NC}"
    echo "   $FUNCTION_URL"
    echo ""
    echo -e "${GREEN}🔧 n8n 설정:${NC}"
    echo "1. Google Sheets 노드: B2 셀 읽기"
    echo "2. HTTP Request 노드:"
    echo "   - Authorization: Bearer {{토큰}}"
    echo "   - URL: https://us-central1-aiplatform.googleapis.com/v1/projects/$PROJECT_ID/locations/us-central1/publishers/google/models/veo-3.0-generate-preview:predictLongRunning"
    
else
    echo ""
    echo -e "${RED}❌ 배포 실패${NC}"
    echo ""
    echo "수동으로 다음을 시도해보세요:"
    echo "1. https://console.cloud.google.com/functions 에서 수동 배포"
    echo "2. IAM 권한 추가 확인"
fi

# 임시 파일 정리
rm -rf $SOURCE_DIR