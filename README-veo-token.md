# Veo 3.0 토큰 자동 갱신 시스템

Google Sheets를 사용하여 Veo 3.0 API 액세스 토큰을 자동으로 갱신하는 시스템입니다.

## 🚀 빠른 설치

Cloud Shell에서 다음 명령을 실행하세요:

```bash
curl -sL https://raw.githubusercontent.com/NewTurn2017/gcp-token-service/main/setup-veo-token-system.sh | bash
```

## 📋 사전 요구사항

- Google Cloud 프로젝트
- Vertex AI API 활성화
- Google Sheets 계정

## 🔧 수동 설치

### 1. 서비스 계정 생성 및 권한 부여

```bash
# 프로젝트 설정
gcloud config set project YOUR_PROJECT_ID

# 서비스 계정 생성
gcloud iam service-accounts create veo-api-sa \
  --display-name="Veo API Service Account"

# 권한 부여
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:veo-api-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/aiplatform.user"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:veo-api-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:veo-api-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/editor"
```

### 2. 서비스 계정 키 생성

```bash
gcloud iam service-accounts keys create ~/veo-key.json \
  --iam-account=veo-api-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

### 3. Python 패키지 설치

```bash
pip3 install google-auth google-auth-oauthlib google-auth-httplib2 google-api-python-client
```

### 4. 스크립트 다운로드 및 설정

```bash
# 스크립트 다운로드
curl -o ~/update-token-to-sheets.py \
  https://raw.githubusercontent.com/NewTurn2017/gcp-token-service/main/update-token-to-sheets.py

# 스프레드시트 ID 설정
nano ~/update-token-to-sheets.py
# SPREADSHEET_ID를 실제 ID로 변경
```

### 5. Google Sheets 공유

1. 새 Google Sheets 생성
2. 공유 버튼 클릭
3. `veo-api-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com` 추가
4. 편집자 권한 부여
5. "무시하고 공유" 클릭

### 6. 테스트 실행

```bash
python3 ~/update-token-to-sheets.py
```

### 7. Cron 작업 설정 (자동 갱신)

```bash
crontab -e

# 다음 줄 추가 (매시간 5분에 실행)
5 * * * * /usr/bin/python3 ~/update-token-to-sheets.py >> ~/token-update.log 2>&1
```

## 📊 Google Sheets 구조

| 셀 | 내용 |
|----|------|
| A1 | Last Updated |
| B1 | 2025-07-23 10:05:00 |
| A2 | Access Token |
| B2 | ya29.c.c0ASRK0Gb... |

## 🔗 n8n 통합

### HTTP Request 노드 설정

1. **Google Sheets 노드**
   - Operation: Read
   - Range: B2
   - 토큰 값 추출

2. **HTTP Request 노드**
   - Method: POST
   - URL: `https://us-central1-aiplatform.googleapis.com/v1/projects/YOUR_PROJECT/locations/us-central1/publishers/google/models/veo-3.0-generate-preview:predictLongRunning`
   - Headers:
     - Authorization: `Bearer {{토큰}}`
     - Content-Type: `application/json`

### 요청 본문 예시

```json
{
  "instances": [
    {
      "prompt": "A beautiful sunset over the ocean"
    }
  ],
  "parameters": {
    "aspectRatio": "16:9",
    "sampleCount": 1,
    "durationSeconds": "8",
    "resolution": "720p"
  }
}
```

## ⚠️ 주의사항

1. 토큰은 1시간마다 자동 갱신됩니다
2. 서비스 계정 키는 안전하게 보관하세요
3. Veo 3.0은 us-central1 리전에서만 사용 가능합니다
4. API 할당량을 확인하세요

## 🐛 문제 해결

### 권한 오류
```bash
# 권한 재설정
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:veo-api-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/aiplatform.user"
```

### 시트 업데이트 오류
- Google Sheets가 서비스 계정과 공유되었는지 확인
- 스프레드시트 ID가 올바른지 확인
- 시트 이름 확인 (기본값: 첫 번째 시트)

### 로그 확인
```bash
tail -f ~/token-update.log
```