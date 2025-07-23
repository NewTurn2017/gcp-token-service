#!/bin/bash

# Vertex AI API 사용 예제 스크립트
# 이 스크립트는 Cloud Shell에서 실행되도록 설계되었습니다.

set -e

echo "🤖 Vertex AI API 사용 예제"
echo "=========================="

# 프로젝트 ID 가져오기
PROJECT_ID=$(gcloud config get-value project)
REGION="asia-northeast3"

# Cloud Run 서비스 URL 가져오기
SERVICE_URL=$(gcloud run services describe get-gcp-token --region=$REGION --format="value(status.url)" 2>/dev/null || echo "")

if [ -z "$SERVICE_URL" ]; then
    echo "❌ Error: get-gcp-token 서비스를 찾을 수 없습니다."
    echo "먼저 setup.sh를 실행하여 서비스를 배포하세요."
    exit 1
fi

echo "📍 Token Service URL: $SERVICE_URL"
echo ""

# 1. 토큰 가져오기
echo "1️⃣ Vertex AI 토큰 가져오기..."
TOKEN_RESPONSE=$(curl -s "$SERVICE_URL/token/vertex")
ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | jq -r .access_token)

if [ "$ACCESS_TOKEN" == "null" ] || [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ Error: 토큰을 가져올 수 없습니다."
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

echo "✅ 토큰 획득 성공!"
echo ""

# 2. Gemini 모델로 간단한 요청 보내기
echo "2️⃣ Gemini 1.5 Flash 모델에 요청 보내기..."

# 요청 데이터 생성
cat > /tmp/request.json << EOF
{
  "instances": [{
    "content": "한국의 수도는 어디인가요? 간단히 답해주세요."
  }],
  "parameters": {
    "temperature": 0.2,
    "maxOutputTokens": 256,
    "topP": 0.8,
    "topK": 40
  }
}
EOF

# Vertex AI API 호출
ENDPOINT="https://$REGION-aiplatform.googleapis.com/v1/projects/$PROJECT_ID/locations/$REGION/publishers/google/models/gemini-1.5-flash:predict"

echo "📡 API 엔드포인트: $ENDPOINT"
echo ""

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/request.json \
  "$ENDPOINT")

# 응답 처리
if echo "$RESPONSE" | jq -e '.predictions' > /dev/null 2>&1; then
    echo "✅ API 호출 성공!"
    echo ""
    echo "🤖 Gemini의 응답:"
    echo "$RESPONSE" | jq -r '.predictions[0].content'
else
    echo "❌ API 호출 실패:"
    echo "$RESPONSE" | jq .
fi

# 3. 고급 예제 - 시스템 프롬프트와 함께 사용
echo ""
echo "3️⃣ 고급 예제 - 시스템 프롬프트 사용..."

cat > /tmp/advanced_request.json << EOF
{
  "instances": [{
    "messages": [
      {
        "role": "system",
        "content": "당신은 친절한 AI 어시스턴트입니다. 항상 이모지를 사용하여 답변하세요."
      },
      {
        "role": "user",
        "content": "오늘 날씨가 어떤가요?"
      }
    ]
  }],
  "parameters": {
    "temperature": 0.7,
    "maxOutputTokens": 512
  }
}
EOF

# Gemini Pro 모델 사용
ENDPOINT_PRO="https://$REGION-aiplatform.googleapis.com/v1/projects/$PROJECT_ID/locations/$REGION/publishers/google/models/gemini-1.5-pro:predict"

RESPONSE_PRO=$(curl -s -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/advanced_request.json \
  "$ENDPOINT_PRO")

if echo "$RESPONSE_PRO" | jq -e '.predictions' > /dev/null 2>&1; then
    echo "✅ Gemini Pro 호출 성공!"
    echo ""
    echo "🤖 Gemini Pro의 응답:"
    echo "$RESPONSE_PRO" | jq -r '.predictions[0].content'
else
    echo "⚠️  Gemini Pro 호출 실패 (권한 또는 할당량 문제일 수 있습니다)"
fi

# 정리
rm -f /tmp/request.json /tmp/advanced_request.json

echo ""
echo "✨ 예제 실행 완료!"
echo ""
echo "💡 팁:"
echo "  - 다른 모델을 사용하려면 엔드포인트의 모델 이름을 변경하세요"
echo "  - 사용 가능한 모델: gemini-1.5-flash, gemini-1.5-pro, gemini-1.0-pro 등"
echo "  - 자세한 API 문서: https://cloud.google.com/vertex-ai/docs/generative-ai/model-reference/gemini"