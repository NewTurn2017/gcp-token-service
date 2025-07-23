# Cloud Functions 기반 Veo 토큰 자동 갱신 시스템

Google Cloud Functions를 사용하여 Veo 3.0 API 토큰을 자동으로 갱신하는 완전 자동화 시스템입니다.

## 🌟 특징

- **완전 자동화**: 서비스 계정부터 Cloud Functions 배포까지 자동 설치
- **무료 운영**: Cloud Functions 무료 티어로 충분히 운영 가능
- **안정적**: Cloud Scheduler로 매시간 자동 실행
- **간편한 설치**: 단 한 줄의 명령으로 전체 시스템 구축

## 🚀 빠른 시작

### 방법 1: 다운로드 후 실행 (권장)
```bash
curl -o setup.sh https://raw.githubusercontent.com/NewTurn2017/gcp-token-service/main/setup-cloud-function-interactive.sh
chmod +x setup.sh
./setup.sh
```

### 방법 2: 빠른 설치 스크립트
```bash
curl -sL https://raw.githubusercontent.com/NewTurn2017/gcp-token-service/main/quick-setup.sh | bash
```

### 방법 3: 파이프 실행 (일부 환경에서 입력 문제 발생 가능)
```bash
curl -sL https://raw.githubusercontent.com/NewTurn2017/gcp-token-service/main/setup-cloud-function.sh | bash
```

## 📋 시스템 구성요소

1. **서비스 계정**: 자동 생성 및 권한 설정
2. **Cloud Function**: 토큰 생성 및 Sheets 업데이트
3. **Cloud Scheduler**: 매시간 자동 실행
4. **Google Sheets**: 토큰 저장소

## 🔧 수동 설치 가이드

### 1. 사전 준비

```bash
# 프로젝트 ID 설정
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID

# 필수 API 활성화
gcloud services enable \
    cloudfunctions.googleapis.com \
    cloudbuild.googleapis.com \
    cloudscheduler.googleapis.com \
    aiplatform.googleapis.com \
    sheets.googleapis.com
```

### 2. 서비스 계정 생성

```bash
# 서비스 계정 생성
gcloud iam service-accounts create veo-token-sa \
    --display-name="Veo Token Service Account"

# 권한 부여
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:veo-token-sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/aiplatform.user"
```

### 3. Cloud Function 배포

```bash
# 함수 배포
gcloud functions deploy veo-token-updater \
    --gen2 \
    --runtime=python311 \
    --region=us-central1 \
    --source=./cloud-function \
    --entry-point=update_token \
    --trigger-http \
    --allow-unauthenticated \
    --set-env-vars="SERVICE_ACCOUNT_JSON='...',SPREADSHEET_ID=..." \
    --memory=256MB
```

### 4. Cloud Scheduler 설정

```bash
# 스케줄러 생성 (매시간 실행)
gcloud scheduler jobs create http veo-token-scheduler \
    --location=us-central1 \
    --schedule="5 * * * *" \
    --uri=FUNCTION_URL \
    --http-method=GET
```

## 📊 Google Sheets 설정

1. 새 스프레드시트 생성
2. 서비스 계정에 편집자 권한 부여
3. 스프레드시트 ID 복사

### 시트 구조

| A | B |
|---|---|
| Last Updated | Access Token |
| 2025-07-23 10:05:00 | ya29.c.c0ASRK0Gb... |

## 🔗 n8n 통합

### 1. Google Sheets 노드 설정
```json
{
  "operation": "read",
  "spreadsheetId": "YOUR_SHEET_ID",
  "range": "B2"
}
```

### 2. HTTP Request 노드 설정
```json
{
  "method": "POST",
  "url": "https://us-central1-aiplatform.googleapis.com/v1/projects/YOUR_PROJECT/locations/us-central1/publishers/google/models/veo-3.0-generate-preview:predictLongRunning",
  "headers": {
    "Authorization": "Bearer {{$node['Google Sheets'].json['token']}}",
    "Content-Type": "application/json"
  },
  "body": {
    "instances": [{
      "prompt": "A beautiful sunset over the ocean"
    }],
    "parameters": {
      "aspectRatio": "16:9",
      "durationSeconds": "8",
      "resolution": "720p"
    }
  }
}
```

## 💰 비용 분석

### Cloud Functions
- **무료 티어**: 200만 호출/월, 400,000 GB-초
- **예상 사용량**: 720 호출/월 (매시간)
- **비용**: **무료**

### Cloud Scheduler
- **무료 티어**: 3개 작업
- **비용**: **무료**

### Google Sheets API
- **무료 티어**: 충분한 할당량
- **비용**: **무료**

## 🛡️ 보안 고려사항

1. **서비스 계정 키**: 환경 변수로 안전하게 저장
2. **최소 권한**: 필요한 권한만 부여
3. **HTTPS 전용**: 모든 통신 암호화
4. **액세스 제어**: Cloud Function은 인증 없이 호출 가능하지만 민감한 데이터는 노출하지 않음

## 🐛 문제 해결

### Cloud Function 로그 확인
```bash
gcloud functions logs read veo-token-updater --region=us-central1
```

### 수동 실행 테스트
```bash
curl https://YOUR_FUNCTION_URL
```

### 스케줄러 상태 확인
```bash
gcloud scheduler jobs list --location=us-central1
```

### 일반적인 문제

1. **권한 오류**: 서비스 계정 권한 재확인
2. **Sheets 업데이트 실패**: 서비스 계정이 시트에 공유되었는지 확인
3. **Function 타임아웃**: 타임아웃 시간 증가 (--timeout=120s)

## 📈 모니터링

### Cloud Console에서 확인
1. Cloud Functions 지표
2. Cloud Scheduler 실행 기록
3. 오류 로그 및 추적

### 알림 설정
```bash
# 오류 알림 설정
gcloud alpha monitoring policies create \
    --notification-channels=CHANNEL_ID \
    --display-name="Veo Token Error Alert"
```

## 🔄 업데이트 및 유지보수

### Function 업데이트
```bash
gcloud functions deploy veo-token-updater \
    --update-env-vars SPREADSHEET_ID=NEW_ID
```

### 스케줄 변경
```bash
gcloud scheduler jobs update http veo-token-scheduler \
    --schedule="*/30 * * * *"  # 30분마다
```

## 📝 추가 리소스

- [Cloud Functions 문서](https://cloud.google.com/functions/docs)
- [Vertex AI Veo API](https://cloud.google.com/vertex-ai/docs)
- [Google Sheets API](https://developers.google.com/sheets/api)
- [Cloud Scheduler](https://cloud.google.com/scheduler/docs)