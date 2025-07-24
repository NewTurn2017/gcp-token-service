#!/bin/bash
# Cloud Function 업데이트 스크립트 (강화된 에러 처리)

echo "🔄 Cloud Function 업데이트"
echo "========================="
echo ""

# 프로젝트 설정
PROJECT_ID=$(gcloud config get-value project)
if [ -z "$PROJECT_ID" ]; then
    echo "❌ 프로젝트가 설정되지 않았습니다"
    exit 1
fi

FUNCTION_NAME="veo-token-updater"
REGION="us-central1"
SA_NAME="veo-token-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
KEY_FILE="$HOME/veo-key.json"

# 스프레드시트 ID 입력
echo -n "스프레드시트 ID: "
read SPREADSHEET_ID

if [ -z "$SPREADSHEET_ID" ]; then
    echo "❌ 스프레드시트 ID가 필요합니다"
    exit 1
fi

# 소스 디렉토리 생성
SOURCE_DIR="/tmp/veo-function-update"
rm -rf $SOURCE_DIR
mkdir -p $SOURCE_DIR

# 강화된 main.py 생성
cat > $SOURCE_DIR/main.py << 'EOF'
import json
import functions_framework
from google.oauth2 import service_account
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from datetime import datetime, timezone, timedelta
import os
import base64
import time
import logging

# 로깅 설정
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def update_token(request):
    """강화된 토큰 업데이트 함수"""
    headers = {'Access-Control-Allow-Origin': '*'}
    
    # CORS preflight 처리
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # 환경 변수 확인
        service_account_json_base64 = os.environ.get('SERVICE_ACCOUNT_JSON_BASE64')
        spreadsheet_id = os.environ.get('SPREADSHEET_ID')
        project_id = os.environ.get('PROJECT_ID')
        
        if not all([service_account_json_base64, spreadsheet_id, project_id]):
            logger.error("Missing environment variables")
            return (json.dumps({'error': 'Missing configuration'}), 500, headers)
        
        # 서비스 계정 정보 디코딩
        service_account_json = base64.b64decode(service_account_json_base64).decode('utf-8')
        service_account_info = json.loads(service_account_json)
        
        # 재시도 로직으로 토큰 생성
        max_retries = 3
        retry_delay = 2
        
        for attempt in range(max_retries):
            try:
                logger.info(f"토큰 생성 시도 {attempt + 1}/{max_retries}")
                
                # Veo API 토큰 생성
                credentials = service_account.Credentials.from_service_account_info(
                    service_account_info,
                    scopes=['https://www.googleapis.com/auth/cloud-platform']
                )
                credentials.refresh(Request())
                token = credentials.token
                
                if not token:
                    raise Exception("토큰이 비어있습니다")
                
                logger.info(f"토큰 생성 성공: {len(token)} 문자")
                break
                
            except Exception as e:
                logger.error(f"토큰 생성 실패 (시도 {attempt + 1}): {str(e)}")
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                    retry_delay *= 2
                else:
                    raise
        
        # Google Sheets 업데이트 (재시도 포함)
        for attempt in range(max_retries):
            try:
                logger.info(f"Sheets 업데이트 시도 {attempt + 1}/{max_retries}")
                
                sheets_creds = service_account.Credentials.from_service_account_info(
                    service_account_info,
                    scopes=['https://www.googleapis.com/auth/spreadsheets']
                )
                
                service = build('sheets', 'v4', credentials=sheets_creds, cache_discovery=False)
                
                # 한국 시간
                KST = timezone(timedelta(hours=9))
                current_time = datetime.now(KST).strftime('%Y-%m-%d %H:%M:%S')
                
                values = [
                    ['Project ID', 'Last Updated (KST)', 'Access Token'],
                    [project_id, current_time, token]
                ]
                
                # 배치 업데이트로 한 번에 처리
                batch_update_request = {
                    'valueInputOption': 'RAW',
                    'data': [
                        {
                            'range': 'A1:C2',
                            'values': values
                        }
                    ]
                }
                
                result = service.spreadsheets().values().batchUpdate(
                    spreadsheetId=spreadsheet_id,
                    body=batch_update_request
                ).execute()
                
                logger.info(f"Sheets 업데이트 성공: {result.get('totalUpdatedCells')} 셀")
                
                # 성공 응답
                response_data = {
                    'status': 'success',
                    'message': f"Updated {result.get('totalUpdatedCells')} cells",
                    'timestamp': current_time,
                    'token_length': len(token),
                    'project_id': project_id
                }
                
                return (json.dumps(response_data), 200, headers)
                
            except HttpError as e:
                logger.error(f"Sheets API 오류 (시도 {attempt + 1}): {e.resp.status} - {e.content}")
                if e.resp.status == 429:  # Rate limit
                    time.sleep(10)
                elif attempt < max_retries - 1:
                    time.sleep(retry_delay)
                else:
                    raise
            except Exception as e:
                logger.error(f"Sheets 업데이트 실패 (시도 {attempt + 1}): {str(e)}")
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                else:
                    raise
        
    except Exception as e:
        logger.error(f"치명적 오류: {str(e)}", exc_info=True)
        error_response = {
            'status': 'error',
            'message': str(e),
            'timestamp': datetime.now(timezone(timedelta(hours=9))).isoformat()
        }
        return (json.dumps(error_response), 500, headers)
EOF

# requirements.txt
cat > $SOURCE_DIR/requirements.txt << 'EOF'
functions-framework==3.*
google-auth==2.*
google-auth-httplib2==0.*
google-api-python-client==2.*
EOF

# Base64 인코딩
echo "서비스 계정 키 인코딩 중..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    SERVICE_ACCOUNT_JSON_BASE64=$(cat "$KEY_FILE" | base64)
else
    SERVICE_ACCOUNT_JSON_BASE64=$(cat "$KEY_FILE" | base64 -w 0)
fi

# 기존 함수 백업 정보 저장
echo ""
echo "기존 Cloud Function 백업 정보 저장 중..."
gcloud functions describe $FUNCTION_NAME --region=$REGION --format=json > /tmp/function-backup.json 2>/dev/null || true

# Cloud Function 재배포
echo ""
echo "☁️ Cloud Function 재배포 중..."

# Gen2 우선 시도
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

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Cloud Function 업데이트 완료!"
    echo ""
    echo "📋 업데이트 내용:"
    echo "- 재시도 로직 추가 (3회)"
    echo "- 상세한 로깅 추가"
    echo "- Rate limit 처리"
    echo "- 배치 업데이트로 성능 개선"
    echo "- 메모리 512MB로 증가"
    echo "- 타임아웃 120초로 증가"
    echo ""
    echo "🧪 테스트 실행..."
    
    # 함수 테스트
    sleep 5  # 배포 완료 대기
    RESPONSE=$(curl -s $FUNCTION_URL)
    echo "응답: $RESPONSE"
    
    # 스케줄러 업데이트도 제안
    echo ""
    echo "💡 스케줄러도 업데이트하시겠습니까?"
    echo "   ./update-scheduler.sh"
else
    echo "❌ 배포 실패"
    echo "백업 정보: /tmp/function-backup.json"
fi

# 정리
rm -rf $SOURCE_DIR