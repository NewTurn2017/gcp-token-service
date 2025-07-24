# Veo 3.0 토큰 자동화 시스템

Google Veo 3.0 API를 위한 자동 토큰 갱신 시스템입니다. Cloud Functions와 Cloud Scheduler를 사용하여 30분마다 자동으로 토큰을 갱신하고 Google Sheets에 저장합니다.

## 🚀 빠른 시작

Google Cloud Shell에서 한 줄로 설치:

```bash
curl -sSL https://raw.githubusercontent.com/NewTurn2017/gcp-token-service/main/setup.sh | bash
```

또는 로컬에서:

```bash
git clone https://github.com/NewTurn2017/gcp-token-service.git && cd gcp-token-service && ./setup.sh
```

## 📋 기능

- ✅ Veo 3.0 API용 액세스 토큰 자동 생성
- ✅ Google Sheets에 토큰 자동 저장  
- ✅ 30분마다 자동 갱신 (Cloud Scheduler)
- ✅ 한국 시간(KST) 표시
- ✅ 재시도 로직으로 안정성 향상
- ✅ n8n 워크플로우 통합 지원

## 📊 Google Sheets 구조

| 열 | 내용 | 설명 |
|---|------|------|
| A | Project ID | GCP 프로젝트 ID |
| B | Last Updated (KST) | 마지막 갱신 시간 (한국 시간) |
| C | Access Token | Veo API 액세스 토큰 |

## 🔧 사전 요구사항

- Google Cloud 프로젝트
- gcloud CLI 설치 및 로그인
- Python 3.7 이상

## 📦 설치 과정

1. **API 활성화**: Cloud Functions, Vertex AI, Sheets API
2. **서비스 계정 생성**: `veo-token-sa` 자동 생성
3. **권한 부여**: Vertex AI User, Editor 권한
4. **Google Sheets 설정**: 서비스 계정에 편집 권한 부여
5. **Cloud Function 배포**: 토큰 갱신 함수
6. **Cloud Scheduler 설정**: 30분마다 자동 실행

## 🎯 n8n 연동

### 1. Google Sheets 노드
- Operation: Read
- Document ID: 스프레드시트 ID
- Range: `C2`

### 2. Set 노드 (토큰 정리)
```javascript
{{ $json.data[0][0].trim() }}
```

### 3. HTTP Request 노드 (Veo API)
- Method: POST
- URL: `https://us-central1-aiplatform.googleapis.com/v1/projects/YOUR_PROJECT_ID/locations/us-central1/publishers/google/models/veo-3.0-generate-preview:predictLongRunning`
- Headers:
  - Authorization: `Bearer {{ $json.token }}`
  - Content-Type: `application/json`

## 🔄 스케줄러 업데이트

기존 스케줄러를 업데이트하려면:

```bash
./update-scheduler.sh
```

## 🛠️ 문제 해결

### 권한 문제 해결
```bash
./fix-permissions.sh
```

### 토큰 갱신 모니터링
```bash
./monitor-scheduler.sh
```

### Cloud Function 업데이트
```bash
./update-function.sh
```

### 수동 토큰 갱신
```bash
gcloud scheduler jobs run veo-token-refresh --location=us-central1
```

### Google Sheets 공유 확인
스프레드시트에서 서비스 계정(`veo-token-sa@PROJECT_ID.iam.gserviceaccount.com`)이 편집자 권한을 가지고 있는지 확인하세요.

## 📝 주요 파일

- `setup.sh`: 메인 설치 스크립트
- `update-scheduler.sh`: 스케줄러 업데이트
- `update-function.sh`: Cloud Function 업데이트  
- `monitor-scheduler.sh`: 시스템 상태 모니터링

## ⚠️ 주의사항

- Google OAuth 토큰은 1시간 후 만료됩니다
- 30분마다 갱신하여 항상 유효한 토큰을 유지합니다
- n8n에서 토큰 사용 시 `.trim()` 필수

## 📄 라이선스

MIT