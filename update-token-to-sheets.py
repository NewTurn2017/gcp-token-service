#!/usr/bin/env python3
import json
import os
import sys
import argparse
from datetime import datetime
from google.oauth2 import service_account
from google.auth.transport.requests import Request
from googleapiclient.discovery import build

# 기본 설정
DEFAULT_SERVICE_ACCOUNT_FILE = os.path.expanduser('~/veo-key.json')
DEFAULT_RANGE = 'A1:B2'
CONFIG_FILE = os.path.expanduser('~/.veo-token-config.json')

def load_config():
    """저장된 설정 불러오기"""
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                return json.load(f)
        except:
            return {}
    return {}

def save_config(config):
    """설정 저장하기"""
    try:
        with open(CONFIG_FILE, 'w') as f:
            json.dump(config, f, indent=2)
    except Exception as e:
        print(f"설정 저장 중 오류: {e}")

def get_veo_token(service_account_file):
    """Veo API용 토큰 생성"""
    credentials = service_account.Credentials.from_service_account_file(
        service_account_file,
        scopes=['https://www.googleapis.com/auth/cloud-platform']
    )
    credentials.refresh(Request())
    return credentials.token

def update_sheet(token, spreadsheet_id, service_account_file):
    """Google Sheets에 토큰 업데이트"""
    creds = service_account.Credentials.from_service_account_file(
        service_account_file,
        scopes=['https://www.googleapis.com/auth/spreadsheets']
    )
    
    service = build('sheets', 'v4', credentials=creds)
    
    # 먼저 시트 정보 확인
    try:
        sheet_metadata = service.spreadsheets().get(spreadsheetId=spreadsheet_id).execute()
        sheets = sheet_metadata.get('sheets', '')
        
        # 첫 번째 시트 이름 사용
        first_sheet_name = sheets[0]['properties']['title'] if sheets else 'Sheet1'
        range_name = f"{first_sheet_name}!{DEFAULT_RANGE}"
    except Exception as e:
        print(f"시트 정보 확인 중 오류: {e}")
        # 실패하면 기본값 사용
        range_name = DEFAULT_RANGE
    
    # 업데이트할 데이터 (헤더와 값을 행으로 배치)
    values = [
        ['Last Updated', 'Access Token'],  # 헤더 (A1, B1)
        [datetime.now().strftime('%Y-%m-%d %H:%M:%S'), token]  # 값 (A2, B2)
    ]
    
    body = {'values': values}
    
    # Sheets 업데이트
    result = service.spreadsheets().values().update(
        spreadsheetId=spreadsheet_id,
        range=range_name,
        valueInputOption='RAW',
        body=body
    ).execute()
    
    print(f"✅ 업데이트 완료: {result.get('updatedCells')} 셀")
    return True

def main():
    parser = argparse.ArgumentParser(
        description='Veo 3.0 API 토큰을 Google Sheets에 업데이트합니다.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
예제:
  # 처음 실행 (대화형 모드)
  python3 update-token-to-sheets.py
  
  # 스프레드시트 ID 지정
  python3 update-token-to-sheets.py --spreadsheet-id YOUR_SHEET_ID
  
  # 서비스 계정 파일 지정
  python3 update-token-to-sheets.py --key-file /path/to/key.json
  
  # 저장된 설정 확인
  python3 update-token-to-sheets.py --show-config
"""
    )
    
    parser.add_argument('--spreadsheet-id', help='Google Sheets ID')
    parser.add_argument('--key-file', default=DEFAULT_SERVICE_ACCOUNT_FILE,
                        help=f'서비스 계정 키 파일 경로 (기본값: {DEFAULT_SERVICE_ACCOUNT_FILE})')
    parser.add_argument('--save', action='store_true',
                        help='스프레드시트 ID를 저장하여 다음에 재사용')
    parser.add_argument('--show-config', action='store_true',
                        help='저장된 설정 표시')
    
    args = parser.parse_args()
    
    # 저장된 설정 불러오기
    config = load_config()
    
    # 설정 표시
    if args.show_config:
        if config:
            print("📋 저장된 설정:")
            print(json.dumps(config, indent=2))
        else:
            print("⚠️  저장된 설정이 없습니다.")
        return
    
    # 스프레드시트 ID 결정
    spreadsheet_id = args.spreadsheet_id
    if not spreadsheet_id and 'spreadsheet_id' in config:
        spreadsheet_id = config['spreadsheet_id']
        print(f"💾 저장된 스프레드시트 ID 사용: {spreadsheet_id}")
    
    # 스프레드시트 ID가 없으면 입력 받기
    if not spreadsheet_id:
        print("🔗 Google Sheets 설정")
        print("1. 새 스프레드시트 생성: https://sheets.google.com")
        print("2. URL에서 ID 복사 (https://docs.google.com/spreadsheets/d/ID_HERE/edit)")
        print("3. 공유 버튼 → 서비스 계정 이메일 추가 → 편집자 권한")
        print("")
        spreadsheet_id = input("스프레드시트 ID 입력: ").strip()
        
        if not spreadsheet_id:
            print("❌ 스프레드시트 ID가 필요합니다.")
            return
    
    # 서비스 계정 파일 확인
    service_account_file = args.key_file
    if not os.path.exists(service_account_file):
        print(f"❌ 서비스 계정 키 파일을 찾을 수 없습니다: {service_account_file}")
        print("💡 파일 경로를 확인하거나 --key-file 옵션으로 지정하세요.")
        return
    
    try:
        # 서비스 계정 이메일 표시
        with open(service_account_file, 'r') as f:
            sa_data = json.load(f)
            sa_email = sa_data.get('client_email', 'Unknown')
            print(f"🔑 서비스 계정: {sa_email}")
        
        # 토큰 생성
        print("🔄 토큰 생성 중...")
        token = get_veo_token(service_account_file)
        print(f"✅ 토큰 생성 완료: {token[:20]}...")
        
        # Sheets 업데이트
        print(f"📊 Google Sheets 업데이트 중...")
        if update_sheet(token, spreadsheet_id, service_account_file):
            # 설정 저장
            if args.save or (not 'spreadsheet_id' in config and 
                           input("\n💾 이 스프레드시트 ID를 저장하시겠습니까? (y/N): ").lower() == 'y'):
                config['spreadsheet_id'] = spreadsheet_id
                save_config(config)
                print(f"✅ 설정이 저장되었습니다: {CONFIG_FILE}")
            
            # 사용법 안내
            print("\n=== 성공! ===")
            print(f"📊 스프레드시트: https://docs.google.com/spreadsheets/d/{spreadsheet_id}")
            print("📍 토큰 위치: B2 셀")
            print("\n=== n8n에서 사용하기 ===")
            print("1. Google Sheets 노드: B2 셀 읽기")
            print("2. HTTP Request 노드: Authorization: Bearer {{토큰}}")
            print("\n=== 자동 갱신 설정 ===")
            print("crontab -e 실행 후 다음 줄 추가:")
            print(f"5 * * * * /usr/bin/python3 {os.path.abspath(__file__)} >> ~/token-update.log 2>&1")
        
    except Exception as e:
        print(f"❌ 오류 발생: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()