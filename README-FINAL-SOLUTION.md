# 🎉 Veo 3.0 토큰 시스템 - 최종 솔루션

## 발견된 문제
감사 로그를 확인한 결과, 기본 서비스 계정(`227871897464-compute@developer.gserviceaccount.com`)이 **이미 존재**하는 것으로 확인되었습니다!

```json
"message": "The default service account (227871897464-compute@developer.gserviceaccount.com) has already been created."
```

## 해결 방법

### 1단계: 서비스 계정 상태 확인
```bash
./check-default-sa-status.sh
```
- 기본 서비스 계정의 존재 여부와 상태를 확인합니다
- 비활성화되어 있거나 권한이 없을 수 있습니다

### 2단계: 권한 수정 (필요한 경우)
```bash
./fix-default-sa-permissions.sh
```
- 서비스 계정을 활성화합니다
- 필요한 모든 권한을 부여합니다
- API를 재활성화하여 권한을 갱신합니다

### 3단계: Cloud Functions 배포
```bash
./deploy-with-default-sa.sh
```
- 기본 서비스 계정을 사용하여 Gen1 Cloud Functions로 배포합니다
- 환경 변수로 서비스 계정 키를 전달합니다
- 선택적으로 Cloud Scheduler를 설정합니다

## 스크립트 설명

### `check-default-sa-status.sh`
- 기본 서비스 계정의 현재 상태를 진단합니다
- 서비스 계정 목록과 권한을 확인합니다
- Cloud Functions 관련 서비스 계정들의 상태를 점검합니다

### `fix-default-sa-permissions.sh`
- 비활성화된 서비스 계정을 활성화합니다
- Editor, Service Account User, Cloud Functions Developer 권한을 부여합니다
- Cloud Functions 서비스 에이전트 권한을 설정합니다
- API를 재활성화하여 권한을 새로고침합니다

### `deploy-with-default-sa.sh`
- 기본 서비스 계정을 사용하여 배포합니다
- Gen1 Cloud Functions를 사용합니다 (더 안정적)
- 환경 변수 파일을 통해 안전하게 키를 전달합니다
- 선택적으로 매시간 자동 실행을 설정합니다

## 예상 결과
1. ✅ 기본 서비스 계정이 활성화되고 올바른 권한을 갖게 됩니다
2. ✅ Cloud Functions가 성공적으로 배포됩니다
3. ✅ 매시간 자동으로 Veo 토큰이 갱신됩니다
4. ✅ n8n에서 Google Sheets의 토큰을 읽어 사용할 수 있습니다

## 문제 해결
만약 여전히 문제가 발생한다면:

1. **수동 배포 시도**
   - https://console.cloud.google.com/functions 에서 직접 배포
   - 서비스 계정: 기본값 사용
   - 환경 변수: SERVICE_ACCOUNT_JSON_BASE64, SPREADSHEET_ID 설정

2. **새 프로젝트 생성**
   - 완전히 새로운 GCP 프로젝트를 생성하면 기본 서비스 계정이 자동 생성됩니다

3. **지원 요청**
   - GCP 지원팀에 기본 서비스 계정 복구 요청