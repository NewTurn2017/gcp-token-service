# GCP Token Service

Google Cloud Platform의 다양한 API (특히 Vertex AI와 Veo 3.0)를 위한 액세스 토큰을 쉽게 생성하고 관리하는 Cloud Run 서비스입니다.

## 🚀 빠른 시작

```bash
# Cloud Shell에서 실행
gcloud config set project YOUR_PROJECT_ID
bash setup.sh
```

## 🎯 주요 기능

- **자동 토큰 생성**: Google Cloud API용 액세스 토큰 자동 생성
- **다중 리전 지원**: us-central1, asia-northeast3 등 다양한 리전 지원
- **Veo 3.0 전용 엔드포인트**: 비디오 생성 AI를 위한 특별 지원
- **n8n 통합**: HTTP Request 노드로 쉽게 통합 가능
- **자동 권한 설정**: 필요한 IAM 권한 자동 구성

## 📁 파일 구조

```
gcp-token-service/
├── README.md                    # 이 파일
├── setup.sh                     # 자동 배포 스크립트
├── vertex_ai_example.sh         # Vertex AI 사용 예제
├── veo_test.sh                  # Veo 3.0 테스트 스크립트
└── n8n_integration_guide.md     # n8n 통합 가이드
```

## 🔧 API 엔드포인트

배포 후 다음 엔드포인트를 사용할 수 있습니다:

| 엔드포인트 | 설명 |
|-----------|------|
| `GET /` | 서비스 정보 및 사용 가능한 엔드포인트 목록 |
| `GET /token` | 기본 액세스 토큰 생성 |
| `GET /token/vertex` | Vertex AI용 토큰 생성 |
| `GET /token/veo` | Veo 3.0용 토큰 생성 (us-central1) |
| `GET /token/{region}` | 특정 리전용 토큰 생성 |
| `GET /project` | 프로젝트 정보 조회 |
| `GET /health` | 헬스 체크 |

## 💡 사용 예제

### 기본 토큰 가져오기
```bash
curl https://YOUR_SERVICE_URL/token
```

### Veo 3.0 토큰으로 비디오 생성
```bash
# 토큰 가져오기
TOKEN=$(curl -s https://YOUR_SERVICE_URL/token/veo | jq -r .access_token)

# Veo 3.0 API 호출
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @request.json \
  https://us-central1-aiplatform.googleapis.com/v1/projects/YOUR_PROJECT/locations/us-central1/publishers/google/models/veo-3.0-generate-preview:predictLongRunning
```

## 🔐 필요한 권한

스크립트가 자동으로 설정하는 권한:

- `roles/run.admin` - Cloud Run 관리
- `roles/iam.serviceAccountUser` - 서비스 계정 사용
- `roles/storage.admin` - Storage 관리
- `roles/aiplatform.user` - Vertex AI 사용
- `roles/aiplatform.predictor` - 예측 요청

## ⚠️ 주의사항

1. **토큰 만료**: 액세스 토큰은 1시간 후 만료됩니다
2. **리전 제한**: Veo 3.0은 us-central1에서만 사용 가능
3. **할당량**: API 할당량을 확인하세요
4. **보안**: 프로덕션에서는 추가 보안 조치가 필요합니다

## 🐛 문제 해결

### 권한 오류
```bash
# 추가 권한 부여
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:SA_EMAIL" \
  --role="roles/aiplatform.user"
```

### 로그 확인
```bash
gcloud run logs read --service=get-gcp-token --region=asia-northeast3
```

## 📚 추가 리소스

- [Vertex AI 문서](https://cloud.google.com/vertex-ai/docs)
- [Veo 3.0 가이드](https://cloud.google.com/vertex-ai/generative-ai/docs/model-reference/veo)
- [Cloud Run 문서](https://cloud.google.com/run/docs)

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다.