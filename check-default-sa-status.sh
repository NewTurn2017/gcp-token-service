#!/bin/bash
# 기본 서비스 계정 상태 확인 스크립트

echo "🔍 기본 서비스 계정 상태 확인"
echo "============================="
echo ""

PROJECT_ID="warmtalentai"
PROJECT_NUMBER="227871897464"
DEFAULT_SA_EMAIL="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "프로젝트: $PROJECT_ID"
echo "프로젝트 번호: $PROJECT_NUMBER"
echo "기본 서비스 계정: $DEFAULT_SA_EMAIL"
echo ""

# 1. 서비스 계정 존재 확인
echo "1. 서비스 계정 존재 확인..."
if gcloud iam service-accounts describe $DEFAULT_SA_EMAIL 2>/dev/null; then
    echo "✅ 서비스 계정이 존재합니다!"
else
    echo "❌ 서비스 계정을 찾을 수 없습니다"
fi
echo ""

# 2. 서비스 계정 목록 확인
echo "2. 모든 서비스 계정 목록..."
gcloud iam service-accounts list --format="table(email,disabled)"
echo ""

# 3. 서비스 계정 권한 확인
echo "3. 서비스 계정 권한 확인..."
gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:${DEFAULT_SA_EMAIL}" \
    --format="table(bindings.role)"
echo ""

# 4. Cloud Functions 서비스 에이전트 확인
echo "4. Cloud Functions 서비스 에이전트 확인..."
CF_AGENT="service-${PROJECT_NUMBER}@gcf-admin-robot.iam.gserviceaccount.com"
echo "Cloud Functions 에이전트: $CF_AGENT"
if gcloud iam service-accounts describe $CF_AGENT 2>/dev/null; then
    echo "✅ Cloud Functions 에이전트 존재"
else
    echo "❌ Cloud Functions 에이전트 없음"
fi
echo ""

# 5. Cloud Build 서비스 계정 확인
echo "5. Cloud Build 서비스 계정 확인..."
CB_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
echo "Cloud Build 계정: $CB_SA"
if gcloud iam service-accounts describe $CB_SA 2>/dev/null; then
    echo "✅ Cloud Build 계정 존재"
else
    echo "❌ Cloud Build 계정 없음"
fi