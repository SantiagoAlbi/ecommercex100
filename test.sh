#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# ecommercex100 — end-to-end test
# Usage: ./test.sh [image_path]
# Requires: aws cli, curl, jq
# ─────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
info() { echo -e "${BLUE}→${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

# ─── deps ────────────────────────────────────
for cmd in aws curl jq; do
  command -v "$cmd" &>/dev/null || fail "Missing dependency: $cmd"
done

# ─── config ──────────────────────────────────
TEST_IMAGE="${1:-}"
PRODUCT_ID="test-$(date +%s)"
COGNITO_USER="${COGNITO_USER:-}"
COGNITO_PASS="${COGNITO_PASS:-}"
WAIT_SECONDS=12   # time for SQS → Lambda → DynamoDB

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ecommercex100 — end-to-end test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── step 0: terraform outputs ───────────────
info "Reading Terraform outputs..."

TERRAFORM_DIR="$(dirname "$0")/terraform"
[[ -d "$TERRAFORM_DIR" ]] || fail "terraform/ directory not found. Run from repo root."

API_ENDPOINT=$(terraform -chdir="$TERRAFORM_DIR" output -raw api_endpoint 2>/dev/null) \
  || fail "Could not read api_endpoint. Did you run terraform apply?"
CLOUDFRONT_URL=$(terraform -chdir="$TERRAFORM_DIR" output -raw cloudfront_url 2>/dev/null) \
  || fail "Could not read cloudfront_url"
CLIENT_ID=$(terraform -chdir="$TERRAFORM_DIR" output -raw cognito_client_id 2>/dev/null) \
  || fail "Could not read cognito_client_id"
TABLE_NAME=$(terraform -chdir="$TERRAFORM_DIR" output -raw dynamodb_table_name 2>/dev/null) \
  || fail "Could not read dynamodb_table_name"

# strip trailing slash from endpoint if present
API_ENDPOINT="${API_ENDPOINT%/}"

ok "Terraform outputs loaded"
echo "   API:        $API_ENDPOINT"
echo "   CloudFront: $CLOUDFRONT_URL"
echo "   Table:      $TABLE_NAME"
echo ""

# ─── step 1: resolve test image ──────────────
info "Resolving test image..."

if [[ -n "$TEST_IMAGE" && -f "$TEST_IMAGE" ]]; then
  IMAGE_PATH="$TEST_IMAGE"
  FILENAME=$(basename "$TEST_IMAGE")
  ok "Using provided image: $FILENAME"
else
  # create a minimal valid JPEG (1×1 white pixel)
  IMAGE_PATH="/tmp/ecommerce_test_$PRODUCT_ID.jpg"
  FILENAME="test_image.jpg"
  # 1×1 white JPEG, base64-encoded
  printf '%s' \
    '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8U' \
    'HRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgN' \
    'DRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy' \
    'MjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAA' \
    'AAAAAAAAAAAAAAAAAAAA/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/EABQRAQAAAAAAAAAAAAAAA' \
    'AAAAP/aAAwDAQACEQMRAD8AJQAB/9k=' \
    | base64 -d > "$IMAGE_PATH" 2>/dev/null \
    || { warn "Could not create synthetic JPEG. Provide a real image: ./test.sh path/to/image.jpg"; exit 1; }
  ok "Using synthetic 1×1 JPEG (no image provided)"
fi
echo ""

# ─── step 2: authenticate with cognito ───────
info "Authenticating with Cognito..."

if [[ -z "$COGNITO_USER" || -z "$COGNITO_PASS" ]]; then
  echo ""
  read -rp "  Cognito username (email): " COGNITO_USER
  read -rsp "  Cognito password:         " COGNITO_PASS
  echo ""
fi

AUTH_RESPONSE=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id "$CLIENT_ID" \
  --auth-parameters "USERNAME=${COGNITO_USER},PASSWORD=${COGNITO_PASS}" \
  2>&1) || fail "Cognito auth failed:\n$AUTH_RESPONSE"

TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.AuthenticationResult.IdToken') \
  || fail "Could not parse IdToken from Cognito response"
[[ "$TOKEN" != "null" && -n "$TOKEN" ]] || fail "Empty token — check credentials"

ok "Authenticated as $COGNITO_USER"
echo "   Token: ${TOKEN:0:40}..."
echo ""

# ─── step 3: get presigned upload url ────────
info "Requesting presigned upload URL..."

UPLOAD_RESPONSE=$(curl -sf -X POST "${API_ENDPOINT}/upload" \
  -H "Authorization: ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"product_id\":\"${PRODUCT_ID}\",\"filename\":\"${FILENAME}\",\"content_type\":\"image/jpeg\"}" \
  2>&1) || fail "API call failed:\n$UPLOAD_RESPONSE"

UPLOAD_URL=$(echo "$UPLOAD_RESPONSE" | jq -r '.upload_url') \
  || fail "Could not parse upload_url"
S3_KEY=$(echo "$UPLOAD_RESPONSE" | jq -r '.key') \
  || fail "Could not parse key"

[[ "$UPLOAD_URL" != "null" && -n "$UPLOAD_URL" ]] \
  || fail "API returned null upload_url. Response: $UPLOAD_RESPONSE"

ok "Got presigned URL"
echo "   S3 key: $S3_KEY"
echo ""

# ─── step 4: upload image directly to s3 ─────
info "Uploading image directly to S3..."

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PUT "$UPLOAD_URL" \
  -H "Content-Type: image/jpeg" \
  --upload-file "$IMAGE_PATH")

[[ "$HTTP_CODE" == "200" ]] \
  || fail "S3 upload failed — HTTP $HTTP_CODE. Check presigned URL or ContentType."

ok "Image uploaded — HTTP $HTTP_CODE"
echo "   File:   $IMAGE_PATH"
echo "   Bucket: raw/${PRODUCT_ID}/${FILENAME}"
echo ""

# ─── step 5: wait for processing pipeline ────
info "Waiting ${WAIT_SECONDS}s for SQS → Lambda → DynamoDB pipeline..."

for i in $(seq 1 "$WAIT_SECONDS"); do
  printf "\r   ${BLUE}[%*d/%d]${NC} processing..." ${#WAIT_SECONDS} "$i" "$WAIT_SECONDS"
  sleep 1
done
echo ""
echo ""

# ─── step 6: verify dynamodb record ──────────
info "Checking DynamoDB for processed metadata..."

FILENAME_NO_EXT="${FILENAME%.*}"
ITEM_KEY="{\"image_id\": {\"S\": \"${PRODUCT_ID}/${FILENAME_NO_EXT}\"}}"

DB_RESPONSE=$(aws dynamodb get-item \
  --table-name "$TABLE_NAME" \
  --key "$ITEM_KEY" \
  2>&1) || fail "DynamoDB query failed:\n$DB_RESPONSE"

ITEM=$(echo "$DB_RESPONSE" | jq -r '.Item') \
  || fail "Could not parse DynamoDB response"

if [[ "$ITEM" == "null" || -z "$ITEM" ]]; then
  warn "Item not found in DynamoDB yet. Pipeline may still be processing."
  warn "Retry manually:"
  echo "   aws dynamodb get-item --table-name $TABLE_NAME --key '$ITEM_KEY'"
  exit 1
fi

ok "DynamoDB record found"

THUMB_URL=$(echo "$DB_RESPONSE"  | jq -r '.Item.urls.M.thumb.S  // "not found"')
MEDIUM_URL=$(echo "$DB_RESPONSE" | jq -r '.Item.urls.M.medium.S // "not found"')
LARGE_URL=$(echo "$DB_RESPONSE"  | jq -r '.Item.urls.M.large.S  // "not found"')

echo "   thumb:  $THUMB_URL"
echo "   medium: $MEDIUM_URL"
echo "   large:  $LARGE_URL"
echo ""

# ─── step 7: verify cloudfront delivery ──────
info "Verifying CloudFront delivery for each variant..."

VARIANTS=("thumb" "medium" "large")
CF_PATH="/${VARIANTS[0]}/${PRODUCT_ID}/${FILENAME_NO_EXT}.webp"

ALL_OK=true
for VARIANT in "${VARIANTS[@]}"; do
  CF_URL="${CLOUDFRONT_URL}/${VARIANT}/${PRODUCT_ID}/${FILENAME_NO_EXT}.webp"
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -I "$CF_URL")
  if [[ "$HTTP_CODE" == "200" ]]; then
    ok "[$VARIANT] HTTP $HTTP_CODE — $CF_URL"
  else
    warn "[$VARIANT] HTTP $HTTP_CODE — $CF_URL"
    ALL_OK=false
  fi
done

echo ""

# ─── summary ─────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if $ALL_OK; then
  echo -e "  ${GREEN}All checks passed ✓${NC}"
else
  echo -e "  ${YELLOW}Partial pass — CloudFront may need ~60s to propagate${NC}"
  echo "  Retry: curl -I ${CLOUDFRONT_URL}/thumb/${PRODUCT_ID}/${FILENAME_NO_EXT}.webp"
fi
echo "  Product ID: $PRODUCT_ID"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
