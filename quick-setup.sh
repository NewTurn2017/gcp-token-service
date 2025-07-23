#!/bin/bash
# 빠른 설치를 위한 간단한 래퍼 스크립트

echo "📥 설치 스크립트 다운로드 중..."
curl -o veo-setup.sh https://raw.githubusercontent.com/NewTurn2017/gcp-token-service/main/setup-cloud-function-interactive.sh

echo "🔧 실행 권한 설정..."
chmod +x veo-setup.sh

echo "🚀 설치 시작..."
./veo-setup.sh

# 설치 후 스크립트 삭제 옵션
echo ""
echo -n "설치 스크립트를 삭제하시겠습니까? (y/N): "
read -r DELETE_SCRIPT
if [[ "$DELETE_SCRIPT" =~ ^[Yy]$ ]]; then
    rm -f veo-setup.sh
    echo "✅ 설치 스크립트가 삭제되었습니다."
fi