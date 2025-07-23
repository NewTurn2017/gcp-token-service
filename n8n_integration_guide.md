# n8n과 GCP Token Service 통합 가이드

## 📋 목차
1. [서비스 배포](#서비스-배포)
2. [n8n에서 Veo 3.0 사용하기](#n8n에서-veo-30-사용하기)
3. [토큰 자동 갱신 워크플로우](#토큰-자동-갱신-워크플로우)
4. [문제 해결](#문제-해결)

## 서비스 배포

먼저 Cloud Shell에서 다음 명령을 실행하여 토큰 서비스를 배포합니다:

```bash
# 프로젝트 설정
gcloud config set project warmtalentai

# setup.sh 실행
bash setup.sh
```

배포가 완료되면 서비스 URL이 표시됩니다 (예: `https://get-gcp-token-xxxxx-an.a.run.app`)

## n8n에서 Veo 3.0 사용하기

### 방법 1: 수동 토큰 설정

1. **토큰 가져오기**
   ```bash
   # Cloud Shell에서 실행
   SERVICE_URL="https://get-gcp-token-xxxxx-an.a.run.app"
   curl $SERVICE_URL/token/veo | jq -r .access_token
   ```

2. **n8n HTTP Request 노드 설정**
   - **Method**: POST
   - **URL**: `https://us-central1-aiplatform.googleapis.com/v1/projects/warmtalentai/locations/us-central1/publishers/google/models/veo-3.0-generate-preview:predictLongRunning`
   - **Authentication**: Header Auth
   - **Header**:
     - Name: `Authorization`
     - Value: `Bearer [위에서 얻은 토큰]`
   - **Headers**: 
     - `Content-Type`: `application/json`
   - **Body**: JSON으로 요청 데이터 입력

### 방법 2: 자동 토큰 갱신 워크플로우

n8n에서 토큰을 자동으로 가져오고 갱신하는 워크플로우:

```json
{
  "name": "Veo 3.0 Video Generation with Auto Token",
  "nodes": [
    {
      "parameters": {
        "url": "https://get-gcp-token-xxxxx-an.a.run.app/token/veo",
        "options": {}
      },
      "name": "Get Access Token",
      "type": "n8n-nodes-base.httpRequest",
      "position": [250, 300]
    },
    {
      "parameters": {
        "functionCode": "const tokenData = items[0].json;\nreturn [{\n  json: {\n    access_token: tokenData.access_token,\n    project_id: tokenData.project_id\n  }\n}];"
      },
      "name": "Extract Token",
      "type": "n8n-nodes-base.function",
      "position": [450, 300]
    },
    {
      "parameters": {
        "method": "POST",
        "url": "=https://us-central1-aiplatform.googleapis.com/v1/projects/{{$node[\"Extract Token\"].json[\"project_id\"]}}/locations/us-central1/publishers/google/models/veo-3.0-generate-preview:predictLongRunning",
        "authentication": "genericCredentialType",
        "genericAuthType": "httpHeaderAuth",
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "Authorization",
              "value": "=Bearer {{$node[\"Extract Token\"].json[\"access_token\"]}}"
            },
            {
              "name": "Content-Type",
              "value": "application/json"
            }
          ]
        },
        "sendBody": true,
        "bodyParameters": {
          "parameters": []
        },
        "jsonParameters": true,
        "body": "{\n  \"instances\": [\n    {\n      \"prompt\": \"YOUR_VIDEO_PROMPT_HERE\"\n    }\n  ],\n  \"parameters\": {\n    \"aspectRatio\": \"16:9\",\n    \"sampleCount\": 2,\n    \"durationSeconds\": \"8\",\n    \"personGeneration\": \"allow_all\",\n    \"addWatermark\": true,\n    \"includeRaiReason\": true,\n    \"generateAudio\": true,\n    \"resolution\": \"720p\"\n  }\n}"
      },
      "name": "Call Veo 3.0 API",
      "type": "n8n-nodes-base.httpRequest",
      "position": [650, 300]
    }
  ]
}
```

### Veo 3.0 요청 파라미터 설명

```json
{
  "instances": [{
    "prompt": "비디오 생성 프롬프트"
  }],
  "parameters": {
    "aspectRatio": "16:9",        // 화면 비율: "16:9", "9:16", "1:1"
    "sampleCount": 2,             // 생성할 비디오 개수 (1-4)
    "durationSeconds": "8",       // 비디오 길이 (초): "4", "8", "16"
    "personGeneration": "allow_all", // 인물 생성: "allow_all", "disallow_all"
    "addWatermark": true,         // 워터마크 추가 여부
    "includeRaiReason": true,     // RAI (Responsible AI) 이유 포함
    "generateAudio": true,        // 오디오 생성 여부
    "resolution": "720p"          // 해상도: "360p", "720p", "1080p"
  }
}
```

## 토큰 자동 갱신 워크플로우

토큰은 1시간 후 만료되므로 자동 갱신이 필요합니다:

1. **Schedule Trigger** 노드 추가 (매 50분마다 실행)
2. **HTTP Request** 노드로 새 토큰 가져오기
3. **Set** 노드로 글로벌 변수에 토큰 저장
4. 실제 API 호출 시 글로벌 변수에서 토큰 참조

## 문제 해결

### 권한 오류 해결

만약 권한 오류가 발생하면 Cloud Shell에서 다음 명령을 실행:

```bash
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# Vertex AI 권한 추가
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/aiplatform.user"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/aiplatform.predictor"
```

### API 활성화

Veo 3.0을 사용하려면 다음 API가 활성화되어 있어야 합니다:

```bash
gcloud services enable aiplatform.googleapis.com
```

### 할당량 확인

Veo 3.0은 할당량이 제한적입니다. 할당량 초과 시 오류가 발생할 수 있습니다.

## 유용한 엔드포인트

- **홈**: `GET /` - 사용 가능한 모든 엔드포인트 확인
- **기본 토큰**: `GET /token` - 기본 액세스 토큰
- **Vertex AI 토큰**: `GET /token/vertex` - Vertex AI용 토큰
- **Veo 3.0 토큰**: `GET /token/veo` - Veo 3.0 전용 토큰 (us-central1)
- **리전별 토큰**: `GET /token/{region}` - 특정 리전용 토큰
- **프로젝트 정보**: `GET /project` - 프로젝트 정보
- **헬스 체크**: `GET /health` - 서비스 상태 확인

## 예제: 작업 상태 확인

비디오 생성은 비동기 작업이므로 상태를 확인해야 합니다:

```bash
# 작업 ID 가져오기 (API 호출 응답에서)
OPERATION_NAME="projects/warmtalentai/locations/us-central1/operations/xxxxx"

# 상태 확인
gcloud ai operations describe $OPERATION_NAME --region=us-central1
```

## 보안 고려사항

1. **토큰 보안**: 토큰을 n8n 환경 변수나 자격 증명으로 안전하게 저장
2. **HTTPS 사용**: 항상 HTTPS를 통해 통신
3. **최소 권한**: 필요한 최소 권한만 부여
4. **정기 갱신**: 토큰을 정기적으로 갱신

## 지원

문제가 발생하면:
1. Cloud Run 로그 확인: `gcloud run logs read --service=get-gcp-token --region=asia-northeast3`
2. API 권한 확인
3. 할당량 및 청구 상태 확인