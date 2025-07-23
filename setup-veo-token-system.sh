#!/bin/bash
# Veo 3.0 토큰 시스템 설치 스크립트

set -e

echo "🚀 Veo 3.0 토큰 시스템 설치 시작..."
echo "================================="

# 프로젝트 설정
PROJECT_ID=$(gcloud config get-value project)
if [ -z "$PROJECT_ID" ]; then
    echo "❌ Error: 프로젝트가 설정되지 않았습니다."
    echo "실행: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

echo "📋 프로젝트: $PROJECT_ID"
echo ""

# 1. API 활성화
echo "1️⃣ 필수 API 활성화..."
gcloud services enable \
    aiplatform.googleapis.com \
    iam.googleapis.com \
    sheets.googleapis.com \
    --quiet

echo "✅ API 활성화 완료"
echo ""

# 2. 서비스 계정 생성
echo "2️⃣ 서비스 계정 생성..."
SERVICE_ACCOUNT_NAME="veo-api-sa"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# 서비스 계정이 이미 존재하는지 확인
if gcloud iam service-accounts describe $SERVICE_ACCOUNT_EMAIL >/dev/null 2>&1; then
    echo "✅ 서비스 계정이 이미 존재합니다: $SERVICE_ACCOUNT_EMAIL"
else
    gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
        --display-name="Veo API Service Account" \
        --quiet
    echo "✅ 서비스 계정 생성 완료: $SERVICE_ACCOUNT_EMAIL"
fi
echo ""

# 3. 필요한 권한 부여
echo "3️⃣ 서비스 계정에 권한 부여..."

# Vertex AI User 권한
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/aiplatform.user" \
    --quiet

# Storage Object Viewer 권한
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/storage.objectViewer" \
    --quiet

# 편집자 권한 (Sheets API 사용을 위해)
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/editor" \
    --quiet

echo "✅ 권한 부여 완료"
echo ""

# 4. 서비스 계정 키 생성
echo "4️⃣ 서비스 계정 키 생성..."
KEY_FILE="$HOME/veo-key.json"

if [ -f "$KEY_FILE" ]; then
    echo "⚠️  키 파일이 이미 존재합니다. 새로 생성하시겠습니까? (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        gcloud iam service-accounts keys create $KEY_FILE \
            --iam-account=$SERVICE_ACCOUNT_EMAIL \
            --quiet
        echo "✅ 새 키 파일 생성 완료: $KEY_FILE"
    else
        echo "✅ 기존 키 파일 사용: $KEY_FILE"
    fi
else
    gcloud iam service-accounts keys create $KEY_FILE \
        --iam-account=$SERVICE_ACCOUNT_EMAIL \
        --quiet
    echo "✅ 키 파일 생성 완료: $KEY_FILE"
fi
echo ""

# 5. Python 패키지 설치
echo "5️⃣ Python 패키지 설치..."
pip3 install --upgrade \
    google-auth \
    google-auth-oauthlib \
    google-auth-httplib2 \
    google-api-python-client \
    --quiet

echo "✅ 패키지 설치 완료"
echo ""

# 6. 토큰 업데이트 스크립트 다운로드
echo "6️⃣ 토큰 업데이트 스크립트 다운로드..."
curl -sL https://raw.githubusercontent.com/NewTurn2017/gcp-token-service/main/update-token-to-sheets.py \
    -o ~/update-token-to-sheets.py

chmod +x ~/update-token-to-sheets.py
echo "✅ 스크립트 다운로드 완료"
echo ""

# 7. 테스트 실행
echo "7️⃣ 설정 및 테스트"
echo "================================="
echo "스크립트가 Google Sheets ID를 입력받도록 대화형으로 실행됩니다."
echo ""
echo "Google Sheets 준비:"
echo "1. 새 스프레드시트 생성: https://sheets.google.com"
echo "2. 공유 → 서비스 계정 이메일($SERVICE_ACCOUNT_EMAIL) 추가 → 편집자 권한"
echo "3. URL에서 ID 복사"
echo ""

# 대화형 모드로 실행
python3 ~/update-token-to-sheets.py

echo ""
echo "9️⃣ Cron 작업 설정 (매시간 자동 갱신)"
echo "================================="
echo "다음 명령을 실행하여 crontab을 편집하세요:"
echo "  crontab -e"
echo ""
echo "그리고 다음 줄을 추가하세요:"
echo "  5 * * * * /usr/bin/python3 $HOME/update-token-to-sheets.py >> $HOME/token-update.log 2>&1"
echo ""

echo "✨ 설치 완료!"
echo ""
echo "📝 n8n에서 사용하기:"
echo "1. Google Sheets 노드로 B2 셀의 토큰 읽기"
echo "2. HTTP Request 노드에서 Authorization: Bearer [토큰] 헤더 사용"
echo "3. Veo 3.0 API 엔드포인트: https://us-central1-aiplatform.googleapis.com/v1/projects/$PROJECT_ID/locations/us-central1/publishers/google/models/veo-3.0-generate-preview:predictLongRunning"