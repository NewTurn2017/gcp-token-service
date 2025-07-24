#!/bin/bash
# 기존 Cloud Scheduler 업데이트 스크립트

echo "⏰ Cloud Scheduler 업데이트"
echo "=========================="
echo ""

# 프로젝트 설정
PROJECT_ID=$(gcloud config get-value project)
if [ -z "$PROJECT_ID" ]; then
    echo "❌ 프로젝트가 설정되지 않았습니다"
    echo "먼저 실행: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

REGION="us-central1"
JOB_NAME="veo-token-refresh"
FUNCTION_NAME="veo-token-updater"

echo "프로젝트: $PROJECT_ID"
echo "리전: $REGION"
echo "작업 이름: $JOB_NAME"
echo ""

# 현재 스케줄러 상태 확인
echo "1️⃣ 현재 스케줄러 확인..."
if gcloud scheduler jobs describe $JOB_NAME --location=$REGION >/dev/null 2>&1; then
    echo "✅ 기존 스케줄러 발견"
    
    # 현재 설정 표시
    echo ""
    echo "현재 설정:"
    gcloud scheduler jobs describe $JOB_NAME --location=$REGION --format="table(
        name.basename(),
        schedule,
        timeZone,
        state
    )"
else
    echo "❌ 스케줄러를 찾을 수 없습니다"
    echo "먼저 complete-setup.sh를 실행해주세요"
    exit 1
fi

# Function URL 가져오기
echo ""
echo "2️⃣ Cloud Function URL 확인..."
FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME --region=$REGION --gen2 --format="value(serviceConfig.uri)" 2>/dev/null || \
               gcloud functions describe $FUNCTION_NAME --region=$REGION --format="value(httpsTrigger.url)")

if [ -z "$FUNCTION_URL" ]; then
    echo "❌ Cloud Function을 찾을 수 없습니다"
    exit 1
fi
echo "✅ Function URL: $FUNCTION_URL"

# 스케줄러 업데이트
echo ""
echo "3️⃣ 스케줄러 업데이트 중..."
gcloud scheduler jobs update http $JOB_NAME \
    --location=$REGION \
    --schedule="*/30 * * * *" \
    --uri=$FUNCTION_URL \
    --http-method=GET \
    --time-zone="Asia/Seoul" \
    --description="Veo token updater - runs every 30 minutes" \
    --quiet

if [ $? -eq 0 ]; then
    echo "✅ 스케줄러 업데이트 완료!"
    echo ""
    echo "새로운 설정:"
    gcloud scheduler jobs describe $JOB_NAME --location=$REGION --format="table(
        name.basename(),
        schedule,
        timeZone,
        state
    )"
    
    echo ""
    echo "📋 업데이트 내용:"
    echo "- 실행 주기: 30분마다 (*/30 * * * *)"
    echo "- 시간대: Asia/Seoul (한국 표준시)"
    echo ""
    
    # 즉시 실행 옵션
    echo -n "지금 바로 테스트 실행하시겠습니까? (y/N): "
    read TEST_NOW
    
    if [[ "$TEST_NOW" =~ ^[Yy]$ ]]; then
        echo "테스트 실행 중..."
        gcloud scheduler jobs run $JOB_NAME --location=$REGION
        echo "✅ 테스트 실행 완료! Google Sheets를 확인해보세요."
    fi
else
    echo "❌ 업데이트 실패"
fi