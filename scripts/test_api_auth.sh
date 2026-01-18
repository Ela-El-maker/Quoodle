#!/bin/bash
# test_api_auth.sh - Verify Laravel API Protection

BASE_URL="http://localhost:8080/api"

echo "---------------------------------------------------"
echo "TEST 1: Public endpoint (Login) - Should Pass (200)"
echo "---------------------------------------------------"
curl -s -X POST "$BASE_URL/login" \
     -H "Content-Type: application/json" \
     -d '{"email":"admin@quoodle.com", "password":"password"}' | grep "token"
if [ $? -eq 0 ]; then echo "✅ PASS"; else echo "❌ FAIL"; fi

echo ""
echo "---------------------------------------------------"
echo "TEST 2: Protected Command (No Token) - Should Fail (401)"
echo "---------------------------------------------------"
# Expecting {"message":"Unauthenticated"} or similar
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/commands" \
     -H "Content-Type: application/json" \
     -d '{"method":"lock_screen"}')

if [ "$HTTP_CODE" == "401" ]; then
    echo "✅ PASS (Got 401 Unauthorized)"
else
    echo "❌ FAIL (Got $HTTP_CODE)"
fi

echo ""
echo "---------------------------------------------------"
echo "TEST 3: Protected Command (Garbage Token) - Should Fail (401)"
echo "---------------------------------------------------"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/commands" \
     -H "Authorization: Bearer invalid_garbage_token_123" \
     -H "Content-Type: application/json" \
     -d '{"method":"lock_screen"}')

if [ "$HTTP_CODE" == "401" ]; then
    echo "✅ PASS (Got 401 Unauthorized)"
else
    echo "❌ FAIL (Got $HTTP_CODE)"
fi
