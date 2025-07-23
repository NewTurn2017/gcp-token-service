#!/bin/bash
# 간단한 Cloud Function 배포 스크립트 (우리 서비스 계정 사용)

echo "🚀 Veo 토큰 시스템 간단 배포"
echo "============================"
echo ""

# 프로젝트 설정
PROJECT_ID=$(gcloud config get-value project)
if [ -z "$PROJECT_ID" ]; then
    echo -n "프로젝트 ID 입력: "
    read PROJECT_ID
    gcloud config set project $PROJECT_ID
fi

# 서비스 계정 확인
SERVICE_ACCOUNT_EMAIL="veo-token-sa@${PROJECT_ID}.iam.gserviceaccount.com"
KEY_FILE="$HOME/veo-key.json"

if [ ! -f "$KEY_FILE" ]; then
    echo "❌ 서비스 계정 키 파일이 없습니다: $KEY_FILE"
    echo "먼저 complete-setup.sh를 실행하세요."
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
echo ""
echo "📦 소스 코드 준비 중..."
SOURCE_DIR="/tmp/veo-function-simple"
rm -rf $SOURCE_DIR
mkdir -p $SOURCE_DIR

# Base64 인코딩
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

# 배포
echo ""
echo "☁️  배포 중..."
echo "기본 서비스 계정 경고가 나와도 무시하고 진행됩니다..."
echo ""

FUNCTION_NAME="veo-token-updater"
REGION="us-central1"

# 기존 함수 삭제
gcloud functions delete $FUNCTION_NAME --region=$REGION --quiet 2>/dev/null || true

# Y를 자동으로 입력하여 프롬프트 건너뛰기
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
    --no-gen2

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ 배포 성공!"
    echo ""
    FUNCTION_URL="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}"
    echo "📊 Google Sheets: https://docs.google.com/spreadsheets/d/$SPREADSHEET_ID"
    echo "☁️  Function URL: $FUNCTION_URL"
    echo ""
    echo "테스트 중..."
    curl -s $FUNCTION_URL | jq '.' || curl -s $FUNCTION_URL
else
    echo ""
    echo "❌ 배포 실패"
    echo ""
    echo "다음을 확인하세요:"
    echo "1. 프로젝트에서 Cloud Functions API가 활성화되어 있는지"
    echo "2. 서비스 계정에 필요한 권한이 있는지"
fi

# 정리
rm -rf $SOURCE_DIR