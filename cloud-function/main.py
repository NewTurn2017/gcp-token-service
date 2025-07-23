import json
import functions_framework
from google.oauth2 import service_account
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from datetime import datetime
import os

# 환경 변수
SERVICE_ACCOUNT_JSON = os.environ.get('SERVICE_ACCOUNT_JSON')
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
        # 서비스 계정 JSON 파싱
        if not SERVICE_ACCOUNT_JSON:
            return (json.dumps({'error': 'Service account JSON not configured'}), 500, headers)
            
        if not SPREADSHEET_ID:
            return (json.dumps({'error': 'Spreadsheet ID not configured'}), 500, headers)
        
        # 서비스 계정 인증 정보 생성
        service_account_info = json.loads(SERVICE_ACCOUNT_JSON)
        
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