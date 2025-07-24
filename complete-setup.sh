#!/bin/bash
# Veo 3.0 Token Service 완전 자동 설치 스크립트

echo "🚀 Veo 3.0 토큰 자동화 시스템 설치"
echo "================================="
echo ""

# 프로젝트 설정
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo "❌ 프로젝트가 설정되지 않았습니다"
    echo "먼저 실행: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
echo "프로젝트: $PROJECT_ID ($PROJECT_NUMBER)"
echo ""

# 1. API 활성화
echo "📋 API 활성화 중..."
set +e  # API 활성화 중 오류 무시
gcloud services enable \
    cloudfunctions.googleapis.com \
    cloudbuild.googleapis.com \
    aiplatform.googleapis.com \
    sheets.googleapis.com \
    cloudscheduler.googleapis.com \
    --quiet
set -e  # 다시 오류 체크 활성화

# 2. 서비스 계정 생성
echo "🔑 서비스 계정 설정..."
SA_NAME="veo-token-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if ! gcloud iam service-accounts describe $SA_EMAIL >/dev/null 2>&1; then
    gcloud iam service-accounts create $SA_NAME --display-name="Veo Token Service" --quiet
fi

# 3. 권한 부여
echo "🔐 권한 부여..."
for role in "roles/aiplatform.user" "roles/editor"; do
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="$role" \
        --quiet >/dev/null 2>&1
done

# 4. 키 생성
KEY_FILE="$HOME/veo-key.json"
if [ ! -f "$KEY_FILE" ]; then
    gcloud iam service-accounts keys create $KEY_FILE --iam-account=$SA_EMAIL --quiet
fi

# 5. Google Sheets 설정
echo ""
echo "📊 Google Sheets 설정"
echo "===================="
echo "1. 새 스프레드시트 생성: https://sheets.google.com"
echo "2. 주소창에서 /d/와 /edit 사이의 ID 복사"
echo "3. 공유 → $SA_EMAIL 추가 (편집자 권한)"
echo ""
# 대화형 입력을 위해 TTY 확인
if [ -t 0 ]; then
    echo -n "스프레드시트 ID: "
    read SPREADSHEET_ID
else
    # 파이프로 실행 중인 경우 TTY 리다이렉션
    exec < /dev/tty
    echo -n "스프레드시트 ID: "
    read SPREADSHEET_ID
fi

# ID 확인
if [ -z "$SPREADSHEET_ID" ]; then
    echo "❌ 스프레드시트 ID가 필요합니다"
    exit 1
fi

# 6. 테스트
echo ""
echo "🧪 연결 테스트..."
cat > /tmp/test-veo.py << EOF
from google.oauth2 import service_account
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from datetime import datetime

credentials = service_account.Credentials.from_service_account_file(
    '$KEY_FILE',
    scopes=['https://www.googleapis.com/auth/cloud-platform']
)
credentials.refresh(Request())
print(f"✅ 토큰 생성 성공: {credentials.token[:20]}...")

sheets_creds = service_account.Credentials.from_service_account_file(
    '$KEY_FILE',
    scopes=['https://www.googleapis.com/auth/spreadsheets']
)
service = build('sheets', 'v4', credentials=sheets_creds)
values = [['Last Updated', 'Access Token'], [datetime.now().strftime('%Y-%m-%d %H:%M:%S'), credentials.token]]
service.spreadsheets().values().update(
    spreadsheetId='$SPREADSHEET_ID',
    range='A1:B2',
    valueInputOption='RAW',
    body={'values': values}
).execute()
print("✅ Sheets 업데이트 성공!")
EOF

pip3 install -q google-auth google-auth-oauthlib google-auth-httplib2 google-api-python-client || {
    echo "⚠️  Python 패키지 설치 실패. 수동으로 설치해주세요:"
    echo "pip3 install google-auth google-auth-oauthlib google-auth-httplib2 google-api-python-client"
    exit 1
}

python3 /tmp/test-veo.py || {
    echo "❌ 테스트 실패. Google Sheets 공유 설정을 확인해주세요"
    exit 1
}

# 7. Cloud Function 배포
echo ""
echo "☁️  Cloud Function 배포..."
SOURCE_DIR="/tmp/veo-function"
mkdir -p $SOURCE_DIR

cat > $SOURCE_DIR/main.py << 'EOF'
import json
import functions_framework
from google.oauth2 import service_account
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from datetime import datetime
import os
import base64

@functions_framework.http
def update_token(request):
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        service_account_json = base64.b64decode(os.environ.get('SERVICE_ACCOUNT_JSON_BASE64')).decode('utf-8')
        service_account_info = json.loads(service_account_json)
        
        credentials = service_account.Credentials.from_service_account_info(
            service_account_info,
            scopes=['https://www.googleapis.com/auth/cloud-platform']
        )
        credentials.refresh(Request())
        
        sheets_creds = service_account.Credentials.from_service_account_info(
            service_account_info,
            scopes=['https://www.googleapis.com/auth/spreadsheets']
        )
        
        service = build('sheets', 'v4', credentials=sheets_creds)
        values = [
            ['Last Updated', 'Access Token'],
            [datetime.now().strftime('%Y-%m-%d %H:%M:%S'), credentials.token]
        ]
        
        service.spreadsheets().values().update(
            spreadsheetId=os.environ.get('SPREADSHEET_ID'),
            range='A1:B2',
            valueInputOption='RAW',
            body={'values': values}
        ).execute()
        
        return (json.dumps({'status': 'success', 'timestamp': datetime.now().isoformat()}), 200, headers)
    except Exception as e:
        return (json.dumps({'error': str(e)}), 500, headers)
EOF

cat > $SOURCE_DIR/requirements.txt << 'EOF'
functions-framework==3.*
google-auth==2.*
google-auth-httplib2==0.*
google-api-python-client==2.*
EOF

# Base64 인코딩
SERVICE_ACCOUNT_JSON_BASE64=$(cat "$KEY_FILE" | base64 -w 0)

# 배포
FUNCTION_NAME="veo-token-updater"
REGION="us-central1"

# Gen2 우선 시도, 실패시 Gen1
echo ""
echo "첫 번째 시도: Gen2 Cloud Functions..."
if gcloud functions deploy $FUNCTION_NAME \
    --gen2 \
    --runtime=python311 \
    --region=$REGION \
    --source=$SOURCE_DIR \
    --entry-point=update_token \
    --trigger-http \
    --allow-unauthenticated \
    --run-service-account=$SA_EMAIL \
    --set-env-vars="SERVICE_ACCOUNT_JSON_BASE64=${SERVICE_ACCOUNT_JSON_BASE64},SPREADSHEET_ID=${SPREADSHEET_ID}" \
    --memory=256MB \
    --quiet 2>/dev/null; then
    echo "✅ Gen2 배포 성공"
    FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME --region=$REGION --gen2 --format="value(serviceConfig.uri)")
else
    echo "Gen1으로 재시도..."
    echo "Y" | gcloud functions deploy $FUNCTION_NAME \
        --runtime=python311 \
        --region=$REGION \
        --source=$SOURCE_DIR \
        --entry-point=update_token \
        --trigger-http \
        --allow-unauthenticated \
        --service-account=$SA_EMAIL \
        --set-env-vars="SERVICE_ACCOUNT_JSON_BASE64=${SERVICE_ACCOUNT_JSON_BASE64},SPREADSHEET_ID=${SPREADSHEET_ID}" \
        --memory=256MB \
        --timeout=60s \
        --no-gen2 \
        --quiet
    FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME --region=$REGION --format="value(httpsTrigger.url)")
fi

# 8. Cloud Scheduler 설정
echo ""
echo "⏰ 자동 실행 설정..."
gcloud scheduler jobs create http veo-token-refresh \
    --location=$REGION \
    --schedule="0 * * * *" \
    --uri=$FUNCTION_URL \
    --http-method=GET \
    --quiet 2>/dev/null || true

# 9. 완료
echo ""
echo "✅ 설치 완료!"
echo "=================="
echo "📊 Google Sheets: https://docs.google.com/spreadsheets/d/$SPREADSHEET_ID"
echo "☁️  Function URL: $FUNCTION_URL"
echo "⏰ 매시간 자동 실행 설정됨"
echo ""
echo "🎉 n8n에서 사용하기:"
echo "1. HTTP Request 노드 추가"
echo "2. Method: GET"
echo "3. URL: https://sheets.googleapis.com/v4/spreadsheets/$SPREADSHEET_ID/values/B2"
echo "4. Authentication: API Key (AIzaSy...)"
echo ""

# 정리
rm -rf $SOURCE_DIR /tmp/test-veo.py