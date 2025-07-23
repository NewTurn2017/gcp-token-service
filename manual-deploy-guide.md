# Cloud Console에서 수동 배포 가이드

기본 서비스 계정 문제로 자동 배포가 안 될 때 수동으로 배포하는 방법입니다.

## 1. Cloud Console 접속

브라우저에서 다음 URL 열기:
```
https://console.cloud.google.com/functions/add?project=YOUR_PROJECT_ID
```

## 2. 함수 설정

### 기본 정보
- **환경**: 1세대
- **함수 이름**: `veo-token-updater`
- **리전**: `us-central1`

### 트리거
- **트리거 유형**: HTTP
- **인증**: 인증되지 않은 호출 허용

### 런타임 설정
- **런타임**: Python 3.11
- **진입점**: `update_token`
- **메모리**: 256MB
- **제한 시간**: 60초

## 3. 소스 코드

### main.py
```python
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
```

### requirements.txt
```
functions-framework==3.*
google-auth==2.* 
google-auth-oauthlib==1.*
google-auth-httplib2==0.*
google-api-python-client==2.*
```

## 4. 환경 변수 설정

### SERVICE_ACCOUNT_JSON_BASE64 생성 방법

Cloud Shell에서:
```bash
# 서비스 계정 키를 Base64로 인코딩
cat ~/veo-key.json | base64 -w 0
```

출력된 긴 문자열을 복사합니다.

### 환경 변수 추가
- **SERVICE_ACCOUNT_JSON_BASE64**: 위에서 복사한 Base64 문자열
- **SPREADSHEET_ID**: Google Sheets ID (예: 17_CfNpjfxvEGydsFr_PNQX1bTEV8XgRAIvMkJ1O5WHM)

## 5. 서비스 계정 설정

**런타임 서비스 계정**: `veo-token-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com`

## 6. 배포

"배포" 버튼 클릭

## 7. 테스트

배포 완료 후:
1. 함수 URL 복사
2. 브라우저나 curl로 테스트:
   ```bash
   curl https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/veo-token-updater
   ```

## 8. Cloud Scheduler 설정 (선택사항)

매시간 자동 실행:
```bash
gcloud scheduler jobs create http veo-token-scheduler \
    --location=us-central1 \
    --schedule="5 * * * *" \
    --uri=YOUR_FUNCTION_URL \
    --http-method=GET
```