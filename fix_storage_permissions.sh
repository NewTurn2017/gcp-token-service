#!/bin/bash
# Storage 권한 문제 해결을 위한 전용 스크립트

set -e

echo "🔧 Storage 권한 문제 해결 스크립트"
echo "================================="

# 프로젝트 정보 가져오기
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
CLOUDBUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
REGION="asia-northeast3"

echo "📋 프로젝트: $PROJECT_ID"
echo "📋 프로젝트 번호: $PROJECT_NUMBER"
echo "📋 Compute SA: $COMPUTE_SA"
echo ""

# 1. 프로젝트 레벨 Storage 권한 부여
echo "1️⃣ 프로젝트 레벨 Storage 권한 부여..."

# Storage Admin 권한 부여 (가장 강력한 권한)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/storage.admin" --quiet

echo "✅ Storage Admin 권한 부여 완료"
echo ""

# 2. Cloud Build 서비스 에이전트 권한 확인
echo "2️⃣ Cloud Build 서비스 에이전트 권한 확인..."
CLOUDBUILD_SERVICE_AGENT="service-${PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${CLOUDBUILD_SERVICE_AGENT}" \
  --role="roles/cloudbuild.serviceAgent" --quiet || true

echo "✅ Cloud Build 서비스 에이전트 권한 확인 완료"
echo ""

# 3. 특정 버킷에 대한 권한 부여 (Cloud Build 소스 버킷)
echo "3️⃣ Cloud Build 소스 버킷 권한 설정..."
BUCKET_NAME="run-sources-${PROJECT_ID}-${REGION}"

# 버킷이 존재하는지 확인하고 권한 부여
gsutil ls gs://${BUCKET_NAME} 2>/dev/null && {
  echo "버킷 발견: gs://${BUCKET_NAME}"
  gsutil iam ch serviceAccount:${COMPUTE_SA}:objectAdmin gs://${BUCKET_NAME}
  gsutil iam ch serviceAccount:${CLOUDBUILD_SA}:objectAdmin gs://${BUCKET_NAME}
  echo "✅ 버킷 권한 설정 완료"
} || {
  echo "⚠️  버킷이 아직 생성되지 않았습니다. 첫 배포 시 자동 생성됩니다."
}
echo ""

# 4. 기본 서비스 계정 확인
echo "4️⃣ 기본 서비스 계정 활성화 확인..."
gcloud iam service-accounts describe ${COMPUTE_SA} >/dev/null 2>&1 || {
  echo "⚠️  Compute Engine 기본 서비스 계정이 비활성화되어 있습니다."
  echo "활성화 중..."
  gcloud iam service-accounts enable ${COMPUTE_SA}
}
echo "✅ 서비스 계정 활성화 확인 완료"
echo ""

# 5. 현재 권한 확인
echo "5️⃣ 현재 권한 확인..."
echo "Compute Engine 서비스 계정 Storage 관련 권한:"
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:${COMPUTE_SA}" \
  --format="table(bindings.role)" | grep -i storage || echo "  Storage 권한 없음"
echo ""

# 6. Cloud Run 기본 서비스 계정 설정
echo "6️⃣ Cloud Run 기본 서비스 계정 설정..."
gcloud config set run/platform managed --quiet
gcloud config set run/region $REGION --quiet

# 기존 서비스가 있다면 서비스 계정 업데이트
if gcloud run services describe get-gcp-token --region=$REGION >/dev/null 2>&1; then
  echo "기존 서비스 발견. 서비스 계정 업데이트 중..."
  gcloud run services update get-gcp-token \
    --service-account=${COMPUTE_SA} \
    --region=$REGION --quiet
  echo "✅ 서비스 계정 업데이트 완료"
fi
echo ""

# 7. 권한 전파 대기
echo "⏳ 권한이 전파되도록 45초 대기..."
for i in {45..1}; do
  echo -ne "\r남은 시간: $i 초  "
  sleep 1
done
echo -e "\n✅ 대기 완료"
echo ""

echo "✨ Storage 권한 설정 완료!"
echo ""
echo "📝 다음 단계:"
echo "1. setup.sh를 다시 실행하세요:"
echo "   bash setup.sh"
echo ""
echo "2. 여전히 실패한다면 다음 명령을 실행하세요:"
echo "   gcloud auth configure-docker asia-northeast3-docker.pkg.dev"
echo ""
echo "3. 그래도 실패한다면 수동 배포를 시도하세요:"
echo "   cd ~/gcp-token-service"
echo "   gcloud run deploy get-gcp-token --source . --region $REGION --allow-unauthenticated --service-account=${COMPUTE_SA}"