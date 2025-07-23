#!/usr/bin/env python3
import json
from datetime import datetime
from google.oauth2 import service_account
from google.auth.transport.requests import Request
from googleapiclient.discovery import build

# 설정
SERVICE_ACCOUNT_FILE = '/home/admin_/veo-key.json'
SPREADSHEET_ID = '17_CfNpjfxvEGydsFr_PNQX1bTEV8XgRAIvMkJ1O5WHM'
RANGE_NAME = 'A1:B2'  # 시트 이름 없이 시도

def get_veo_token():
    """Veo API용 토큰 생성"""
    credentials = service_account.Credentials.from_service_account_file(
        SERVICE_ACCOUNT_FILE,
        scopes=['https://www.googleapis.com/auth/cloud-platform']
    )
    credentials.refresh(Request())
    return credentials.token

def update_sheet(token):
    """Google Sheets에 토큰 업데이트"""
    creds = service_account.Credentials.from_service_account_file(
        SERVICE_ACCOUNT_FILE,
        scopes=['https://www.googleapis.com/auth/spreadsheets']
    )
    
    service = build('sheets', 'v4', credentials=creds)
    
    # 먼저 시트 정보 확인
    try:
        sheet_metadata = service.spreadsheets().get(spreadsheetId=SPREADSHEET_ID).execute()
        sheets = sheet_metadata.get('sheets', '')
        print(f"사용 가능한 시트: {[sheet['properties']['title'] for sheet in sheets]}")
        
        # 첫 번째 시트 이름 사용
        first_sheet_name = sheets[0]['properties']['title'] if sheets else 'Sheet1'
        range_name = f"{first_sheet_name}!A1:B2"
        print(f"사용할 범위: {range_name}")
    except Exception as e:
        print(f"시트 정보 확인 중 오류: {e}")
        # 실패하면 기본값 사용
        range_name = 'A1:B2'
    
    # 업데이트할 데이터
    values = [
        ['Last Updated', datetime.now().strftime('%Y-%m-%d %H:%M:%S')],
        ['Access Token', token]
    ]
    
    body = {'values': values}
    
    # Sheets 업데이트
    result = service.spreadsheets().values().update(
        spreadsheetId=SPREADSHEET_ID,
        range=range_name,
        valueInputOption='RAW',
        body=body
    ).execute()
    
    print(f"업데이트 완료: {result.get('updatedCells')} 셀")

def main():
    try:
        # 토큰 생성
        token = get_veo_token()
        print(f"토큰 생성 완료: {token[:20]}...")
        
        # Sheets 업데이트
        update_sheet(token)
        print("Google Sheets 업데이트 완료!")
        
        # n8n용 사용법 출력
        print("\n=== n8n에서 사용하기 ===")
        print(f"1. Google Sheets에서 B2 셀의 토큰 읽기")
        print(f"2. 스프레드시트 URL: https://docs.google.com/spreadsheets/d/{SPREADSHEET_ID}")
        print(f"3. 토큰은 1시간마다 자동 갱신됩니다")
        
    except Exception as e:
        print(f"오류 발생: {e}")

if __name__ == "__main__":
    main()