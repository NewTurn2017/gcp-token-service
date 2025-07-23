#!/bin/bash
# 기본 Compute Engine 서비스 계정 재생성 스크립트

echo "🔧 기본 Compute Engine 서비스 계정 재생성"
echo "========================================"
echo ""

PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
DEFAULT_SA_EMAIL="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "프로젝트: $PROJECT_ID"
echo "프로젝트 번호: $PROJECT_NUMBER"
echo "기본 서비스 계정: $DEFAULT_SA_EMAIL"
echo ""

# 현재 상태 확인
echo "1. 현재 서비스 계정 상태 확인..."
if gcloud iam service-accounts describe $DEFAULT_SA_EMAIL >/dev/null 2>&1; then
    echo "✅ 기본 서비스 계정이 이미 존재합니다!"
    exit 0
else
    echo "❌ 기본 서비스 계정이 없습니다. 재생성을 시작합니다..."
fi
echo ""

# Compute Engine API 재활성화로 서비스 계정 생성
echo "2. Compute Engine API 재활성화..."
echo "   (이 과정에서 기본 서비스 계정이 자동 생성됩니다)"
echo ""

# API 비활성화
echo "   API 비활성화 중..."
gcloud services disable compute.googleapis.com --force 2>/dev/null || true

# 잠시 대기
echo "   30초 대기 중..."
sleep 30

# API 재활성화
echo "   API 재활성화 중..."
gcloud services enable compute.googleapis.com

# 추가 대기
echo "   서비스 초기화 대기 중..."
sleep 10

# 결과 확인
echo ""
echo "3. 결과 확인..."
if gcloud iam service-accounts describe $DEFAULT_SA_EMAIL >/dev/null 2>&1; then
    echo "✅ 기본 서비스 계정이 성공적으로 생성되었습니다!"
    
    # 필요한 권한 부여
    echo ""
    echo "4. 필요한 권한 부여 중..."
    
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${DEFAULT_SA_EMAIL}" \
        --role="roles/editor" \
        --quiet
    
    echo "✅ 권한 부여 완료"
    
else
    echo "❌ 여전히 기본 서비스 계정이 생성되지 않았습니다."
    echo ""
    echo "대안 1: Cloud Console에서 Compute Engine 페이지 방문"
    echo "        https://console.cloud.google.com/compute?project=$PROJECT_ID"
    echo ""
    echo "대안 2: 우리가 만든 서비스 계정 사용"
    echo "        veo-token-sa@$PROJECT_ID.iam.gserviceaccount.com"
fi