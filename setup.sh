#!/bin/bash
set -e

echo "🚀 GCP Token Service 설치 시작..."

# 프로젝트 설정
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
CLOUDBUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

# API 활성화
echo "🔌 API 활성화..."
gcloud services enable cloudbuild.googleapis.com run.googleapis.com artifactregistry.googleapis.com aiplatform.googleapis.com compute.googleapis.com --quiet

# IAM 설정
echo "🔑 권한 설정..."
# Cloud Build 서비스 계정에 필요한 권한 부여
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${CLOUDBUILD_SA}" \
  --role="roles/run.admin" --quiet
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${CLOUDBUILD_SA}" \
  --role="roles/iam.serviceAccountUser" --quiet
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${CLOUDBUILD_SA}" \
  --role="roles/storage.admin" --quiet

# Compute Engine 기본 서비스 계정에 Storage 권한 부여
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/storage.objectViewer" --quiet

# Vertex AI 사용을 위한 권한 추가
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/aiplatform.user" --quiet

# Vertex AI 고급 기능을 위한 추가 권한
# roles/aiplatform.predictor는 프로젝트 레벨에서 지원되지 않으므로 제거

# Cloud Run 기본 서비스 계정에도 동일한 권한 부여
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}@gcp-sa-run.iam.gserviceaccount.com" \
  --role="roles/aiplatform.user" --quiet || true

# 대기
sleep 10

# 소스 준비 및 배포
echo "🚀 배포 중..."
cd ~ && rm -rf gcp-token-service && mkdir gcp-token-service && cd gcp-token-service

cat > main.py << 'EOF'
from flask import Flask, jsonify, request
import google.auth
import google.auth.transport.requests
from google.oauth2 import service_account
import os
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

@app.route('/')
def home():
    """홈 엔드포인트 - 서비스 정보 제공"""
    return jsonify({
        "service": "GCP Token Service",
        "version": "1.1",
        "endpoints": {
            "/token": "Get default access token",
            "/token/vertex": "Get access token for Vertex AI",
            "/token/veo": "Get access token for Veo 3.0 (us-central1)",
            "/token/<region>": "Get access token for specific region",
            "/project": "Get project information",
            "/health": "Health check"
        },
        "supported_regions": [
            "us-central1", "us-east1", "us-west1", 
            "europe-west4", "asia-northeast3", "asia-northeast1"
        ]
    })

@app.route('/token')
def get_token():
    """기본 액세스 토큰 가져오기"""
    try:
        credentials, project = google.auth.default()
        auth_req = google.auth.transport.requests.Request()
        credentials.refresh(auth_req)
        
        return jsonify({
            "success": True, 
            "access_token": credentials.token,
            "token_type": "Bearer",
            "project_id": project
        })
    except Exception as e:
        logging.error(f"Error getting token: {str(e)}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route('/token/vertex')
def get_vertex_token():
    """Vertex AI용 액세스 토큰 가져오기"""
    try:
        # Vertex AI API에 필요한 스코프
        scopes = ['https://www.googleapis.com/auth/cloud-platform']
        
        credentials, project = google.auth.default(scopes=scopes)
        auth_req = google.auth.transport.requests.Request()
        credentials.refresh(auth_req)
        
        return jsonify({
            "success": True,
            "access_token": credentials.token,
            "token_type": "Bearer",
            "project_id": project,
            "scopes": scopes,
            "usage": {
                "endpoint": f"https://{get_region()}-aiplatform.googleapis.com",
                "example_header": f"Authorization: Bearer {credentials.token[:20]}..."
            }
        })
    except Exception as e:
        logging.error(f"Error getting Vertex AI token: {str(e)}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route('/project')
def get_project_info():
    """프로젝트 정보 가져오기"""
    try:
        _, project = google.auth.default()
        region = get_region()
        
        return jsonify({
            "success": True,
            "project_id": project,
            "region": region,
            "vertex_ai_endpoint": f"https://{region}-aiplatform.googleapis.com"
        })
    except Exception as e:
        logging.error(f"Error getting project info: {str(e)}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route('/health')
def health_check():
    """헬스 체크 엔드포인트"""
    return jsonify({"status": "healthy", "service": "gcp-token-service"})

def get_region():
    """Cloud Run 리전 가져오기"""
    # Cloud Run에서는 K_SERVICE 환경 변수가 설정됨
    if os.environ.get('K_SERVICE'):
        # 기본적으로 asia-northeast3 사용
        return os.environ.get('REGION', 'asia-northeast3')
    return 'asia-northeast3'

@app.route('/token/veo')
def get_veo_token():
    """Veo 3.0용 액세스 토큰 가져오기 (us-central1 리전)"""
    try:
        # Veo 3.0 API에 필요한 스코프
        scopes = ['https://www.googleapis.com/auth/cloud-platform']
        
        credentials, project = google.auth.default(scopes=scopes)
        auth_req = google.auth.transport.requests.Request()
        credentials.refresh(auth_req)
        
        return jsonify({
            "success": True,
            "access_token": credentials.token,
            "token_type": "Bearer",
            "project_id": project,
            "scopes": scopes,
            "region": "us-central1",
            "usage": {
                "endpoint": f"https://us-central1-aiplatform.googleapis.com",
                "model": "veo-3.0-generate-preview",
                "example_header": f"Authorization: Bearer {credentials.token[:20]}...",
                "n8n_config": {
                    "authentication": "Generic Credential Type",
                    "header_auth": True,
                    "header_name": "Authorization",
                    "header_value": f"Bearer {credentials.token}"
                }
            }
        })
    except Exception as e:
        logging.error(f"Error getting Veo token: {str(e)}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route('/token/<region>')
def get_regional_token(region):
    """특정 리전용 액세스 토큰 가져오기"""
    try:
        # 유효한 리전 확인
        valid_regions = ['us-central1', 'us-east1', 'us-west1', 'europe-west4', 'asia-northeast3', 'asia-northeast1']
        if region not in valid_regions:
            return jsonify({
                "success": False, 
                "error": f"Invalid region. Valid regions: {', '.join(valid_regions)}"
            }), 400
        
        scopes = ['https://www.googleapis.com/auth/cloud-platform']
        credentials, project = google.auth.default(scopes=scopes)
        auth_req = google.auth.transport.requests.Request()
        credentials.refresh(auth_req)
        
        return jsonify({
            "success": True,
            "access_token": credentials.token,
            "token_type": "Bearer",
            "project_id": project,
            "region": region,
            "endpoint": f"https://{region}-aiplatform.googleapis.com"
        })
    except Exception as e:
        logging.error(f"Error getting regional token: {str(e)}")
        return jsonify({"success": False, "error": str(e)}), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)
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
echo ""
echo "🔧 사용 방법:"
echo "  기본 토큰: curl $URL/token"
echo "  Vertex AI 토큰: curl $URL/token/vertex"
echo "  Veo 3.0 토큰: curl $URL/token/veo"
echo "  프로젝트 정보: curl $URL/project"
echo ""
echo "📚 n8n에서 Veo 3.0 사용 방법:"
echo "  1. HTTP Request 노드 추가"
echo "  2. Method: POST"
echo "  3. URL: https://us-central1-aiplatform.googleapis.com/v1/projects/$PROJECT_ID/locations/us-central1/publishers/google/models/veo-3.0-generate-preview:predictLongRunning"
echo "  4. Authentication: Header Auth"
echo "  5. Header: Authorization = Bearer \$(curl -s $URL/token/veo | jq -r .access_token)"
echo ""
echo "🎥 Veo 3.0 사용 예제:"
echo "  TOKEN=\$(curl -s $URL/token/veo | jq -r .access_token)"
echo "  curl -X POST \\"
echo "    -H \"Authorization: Bearer \$TOKEN\" \\"
echo "    -H \"Content-Type: application/json\" \\"
echo "    -d @request.json \\"
echo "    https://us-central1-aiplatform.googleapis.com/v1/projects/$PROJECT_ID/locations/us-central1/publishers/google/models/veo-3.0-generate-preview:predictLongRunning"
