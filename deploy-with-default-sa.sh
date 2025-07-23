#!/bin/bash
# 기본 서비스 계정을 사용한 Cloud Functions 배포

echo "🚀 기본 서비스 계정으로 Cloud Functions 배포"
echo "=========================================="
echo ""

# 프로젝트 설정
PROJECT_ID="warmtalentai"
PROJECT_NUMBER="227871897464"
DEFAULT_SA_EMAIL="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
KEY_FILE="$HOME/veo-key.json"

echo "프로젝트: $PROJECT_ID"
echo "기본 서비스 계정: $DEFAULT_SA_EMAIL"
echo ""

# 키 파일 확인
if [ ! -f "$KEY_FILE" ]; then
    echo "❌ 서비스 계정 키 파일이 없습니다: $KEY_FILE"
    exit 1
fi

# 스프레드시트 ID
echo -n "Google Sheets ID 입력: "
read SPREADSHEET_ID

if [ -z "$SPREADSHEET_ID" ]; then
    echo "❌ 스프레드시트 ID가 필요합니다"
    exit 1
fi

# 소스 코드 준비
SOURCE_DIR="/tmp/veo-default-sa"
rm -rf $SOURCE_DIR
mkdir -p $SOURCE_DIR

# Base64 인코딩
SERVICE_ACCOUNT_JSON_BASE64=$(cat "$KEY_FILE" | base64 -w 0)

# main.py (기존과 동일)
cat > $SOURCE_DIR/main.py << 'EOF'
import json
import functions_framework
from google.oauth2 import service_account
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from datetime import datetime
import os
import base64

SERVICE_ACCOUNT_JSON_BASE64 = os.environ.get('SERVICE_ACCOUNT_JSON_BASE64')
SPREADSHEET_ID = os.environ.get('SPREADSHEET_ID')

@functions_framework.http
def update_token(request):
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST',
        'Access-Control-Allow-Headers': 'Content-Type',
    }
    
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        if not SERVICE_ACCOUNT_JSON_BASE64 or not SPREADSHEET_ID:
            return (json.dumps({'error': 'Missing configuration'}), 500, headers)
        
        service_account_json = base64.b64decode(SERVICE_ACCOUNT_JSON_BASE64).decode('utf-8')
        service_account_info = json.loads(service_account_json)
        
        # Veo 토큰 생성
        credentials = service_account.Credentials.from_service_account_info(
            service_account_info,
            scopes=['https://www.googleapis.com/auth/cloud-platform']
        )
        credentials.refresh(Request())
        token = credentials.token
        
        # Sheets 업데이트
        sheets_creds = service_account.Credentials.from_service_account_info(
            service_account_info,
            scopes=['https://www.googleapis.com/auth/spreadsheets']
        )
        
        service = build('sheets', 'v4', credentials=sheets_creds)
        
        values = [
            ['Last Updated', 'Access Token'],
            [datetime.now().strftime('%Y-%m-%d %H:%M:%S'), token]
        ]
        
        result = service.spreadsheets().values().update(
            spreadsheetId=SPREADSHEET_ID,
            range='A1:B2',
            valueInputOption='RAW',
            body={'values': values}
        ).execute()
        
        return (json.dumps({
            'status': 'success',
            'message': f"Updated {result.get('updatedCells')} cells",
            'timestamp': datetime.now().isoformat()
        }), 200, headers)
        
    except Exception as e:
        return (json.dumps({
            'status': 'error',
            'message': str(e)
        }), 500, headers)
EOF

# requirements.txt
cat > $SOURCE_DIR/requirements.txt << 'EOF'
functions-framework==3.*
google-auth==2.*
google-auth-oauthlib==1.*
google-auth-httplib2==0.*
google-api-python-client==2.*
EOF

# 환경 변수 파일
ENV_FILE="/tmp/env.yaml"
cat > $ENV_FILE << EOF
SERVICE_ACCOUNT_JSON_BASE64: '$SERVICE_ACCOUNT_JSON_BASE64'
SPREADSHEET_ID: '$SPREADSHEET_ID'
EOF

# 배포
echo ""
echo "☁️  Cloud Functions 배포 중..."
FUNCTION_NAME="veo-token-updater"
REGION="us-central1"

# 기존 함수 삭제
echo "기존 함수 삭제 중..."
gcloud functions delete $FUNCTION_NAME --region=$REGION --quiet 2>/dev/null || true

# Gen1으로 배포 (기본 서비스 계정 사용)
echo ""
echo "Gen1 Cloud Functions로 배포..."
gcloud functions deploy $FUNCTION_NAME \
    --runtime=python311 \
    --region=$REGION \
    --source=$SOURCE_DIR \
    --entry-point=update_token \
    --trigger-http \
    --allow-unauthenticated \
    --env-vars-file=$ENV_FILE \
    --memory=256MB \
    --timeout=60s \
    --no-gen2 \
    --quiet

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ 배포 성공!"
    
    FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME --region=$REGION --format="value(httpsTrigger.url)")
    
    echo ""
    echo "📊 Google Sheets: https://docs.google.com/spreadsheets/d/$SPREADSHEET_ID"
    echo "☁️  Function URL: $FUNCTION_URL"
    echo ""
    echo "테스트 중..."
    curl -s $FUNCTION_URL | jq '.' || curl -s $FUNCTION_URL
    
    # Cloud Scheduler 설정
    echo ""
    echo "⏰ Cloud Scheduler 설정 (선택사항)"
    echo -n "매시간 자동 실행을 설정하시겠습니까? (y/N): "
    read SETUP_SCHEDULER
    
    if [ "$SETUP_SCHEDULER" = "y" ] || [ "$SETUP_SCHEDULER" = "Y" ]; then
        JOB_NAME="veo-token-refresh"
        
        # Cloud Scheduler API 활성화
        gcloud services enable cloudscheduler.googleapis.com --quiet
        
        # 기존 작업 삭제
        gcloud scheduler jobs delete $JOB_NAME --location=$REGION --quiet 2>/dev/null || true
        
        # 새 작업 생성
        gcloud scheduler jobs create http $JOB_NAME \
            --location=$REGION \
            --schedule="0 * * * *" \
            --uri=$FUNCTION_URL \
            --http-method=GET \
            --time-zone="Asia/Seoul"
        
        echo "✅ Cloud Scheduler 설정 완료! 매시간 자동 실행됩니다."
    fi
else
    echo ""
    echo "❌ 배포 실패"
    echo ""
    echo "다음을 시도해보세요:"
    echo "1. ./check-default-sa-status.sh 실행하여 서비스 계정 상태 확인"
    echo "2. ./fix-default-sa-permissions.sh 실행하여 권한 수정"
    echo "3. 다시 이 스크립트 실행"
fi

# 정리
rm -rf $SOURCE_DIR
rm -f $ENV_FILE