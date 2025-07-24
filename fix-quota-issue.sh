#!/bin/bash
# Google Sheets API 할당량 문제 해결 스크립트

echo "🔧 Google Sheets API 할당량 문제 해결"
echo "===================================="
echo ""

PROJECT_ID=$(gcloud config get-value project)

# 1. 현재 할당량 상태 확인
echo "📊 현재 API 할당량 상태 확인"
echo "https://console.cloud.google.com/apis/api/sheets.googleapis.com/quotas?project=$PROJECT_ID"
echo ""

# 2. Cloud Function 업데이트 준비
echo "⚡ Cloud Function 최적화 업데이트 준비"
SOURCE_DIR="/tmp/veo-function-quota-fix"
rm -rf $SOURCE_DIR
mkdir -p $SOURCE_DIR

# 최적화된 main.py 생성
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

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 글로벌 변수로 서비스 객체 캐싱
_sheets_service = None

def get_sheets_service(service_account_info):
    """Sheets 서비스 객체를 캐싱하여 재사용"""
    global _sheets_service
    if _sheets_service is None:
        sheets_creds = service_account.Credentials.from_service_account_info(
            service_account_info,
            scopes=['https://www.googleapis.com/auth/spreadsheets']
        )
        _sheets_service = build('sheets', 'v4', credentials=sheets_creds, cache_discovery=False)
    return _sheets_service

@functions_framework.http
def update_token(request):
    """할당량 최적화된 토큰 업데이트 함수"""
    headers = {'Access-Control-Allow-Origin': '*'}
    
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
        
        # 토큰 생성 (재시도 최소화)
        max_retries = 2  # 3번에서 2번으로 감소
        retry_delay = 5   # 2초에서 5초로 증가
        
        token = None
        for attempt in range(max_retries):
            try:
                logger.info(f"토큰 생성 시도 {attempt + 1}/{max_retries}")
                
                credentials = service_account.Credentials.from_service_account_info(
                    service_account_info,
                    scopes=['https://www.googleapis.com/auth/cloud-platform']
                )
                credentials.refresh(Request())
                token = credentials.token
                
                if token:
                    logger.info(f"토큰 생성 성공: {len(token)} 문자")
                    break
                    
            except Exception as e:
                logger.error(f"토큰 생성 실패 (시도 {attempt + 1}): {str(e)}")
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                else:
                    raise
        
        if not token:
            raise Exception("토큰 생성 실패")
        
        # Sheets 업데이트 (할당량 최적화)
        try:
            logger.info("Sheets 업데이트 시도")
            
            # 캐싱된 서비스 객체 사용
            service = get_sheets_service(service_account_info)
            
            # 한국 시간
            KST = timezone(timedelta(hours=9))
            current_time = datetime.now(KST).strftime('%Y-%m-%d %H:%M:%S')
            
            # 단일 셀 업데이트로 API 호출 최소화
            values = [[project_id, current_time, token]]
            
            # 헤더는 이미 있다고 가정하고 데이터만 업데이트
            result = service.spreadsheets().values().update(
                spreadsheetId=spreadsheet_id,
                range='A2:C2',  # 헤더 제외
                valueInputOption='RAW',
                body={'values': values}
            ).execute()
            
            logger.info(f"Sheets 업데이트 성공: {result.get('updatedCells')} 셀")
            
            return (json.dumps({
                'status': 'success',
                'timestamp': current_time,
                'cells_updated': result.get('updatedCells')
            }), 200, headers)
            
        except HttpError as e:
            if e.resp.status == 429:
                # 할당량 초과 시 자세한 로깅
                logger.error(f"Quota exceeded: {e}")
                return (json.dumps({
                    'error': 'Quota exceeded',
                    'message': 'Google Sheets API quota limit reached. Please wait.',
                    'retry_after': '60 seconds'
                }), 429, headers)
            else:
                raise
                
    except Exception as e:
        logger.error(f"치명적 오류: {str(e)}", exc_info=True)
        return (json.dumps({'error': str(e)}), 500, headers)
EOF

# requirements.txt
cat > $SOURCE_DIR/requirements.txt << 'EOF'
functions-framework==3.*
google-auth==2.*
google-auth-httplib2==0.*
google-api-python-client==2.*
EOF

echo ""
echo "3. 스케줄러 빈도 조정 옵션"
echo "현재: 30분마다 실행"
echo ""
echo "할당량 문제가 지속되면 실행 빈도를 줄이는 것을 고려하세요:"
echo "- 1시간마다: */60 * * * *"
echo "- 45분마다: */45 * * * *"
echo ""

echo "4. 할당량 증가 요청"
echo "프로젝트의 할당량을 증가시키려면:"
echo "1. https://console.cloud.google.com/apis/api/sheets.googleapis.com/quotas 방문"
echo "2. '할당량 증가 요청' 클릭"
echo "3. 필요한 할당량 입력 후 제출"
echo ""

echo "📝 권장 사항:"
echo "1. 이 스크립트를 실행하여 Cloud Function 최적화"
echo "2. 필요시 스케줄러 빈도 조정"
echo "3. 장기적으로는 할당량 증가 요청"
echo ""

echo "Cloud Function을 업데이트하시겠습니까? (y/n)"
read -r response

if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "Cloud Function 업데이트 중..."
    
    # 기존 설정 가져오기
    FUNCTION_NAME="veo-token-updater"
    REGION="us-central1"
    SA_NAME="veo-token-sa"
    SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    KEY_FILE="$HOME/veo-key.json"
    
    echo -n "스프레드시트 ID: "
    read SPREADSHEET_ID
    
    # Base64 인코딩
    if [[ "$OSTYPE" == "darwin"* ]]; then
        SERVICE_ACCOUNT_JSON_BASE64=$(cat "$KEY_FILE" | base64)
    else
        SERVICE_ACCOUNT_JSON_BASE64=$(cat "$KEY_FILE" | base64 -w 0)
    fi
    
    # Cloud Function 재배포
    gcloud functions deploy $FUNCTION_NAME \
        --gen2 \
        --runtime=python311 \
        --region=$REGION \
        --source=$SOURCE_DIR \
        --entry-point=update_token \
        --trigger-http \
        --allow-unauthenticated \
        --run-service-account=$SA_EMAIL \
        --set-env-vars="SERVICE_ACCOUNT_JSON_BASE64=${SERVICE_ACCOUNT_JSON_BASE64},SPREADSHEET_ID=${SPREADSHEET_ID},PROJECT_ID=${PROJECT_ID}" \
        --memory=256MB \
        --timeout=60s \
        --max-instances=10 \
        --quiet
    
    echo "✅ Cloud Function 업데이트 완료!"
    echo ""
    echo "💡 추가 조치:"
    echo "1. 1시간 정도 대기 후 다시 시도"
    echo "2. 필요시 ./update-scheduler.sh 실행하여 빈도 조정"
fi

# 정리
rm -rf $SOURCE_DIR