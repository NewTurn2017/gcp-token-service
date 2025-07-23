#!/bin/bash
# 기본 서비스 계정 이름으로 서비스 계정 생성하는 스크립트

echo "🚀 기본 서비스 계정 이름으로 Veo 토큰 시스템 설치"
echo "=============================================="
echo ""

# 프로젝트 설정
PROJECT_ID=$(gcloud config get-value project)
if [ -z "$PROJECT_ID" ]; then
    echo -n "프로젝트 ID 입력: "
    read PROJECT_ID
    gcloud config set project $PROJECT_ID
fi

# 프로젝트 번호 가져오기
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
DEFAULT_SA_NAME="${PROJECT_NUMBER}-compute"
DEFAULT_SA_EMAIL="${DEFAULT_SA_NAME}@developer.gserviceaccount.com"

echo "프로젝트: $PROJECT_ID"
echo "프로젝트 번호: $PROJECT_NUMBER"
echo "서비스 계정 이름: $DEFAULT_SA_NAME"
echo "서비스 계정 이메일: $DEFAULT_SA_EMAIL"
echo ""

# 1. API 활성화
echo "📋 필수 API 활성화 중..."
gcloud services enable \
    cloudfunctions.googleapis.com \
    cloudbuild.googleapis.com \
    aiplatform.googleapis.com \
    iam.googleapis.com \
    sheets.googleapis.com \
    compute.googleapis.com \
    --quiet

echo "✅ API 활성화 완료"
echo ""

# 2. 기본 서비스 계정 이름으로 생성
echo "🔑 서비스 계정 생성"
echo "==================="

# 기존 서비스 계정 확인
if gcloud iam service-accounts describe $DEFAULT_SA_EMAIL >/dev/null 2>&1; then
    echo "⚠️  서비스 계정이 이미 존재합니다"
else
    echo "기본 서비스 계정 이름으로 생성 중..."
    gcloud iam service-accounts create "$DEFAULT_SA_NAME" \
        --display-name="Compute Engine default service account" \
        --quiet
    
    if [ $? -eq 0 ]; then
        echo "✅ 서비스 계정 생성 성공!"
    else
        echo "❌ 생성 실패. developer.gserviceaccount.com 도메인은 특별한 권한이 필요할 수 있습니다."
        echo ""
        echo "대신 일반 서비스 계정을 사용합니다..."
        
        # 대체 서비스 계정 생성
        SERVICE_ACCOUNT_NAME="veo-token-sa"
        SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
        
        gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
            --display-name="Veo Token Service Account" \
            --quiet
        
        DEFAULT_SA_EMAIL=$SERVICE_ACCOUNT_EMAIL
        echo "✅ 대체 서비스 계정 생성: $SERVICE_ACCOUNT_EMAIL"
    fi
fi
echo ""

# 3. 권한 부여
echo "🔐 권한 부여"
echo "==========="

# 필요한 권한들
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${DEFAULT_SA_EMAIL}" \
    --role="roles/aiplatform.user" \
    --quiet

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${DEFAULT_SA_EMAIL}" \
    --role="roles/cloudfunctions.invoker" \
    --quiet

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${DEFAULT_SA_EMAIL}" \
    --role="roles/cloudbuild.builds.builder" \
    --quiet

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${DEFAULT_SA_EMAIL}" \
    --role="roles/iam.serviceAccountUser" \
    --quiet

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${DEFAULT_SA_EMAIL}" \
    --role="roles/editor" \
    --quiet

echo "✅ 권한 부여 완료"
echo ""

# 4. 서비스 계정 키 생성
echo "🔑 서비스 계정 키 생성"
echo "===================="
KEY_FILE="$HOME/veo-key.json"

if [ -f "$KEY_FILE" ]; then
    echo "키 파일이 이미 존재합니다"
else
    gcloud iam service-accounts keys create $KEY_FILE \
        --iam-account=$DEFAULT_SA_EMAIL \
        --quiet
    echo "✅ 키 파일 생성 완료: $KEY_FILE"
fi
echo ""

# 5. Google Sheets 설정
echo "📊 Google Sheets 설정"
echo "===================="
echo ""
echo "1. 새 스프레드시트 생성: https://sheets.google.com"
echo "2. '공유' 버튼 클릭"
echo "3. 다음 이메일 추가: $DEFAULT_SA_EMAIL"
echo "4. '편집자' 권한 선택"
echo "5. '무시하고 공유' 클릭"
echo ""
echo -n "스프레드시트 ID 입력: "
read SPREADSHEET_ID

if [ -z "$SPREADSHEET_ID" ]; then
    echo "❌ 스프레드시트 ID가 필요합니다"
    exit 1
fi
echo ""

# 6. Python 패키지 설치
echo "📦 Python 패키지 설치"
echo "===================="
pip3 install --upgrade --quiet \
    google-auth \
    google-auth-oauthlib \
    google-auth-httplib2 \
    google-api-python-client

echo "✅ 패키지 설치 완료"
echo ""

# 7. 테스트 스크립트 생성
echo "🧪 테스트 스크립트 생성"
echo "====================="

cat > ~/test-veo-token.py << EOF
from google.oauth2 import service_account
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from datetime import datetime

# 서비스 계정 파일
SERVICE_ACCOUNT_FILE = '$KEY_FILE'
SPREADSHEET_ID = '$SPREADSHEET_ID'

# Veo API 토큰 생성
credentials = service_account.Credentials.from_service_account_file(
    SERVICE_ACCOUNT_FILE,
    scopes=['https://www.googleapis.com/auth/cloud-platform']
)
credentials.refresh(Request())
token = credentials.token

print(f"✅ 토큰 생성 성공!")
print(f"토큰 (처음 20자): {token[:20]}...")

# Google Sheets 업데이트
sheets_creds = service_account.Credentials.from_service_account_file(
    SERVICE_ACCOUNT_FILE,
    scopes=['https://www.googleapis.com/auth/spreadsheets']
)

service = build('sheets', 'v4', credentials=sheets_creds)

values = [
    ['Last Updated', 'Access Token'],
    [datetime.now().strftime('%Y-%m-%d %H:%M:%S'), token]
]

body = {'values': values}

result = service.spreadsheets().values().update(
    spreadsheetId=SPREADSHEET_ID,
    range='A1:B2',
    valueInputOption='RAW',
    body=body
).execute()

print(f"✅ Google Sheets 업데이트 완료!")
print(f"   https://docs.google.com/spreadsheets/d/{SPREADSHEET_ID}")
EOF

echo "✅ 테스트 스크립트 생성: ~/test-veo-token.py"
echo ""

# 8. 테스트 실행
echo "테스트 실행 중..."
python3 ~/test-veo-token.py

echo ""
echo "🎉 설치 완료!"
echo "============"
echo ""
echo "이제 Cloud Functions 배포를 시도해보세요:"
echo ""
echo "1. 자동 배포:"
echo "   ./complete-setup.sh"
echo ""
echo "2. 수동 배포:"
echo "   Cloud Console에서 함수 생성"
echo "   서비스 계정: $DEFAULT_SA_EMAIL"
echo ""
echo "서비스 계정 정보:"
echo "- 이메일: $DEFAULT_SA_EMAIL"
echo "- 키 파일: $KEY_FILE"
echo "- Google Sheets ID: $SPREADSHEET_ID"