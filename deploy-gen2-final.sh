#!/bin/bash
# 2세대 Cloud Functions로 배포 (기본 서비스 계정 없이)

echo "🚀 Cloud Functions 2세대 배포 (기본 SA 없이)"
echo "=========================================="
echo ""

# 프로젝트 설정
PROJECT_ID=$(gcloud config get-value project)
SERVICE_ACCOUNT_EMAIL="veo-token-sa@${PROJECT_ID}.iam.gserviceaccount.com"
KEY_FILE="$HOME/veo-key.json"

echo "프로젝트: $PROJECT_ID"
echo "서비스 계정: $SERVICE_ACCOUNT_EMAIL"
echo ""

# 키 파일 확인
if [ ! -f "$KEY_FILE" ]; then
    echo "❌ 서비스 계정 키 파일이 없습니다"
    exit 1
fi

# 스프레드시트 ID
echo -n "Google Sheets ID 입력: "
read SPREADSHEET_ID

# Cloud Run API 활성화 (Gen2 필수)
echo ""
echo "📋 필수 API 활성화 중..."
gcloud services enable \
    cloudfunctions.googleapis.com \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    --quiet

echo "✅ API 활성화 완료"
echo ""

# 소스 코드 준비
SOURCE_DIR="/tmp/veo-gen2"
rm -rf $SOURCE_DIR
mkdir -p $SOURCE_DIR

# Base64 인코딩
SERVICE_ACCOUNT_JSON_BASE64=$(cat "$KEY_FILE" | base64 -w 0)

# main.py
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
echo "☁️  배포 중..."
FUNCTION_NAME="veo-token-updater"
REGION="us-central1"

# 기존 함수 삭제
gcloud functions delete $FUNCTION_NAME --region=$REGION --gen2 --quiet 2>/dev/null || true

# 2세대로 배포
gcloud functions deploy $FUNCTION_NAME \
    --gen2 \
    --runtime=python311 \
    --region=$REGION \
    --source=$SOURCE_DIR \
    --entry-point=update_token \
    --trigger-http \
    --allow-unauthenticated \
    --run-service-account=$SERVICE_ACCOUNT_EMAIL \
    --env-vars-file=$ENV_FILE \
    --memory=256MB \
    --timeout=60s \
    --max-instances=10 \
    --quiet

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ 배포 성공!"
    
    FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME --region=$REGION --gen2 --format="value(serviceConfig.uri)")
    
    echo ""
    echo "📊 Google Sheets: https://docs.google.com/spreadsheets/d/$SPREADSHEET_ID"
    echo "☁️  Function URL: $FUNCTION_URL"
    echo ""
    echo "테스트 중..."
    curl -s $FUNCTION_URL | jq '.' || curl -s $FUNCTION_URL
else
    echo "❌ 배포 실패"
fi

# 정리
rm -rf $SOURCE_DIR
rm -f $ENV_FILE