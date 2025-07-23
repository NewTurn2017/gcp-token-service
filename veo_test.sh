#!/bin/bash

# Veo 3.0 API 테스트 스크립트
# Cloud Shell에서 실행하세요

set -e

echo "🎥 Veo 3.0 API 테스트"
echo "==================="

# 프로젝트 설정
PROJECT_ID=$(gcloud config get-value project)
REGION="asia-northeast3"  # Cloud Run 서비스 리전
VEO_REGION="us-central1"  # Veo 3.0 리전

# 서비스 URL 가져오기
SERVICE_URL=$(gcloud run services describe get-gcp-token --region=$REGION --format="value(status.url)" 2>/dev/null || echo "")

if [ -z "$SERVICE_URL" ]; then
    echo "❌ Error: get-gcp-token 서비스를 찾을 수 없습니다."
    echo "먼저 setup.sh를 실행하여 서비스를 배포하세요."
    exit 1
fi

echo "📍 Token Service URL: $SERVICE_URL"
echo ""

# 1. Veo 토큰 가져오기
echo "1️⃣ Veo 3.0 토큰 가져오기..."
TOKEN_RESPONSE=$(curl -s "$SERVICE_URL/token/veo")
ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | jq -r .access_token)

if [ "$ACCESS_TOKEN" == "null" ] || [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ Error: 토큰을 가져올 수 없습니다."
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

echo "✅ 토큰 획득 성공!"
echo "토큰 (처음 50자): ${ACCESS_TOKEN:0:50}..."
echo ""

# 2. 간단한 비디오 생성 요청
echo "2️⃣ Veo 3.0으로 비디오 생성 요청..."

# 짧은 테스트 프롬프트로 요청 생성
cat > /tmp/veo_request.json << EOF
{
    "instances": [
        {
            "prompt": "A beautiful sunset over the ocean with waves gently crashing on the beach, golden hour lighting, cinematic style"
        }
    ],
    "parameters": {
        "aspectRatio": "16:9",
        "sampleCount": 1,
        "durationSeconds": "4",
        "personGeneration": "allow_all",
        "addWatermark": true,
        "includeRaiReason": true,
        "generateAudio": true,
        "resolution": "720p"
    }
}
EOF

# Veo 3.0 API 엔드포인트
ENDPOINT="https://$VEO_REGION-aiplatform.googleapis.com/v1/projects/$PROJECT_ID/locations/$VEO_REGION/publishers/google/models/veo-3.0-generate-preview:predictLongRunning"

echo "📡 API 엔드포인트: $ENDPOINT"
echo ""

# API 호출
echo "📤 비디오 생성 요청 전송 중..."
RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/veo_request.json \
  "$ENDPOINT")

# 응답 처리
if echo "$RESPONSE" | jq -e '.name' > /dev/null 2>&1; then
    OPERATION_NAME=$(echo "$RESPONSE" | jq -r '.name')
    echo "✅ 비디오 생성 요청 성공!"
    echo "📋 Operation ID: $OPERATION_NAME"
    echo ""
    echo "🔄 비디오 생성 상태 확인:"
    echo "  gcloud ai operations describe $OPERATION_NAME --region=$VEO_REGION"
    echo ""
    echo "💡 참고: 비디오 생성은 몇 분 정도 걸릴 수 있습니다."
else
    echo "❌ API 호출 실패:"
    echo "$RESPONSE" | jq .
    echo ""
    echo "🔍 가능한 원인:"
    echo "  1. Veo 3.0 API가 활성화되지 않았거나 권한이 부족함"
    echo "  2. 프로젝트에서 Veo 3.0을 사용할 수 없음"
    echo "  3. 할당량 초과"
fi

# 3. 작업 상태 확인 방법 안내
echo ""
echo "📖 n8n 통합 가이드:"
echo "  1. HTTP Request 노드에서:"
echo "     - Method: POST"
echo "     - URL: $ENDPOINT"
echo "     - Authentication: Header Auth"
echo "     - Header Name: Authorization"
echo "     - Header Value: Bearer [토큰]"
echo ""
echo "  2. 토큰 자동 갱신을 위해:"
echo "     - 별도의 HTTP Request로 $SERVICE_URL/token/veo 호출"
echo "     - 응답에서 access_token 추출"
echo "     - 메인 요청에 사용"

# 정리
rm -f /tmp/veo_request.json

echo ""
echo "✨ 테스트 완료!"