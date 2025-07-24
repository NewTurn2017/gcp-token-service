# Veo 3.0 토큰 자동화 시스템

Google Cloud Shell에서 한 줄로 설치:

```bash
curl -sSL https://raw.githubusercontent.com/NewTurn2017/gcp-token-service/main/complete-setup.sh | bash
```

또는 로컬에서:

```bash
git clone https://github.com/NewTurn2017/gcp-token-service.git && cd gcp-token-service && ./complete-setup.sh
```

## 🚀 기능

- Veo 3.0 API용 액세스 토큰 자동 생성
- Google Sheets에 토큰 자동 저장
- 매시간 자동 갱신 (Cloud Scheduler)
- n8n 통합 지원

## 📋 사전 요구사항

- Google Cloud 프로젝트
- gcloud CLI 설치 및 로그인
- Python 3.7+

## 🛠️ 수동 설치

```bash
# 1. 프로젝트 설정
gcloud config set project YOUR_PROJECT_ID

# 2. 설치 실행
./install.sh
```

## 📊 n8n 연동

1. HTTP Request 노드 추가
2. Method: GET
3. URL: `https://sheets.googleapis.com/v4/spreadsheets/YOUR_SHEET_ID/values/C2`
4. Authentication: API Key

### Google Sheets 구조
- A열: Project ID
- B열: Last Updated (timestamp)
- C열: Access Token

## 🔧 문제 해결

기본 서비스 계정 오류 시:
```bash
# Gen2 대신 Gen1 사용
gcloud functions deploy veo-token-updater \
    --runtime=python311 \
    --trigger-http \
    --allow-unauthenticated \
    --no-gen2
```

## 📝 라이선스

MIT