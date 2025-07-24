#!/bin/bash
# Veo 3.0 토큰 자동화 시스템 - 최종 설치 스크립트

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
gcloud services enable \
    cloudfunctions.googleapis.com \
    cloudbuild.googleapis.com \
    aiplatform.googleapis.com \
    sheets.googleapis.com \
    cloudscheduler.googleapis.com \
    --quiet

# 2. 서비스 계정 생성
echo "🔑 서비스 계정 설정..."
SA_NAME="veo-token-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if ! gcloud iam service-accounts describe $SA_EMAIL >/dev/null 2>&1; then
    gcloud iam service-accounts create $SA_NAME --display-name="Veo Token Service" --quiet
fi

# 3. 권한 부여
echo "🔐 권한 부여..."
for role in "roles/aiplatform.user" "roles/editor" "roles/sheets.editor"; do
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="$role" \
        --quiet >/dev/null 2>&1
done

# Cloud Scheduler 서비스 계정 준비
SCHEDULER_SA="service-${PROJECT_NUMBER}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"

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

# 대화형 입력 처리
echo -n "스프레드시트 ID: "
if [ -t 0 ]; then
    read SPREADSHEET_ID
else
    read SPREADSHEET_ID < /dev/tty
fi

if [ -z "$SPREADSHEET_ID" ]; then
    echo "❌ 스프레드시트 ID가 필요합니다"
    exit 1
fi

echo "입력된 ID: $SPREADSHEET_ID"

# 6. 연결 테스트
echo ""
echo "🧪 연결 테스트 준비 중..."
cat > /tmp/test-veo.py << EOF
from google.oauth2 import service_account
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from datetime import datetime, timezone, timedelta

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

KST = timezone(timedelta(hours=9))
values = [['Project ID', 'Last Updated (KST)', 'Access Token'], 
          ['$PROJECT_ID', datetime.now(KST).strftime('%Y-%m-%d %H:%M:%S'), credentials.token]]

service.spreadsheets().values().update(
    spreadsheetId='$SPREADSHEET_ID',
    range='A1:C2',
    valueInputOption='RAW',
    body={'values': values}
).execute()
print("✅ Sheets 업데이트 성공!")
EOF

echo "Python 패키지 설치 중..."
if command -v python3 &> /dev/null; then
    PY_CMD="python3"
    PIP_CMD="pip3"
else
    PY_CMD="python"
    PIP_CMD="pip"
fi

$PIP_CMD install -q google-auth google-auth-oauthlib google-auth-httplib2 google-api-python-client || {
    echo "⚠️  Python 패키지 설치 실패"
    exit 1
}

echo "테스트 실행 중..."
$PY_CMD /tmp/test-veo.py || {
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
from datetime import datetime, timezone, timedelta
import os
import base64
import time
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def update_token(request):
    headers = {'Access-Control-Allow-Origin': '*'}
    
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    max_retries = 3
    retry_delay = 2
    
    try:
        service_account_json = base64.b64decode(os.environ.get('SERVICE_ACCOUNT_JSON_BASE64')).decode('utf-8')
        service_account_info = json.loads(service_account_json)
        
        # 토큰 생성 (재시도 포함)
        for attempt in range(max_retries):
            try:
                logger.info(f"토큰 생성 시도 {attempt + 1}/{max_retries}")
                credentials = service_account.Credentials.from_service_account_info(
                    service_account_info,
                    scopes=['https://www.googleapis.com/auth/cloud-platform']
                )
                credentials.refresh(Request())
                token = credentials.token
                logger.info(f"토큰 생성 성공: {len(token)} 문자")
                break
            except Exception as e:
                logger.error(f"토큰 생성 실패 (시도 {attempt + 1}): {str(e)}")
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                    retry_delay *= 2
                else:
                    raise
        
        # Sheets 업데이트 (재시도 포함)
        for attempt in range(max_retries):
            try:
                logger.info(f"Sheets 업데이트 시도 {attempt + 1}/{max_retries}")
                sheets_creds = service_account.Credentials.from_service_account_info(
                    service_account_info,
                    scopes=['https://www.googleapis.com/auth/spreadsheets']
                )
                
                service = build('sheets', 'v4', credentials=sheets_creds, cache_discovery=False)
                KST = timezone(timedelta(hours=9))
                current_time = datetime.now(KST).strftime('%Y-%m-%d %H:%M:%S')
                
                values = [
                    ['Project ID', 'Last Updated (KST)', 'Access Token'],
                    [os.environ.get('PROJECT_ID', 'Unknown'), current_time, token]
                ]
                
                result = service.spreadsheets().values().update(
                    spreadsheetId=os.environ.get('SPREADSHEET_ID'),
                    range='A1:C2',
                    valueInputOption='RAW',
                    body={'values': values}
                ).execute()
                
                logger.info(f"Sheets 업데이트 성공: {result.get('updatedCells')} 셀")
                
                return (json.dumps({
                    'status': 'success',
                    'timestamp': current_time,
                    'cells_updated': result.get('updatedCells')
                }), 200, headers)
                
            except Exception as e:
                logger.error(f"Sheets 업데이트 실패 (시도 {attempt + 1}): {str(e)}")
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                else:
                    raise
                    
    except Exception as e:
        logger.error(f"치명적 오류: {str(e)}", exc_info=True)
        return (json.dumps({'error': str(e)}), 500, headers)
EOF

cat > $SOURCE_DIR/requirements.txt << 'EOF'
functions-framework==3.*
google-auth==2.*
google-auth-httplib2==0.*
google-api-python-client==2.*
EOF

# Base64 인코딩 (OS별 처리)
if [[ "$OSTYPE" == "darwin"* ]]; then
    SERVICE_ACCOUNT_JSON_BASE64=$(cat "$KEY_FILE" | base64)
else
    SERVICE_ACCOUNT_JSON_BASE64=$(cat "$KEY_FILE" | base64 -w 0)
fi

# 배포
FUNCTION_NAME="veo-token-updater"
REGION="us-central1"

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
    --set-env-vars="SERVICE_ACCOUNT_JSON_BASE64=${SERVICE_ACCOUNT_JSON_BASE64},SPREADSHEET_ID=${SPREADSHEET_ID},PROJECT_ID=${PROJECT_ID}" \
    --memory=512MB \
    --timeout=120s \
    --max-instances=100 \
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
        --set-env-vars="SERVICE_ACCOUNT_JSON_BASE64=${SERVICE_ACCOUNT_JSON_BASE64},SPREADSHEET_ID=${SPREADSHEET_ID},PROJECT_ID=${PROJECT_ID}" \
        --memory=512MB \
        --timeout=120s \
        --max-instances=100 \
        --no-gen2 \
        --quiet
    FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME --region=$REGION --format="value(httpsTrigger.url)")
fi

# Cloud Function 호출 권한 부여
echo ""
echo "🔓 Cloud Function 접근 권한 설정..."
gcloud functions add-iam-policy-binding $FUNCTION_NAME \
    --region=$REGION \
    --member="serviceAccount:${SCHEDULER_SA}" \
    --role="roles/cloudfunctions.invoker" \
    --quiet 2>/dev/null || {
    # Gen2인 경우 Cloud Run 권한
    gcloud run services add-iam-policy-binding $FUNCTION_NAME \
        --region=$REGION \
        --member="serviceAccount:${SCHEDULER_SA}" \
        --role="roles/run.invoker" \
        --quiet 2>/dev/null || true
}

# 8. Cloud Scheduler 설정
echo ""
echo "⏰ 자동 실행 설정..."
gcloud scheduler jobs create http veo-token-refresh \
    --location=$REGION \
    --schedule="*/30 * * * *" \
    --uri=$FUNCTION_URL \
    --http-method=GET \
    --time-zone="Asia/Seoul" \
    --oidc-service-account-email=$SCHEDULER_SA \
    --quiet 2>/dev/null || true

# 9. 완료
echo ""
echo "✅ 설치 완료!"
echo "=================="
echo "📊 Google Sheets: https://docs.google.com/spreadsheets/d/$SPREADSHEET_ID"
echo "☁️  Function URL: $FUNCTION_URL"
echo "⏰ 30분마다 자동 실행 (KST)"
echo ""
echo "🎉 n8n에서 사용하기:"
echo "1. HTTP Request 노드 추가"
echo "2. Method: GET"
echo "3. URL: https://sheets.googleapis.com/v4/spreadsheets/$SPREADSHEET_ID/values/C2"
echo "4. Authentication: API Key (AIzaSy...)"
echo "   (토큰은 C2 셀, 프로젝트 ID는 A2 셀에 저장됩니다)"
echo ""

# 정리
rm -rf $SOURCE_DIR /tmp/test-veo.py