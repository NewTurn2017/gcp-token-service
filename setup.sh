#!/bin/bash
set -e

echo "🚀 GCP Token Service 설치 시작..."

# 프로젝트 설정
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# API 활성화
echo "🔌 API 활성화..."
gcloud services enable cloudbuild.googleapis.com run.googleapis.com artifactregistry.googleapis.com --quiet

# IAM 설정
echo "🔑 권한 설정..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/run.admin" --quiet
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser" --quiet

# 대기
sleep 5

# 소스 준비 및 배포
echo "🚀 배포 중..."
cd ~ && rm -rf gcp-token-service && mkdir gcp-token-service && cd gcp-token-service

cat > main.py << 'EOF'
from flask import Flask, jsonify
import google.auth
import google.auth.transport.requests

app = Flask(__name__)

@app.route('/')
def get_token():
    try:
        credentials, project = google.auth.default()
        auth_req = google.auth.transport.requests.Request()
        credentials.refresh(auth_req)
        return jsonify({"success": True, "access_token": credentials.token, "project_id": project})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

if __name__ == '__main__':
    import os
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF

echo 'Flask==3.0.0
google-auth[requests]==2.23.4
gunicorn==23.0.0' > requirements.txt

echo 'web: gunicorn --bind :$PORT main:app' > Procfile

# 배포
gcloud run deploy get-gcp-token --source . --region asia-northeast3 --allow-unauthenticated --quiet
gcloud run services add-iam-policy-binding get-gcp-token --region=asia-northeast3 --member="allUsers" --role="roles/run.invoker" --quiet

# 완료
URL=$(gcloud run services describe get-gcp-token --region=asia-northeast3 --format="value(status.url)")
echo "✅ 완료!"
echo "📍 URL: $URL"
