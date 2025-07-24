#!/bin/bash
# 스케줄러 및 토큰 갱신 모니터링 스크립트

echo "🔍 스케줄러 및 토큰 갱신 모니터링"
echo "================================="
echo ""

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 설정
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
JOB_NAME="veo-token-refresh"
FUNCTION_NAME="veo-token-updater"

echo "프로젝트: $PROJECT_ID"
echo ""

# 1. 스케줄러 상태 및 실행 기록 확인
echo -e "${BLUE}1️⃣ Cloud Scheduler 상태${NC}"
echo "------------------------"

# 스케줄러 상세 정보
JOB_INFO=$(gcloud scheduler jobs describe $JOB_NAME --location=$REGION --format=json 2>/dev/null)

if [ -n "$JOB_INFO" ]; then
    echo "$JOB_INFO" | jq -r '
        "이름: " + .name,
        "스케줄: " + .schedule,
        "시간대: " + .timeZone,
        "상태: " + .state,
        "마지막 실행: " + (.lastAttemptTime // "없음"),
        "다음 실행: " + (.nextRunTime // "없음")
    '
    
    # 마지막 실행 시간 계산
    LAST_RUN=$(echo "$JOB_INFO" | jq -r '.lastAttemptTime // empty')
    if [ -n "$LAST_RUN" ]; then
        LAST_RUN_EPOCH=$(date -d "$LAST_RUN" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${LAST_RUN%%.*}" +%s 2>/dev/null)
        CURRENT_EPOCH=$(date +%s)
        DIFF_MINUTES=$(( ($CURRENT_EPOCH - $LAST_RUN_EPOCH) / 60 ))
        
        echo ""
        if [ $DIFF_MINUTES -gt 35 ]; then
            echo -e "${RED}⚠️  경고: 마지막 실행이 ${DIFF_MINUTES}분 전입니다!${NC}"
            echo "   30분마다 실행되어야 하는데 지연되고 있습니다."
        else
            echo -e "${GREEN}✅ 정상: 마지막 실행이 ${DIFF_MINUTES}분 전입니다.${NC}"
        fi
    fi
else
    echo -e "${RED}❌ 스케줄러를 찾을 수 없습니다${NC}"
fi

# 2. Cloud Function 로그 확인
echo ""
echo -e "${BLUE}2️⃣ Cloud Function 최근 실행 로그${NC}"
echo "--------------------------------"

echo "최근 5개 실행 기록:"
gcloud functions logs read $FUNCTION_NAME \
    --region=$REGION \
    --limit=50 \
    --format="table(time,severity,text)" | grep -E "(Executing|success|error|Updated)" | head -20

# 3. 스프레드시트 ID 입력 및 현재 값 확인
echo ""
echo -e "${BLUE}3️⃣ Google Sheets 현재 상태${NC}"
echo "-------------------------"
echo -n "스프레드시트 ID: "
read SPREADSHEET_ID

if [ -n "$SPREADSHEET_ID" ]; then
    # 현재 토큰 확인
    cat > /tmp/check-sheet.py << EOF
import sys
from google.oauth2 import service_account
from googleapiclient.discovery import build
from datetime import datetime, timezone, timedelta
import json

KEY_FILE = "$HOME/veo-key.json"
SPREADSHEET_ID = "$SPREADSHEET_ID"

try:
    # Sheets 읽기
    sheets_creds = service_account.Credentials.from_service_account_file(
        KEY_FILE,
        scopes=['https://www.googleapis.com/auth/spreadsheets']
    )
    
    service = build('sheets', 'v4', credentials=sheets_creds)
    
    result = service.spreadsheets().values().get(
        spreadsheetId=SPREADSHEET_ID,
        range='A1:C2'
    ).execute()
    
    values = result.get('values', [])
    if len(values) > 1 and len(values[1]) >= 3:
        last_updated = values[1][1]
        token = values[1][2]
        
        print(f"Project ID: {values[1][0]}")
        print(f"Last Updated: {last_updated}")
        print(f"Token: {token[:30]}...{token[-10:]}")
        print(f"Token Length: {len(token)}")
        
        # 시간 차이 계산
        try:
            # KST 시간 파싱 시도
            update_time = datetime.strptime(last_updated, '%Y-%m-%d %H:%M:%S')
            update_time = update_time.replace(tzinfo=timezone(timedelta(hours=9)))  # KST
            now = datetime.now(timezone(timedelta(hours=9)))
            diff = now - update_time
            minutes_ago = int(diff.total_seconds() / 60)
            
            print(f"\\n마지막 업데이트: {minutes_ago}분 전")
            
            if minutes_ago > 60:
                print("❌ 경고: 1시간 이상 업데이트되지 않았습니다!")
                print("   토큰이 만료되었을 가능성이 높습니다.")
            elif minutes_ago > 35:
                print("⚠️  주의: 30분 이상 업데이트되지 않았습니다.")
            else:
                print("✅ 정상: 최근에 업데이트되었습니다.")
                
        except Exception as e:
            print(f"시간 파싱 오류: {e}")
            
        # 토큰 유효성 확인
        print("\\n토큰 형식 확인:")
        if token.startswith("ya29."):
            print("✅ 올바른 Google OAuth 토큰 형식")
        else:
            print("❌ 잘못된 토큰 형식")
            
    else:
        print("❌ 시트에 데이터가 없습니다")
        
except Exception as e:
    print(f"오류: {e}")
EOF

    if command -v python3 &> /dev/null; then
        PY_CMD="python3"
    else
        PY_CMD="python"
    fi
    
    $PY_CMD /tmp/check-sheet.py
fi

# 4. Cloud Function 실행 테스트
echo ""
echo -e "${BLUE}4️⃣ Cloud Function 직접 테스트${NC}"
echo "-----------------------------"
FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME --region=$REGION --gen2 --format="value(serviceConfig.uri)" 2>/dev/null || \
               gcloud functions describe $FUNCTION_NAME --region=$REGION --format="value(httpsTrigger.url)")

if [ -n "$FUNCTION_URL" ]; then
    echo "Function URL: $FUNCTION_URL"
    echo "직접 호출 중..."
    
    RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" $FUNCTION_URL)
    HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
    BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')
    
    echo "응답 코드: $HTTP_CODE"
    echo "응답 내용: $BODY"
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✅ Function 실행 성공${NC}"
    else
        echo -e "${RED}❌ Function 실행 실패${NC}"
    fi
fi

# 5. 문제 진단 및 해결책
echo ""
echo -e "${BLUE}5️⃣ 진단 결과 및 해결책${NC}"
echo "---------------------"

cat << 'EOF'
가능한 문제들:

1. Cloud Scheduler가 실패하는 경우:
   - Cloud Function URL이 변경되었을 수 있음
   - 권한 문제일 수 있음
   
   해결: ./update-scheduler.sh 실행

2. Cloud Function은 실행되지만 Sheets가 업데이트 안 되는 경우:
   - 환경 변수가 손실되었을 수 있음
   - 서비스 계정 키가 만료되었을 수 있음
   
   해결: Cloud Function 재배포
   
3. 특정 시간대에만 실패하는 경우:
   - Google API 할당량 초과
   - 네트워크 일시적 오류
   
   해결: Cloud Function에 재시도 로직 추가

4. 토큰은 생성되지만 n8n에서 실패하는 경우:
   - n8n이 캐시된 오래된 토큰 사용
   - 토큰 형식에 문제 (공백, 줄바꿈)
   
   해결: n8n 워크플로우에 .trim() 추가
EOF

# 6. 즉시 수정 명령어
echo ""
echo -e "${YELLOW}🔧 즉시 수정 명령어:${NC}"
echo "# 스케줄러 강제 실행"
echo "gcloud scheduler jobs run $JOB_NAME --location=$REGION"
echo ""
echo "# Cloud Function 로그 실시간 확인"
echo "gcloud functions logs tail $FUNCTION_NAME --region=$REGION"
echo ""
echo "# Cloud Function 재배포 (환경변수 재설정)"
echo "cd /path/to/gcp-token-service && ./complete-setup.sh"

# 정리
rm -f /tmp/check-sheet.py