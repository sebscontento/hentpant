#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SUPABASE_URL="${SUPABASE_URL:-https://jfyuhjxmjbhxtfgtfkhd.supabase.co}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-sb_publishable_pRB2ct6_Jc_RcPizYDO5Tw_Df-41O5V}"

RUN_ID="${RUN_ID:-journey-$(date +%Y%m%d%H%M%S)}"
VERIFY_PASSWORD="${VERIFY_PASSWORD:-PantCollect123!}"
GIVER_EMAIL="${GIVER_EMAIL:-${RUN_ID}-giver@example.com}"
RECEIVER_EMAIL="${RECEIVER_EMAIL:-${RUN_ID}-receiver@example.com}"
VERIFY_LATITUDE="${VERIFY_LATITUDE:-55.6761}"
VERIFY_LONGITUDE="${VERIFY_LONGITUDE:-12.5683}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

api_request() {
  local method="$1"
  local url="$2"
  local token="${3:-}"
  local body="${4:-}"
  local prefer="${5:-}"
  local response_file
  local status_code
  local response_body

  local args=(
    -sS
    -X "$method"
    "$url"
    -H "apikey: $SUPABASE_ANON_KEY"
  )

  if [[ -n "$token" ]]; then
    args+=(-H "Authorization: Bearer $token")
  fi

  if [[ -n "$prefer" ]]; then
    args+=(-H "Prefer: $prefer")
  fi

  if [[ -n "$body" ]]; then
    args+=(-H "Content-Type: application/json" -d "$body")
  fi

  response_file="$(mktemp)"

  if ! status_code="$(curl "${args[@]}" -o "$response_file" -w '%{http_code}')"; then
    rm -f "$response_file"
    return 1
  fi

  response_body="$(cat "$response_file")"
  rm -f "$response_file"

  if (( status_code < 200 || status_code >= 300 )); then
    if [[ -n "$response_body" ]]; then
      printf '%s\n' "$response_body" >&2
    fi
    echo "HTTP $status_code for $method $url" >&2
    return 22
  fi

  printf '%s' "$response_body"
}

sign_up() {
  local email="$1"
  local password="$2"
  local display_name="$3"
  local can_give="$4"
  local can_receive="$5"

  local payload
  payload="$(
    jq -cn \
      --arg email "$email" \
      --arg password "$password" \
      --arg display_name "$display_name" \
      --argjson can_give "$can_give" \
      --argjson can_receive "$can_receive" \
      '{
        email: $email,
        password: $password,
        data: {
          display_name: $display_name,
          can_give: $can_give,
          can_receive: $can_receive
        }
      }'
  )"

  api_request POST "$SUPABASE_URL/auth/v1/signup" "" "$payload" >/dev/null
}

sign_in() {
  local email="$1"
  local password="$2"
  local payload

  payload="$(
    jq -cn \
      --arg email "$email" \
      --arg password "$password" \
      '{email: $email, password: $password}'
  )"

  if ! api_request POST "$SUPABASE_URL/auth/v1/token?grant_type=password" "" "$payload"; then
    echo "" >&2
    echo "Email sign-in failed for $email." >&2
    echo "If confirm email is enabled in Supabase, confirm the user or disable confirmation for automated verification." >&2
    exit 1
  fi
}

wait_for_profile() {
  local user_id="$1"
  local token="$2"

  local attempt
  for attempt in $(seq 1 12); do
    local response
    response="$(
      api_request \
        GET \
        "$SUPABASE_URL/rest/v1/profiles?id=eq.$user_id&select=id,display_name,email,can_give,can_receive,staff_role,moderator_request_status" \
        "$token"
    )"

    if jq -e 'length > 0' >/dev/null 2>&1 <<<"$response"; then
      printf '%s\n' "$response"
      return 0
    fi

    sleep 1
  done

  echo "Timed out waiting for profile row for user $user_id" >&2
  exit 1
}

fetch_listing() {
  local listing_id="$1"
  local token="$2"

  api_request \
    GET \
    "$SUPABASE_URL/rest/v1/listings?id=eq.$listing_id&select=id,status,giver_id,collector_id,created_at,quantity_text" \
    "$token"
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [[ "$expected" != "$actual" ]]; then
    echo "Assertion failed for $label" >&2
    echo "Expected: $expected" >&2
    echo "Actual:   $actual" >&2
    exit 1
  fi
}

require_command curl
require_command jq

echo "Verifying PantCollect user journey against $SUPABASE_URL"
echo "Run id: $RUN_ID"
echo "Giver: $GIVER_EMAIL"
echo "Receiver: $RECEIVER_EMAIL"
echo ""

echo "1. Creating fresh giver and receiver accounts..."
sign_up "$GIVER_EMAIL" "$VERIFY_PASSWORD" "Journey Giver $RUN_ID" true false
sign_up "$RECEIVER_EMAIL" "$VERIFY_PASSWORD" "Journey Receiver $RUN_ID" false true

echo "2. Signing in both accounts..."
giver_session="$(sign_in "$GIVER_EMAIL" "$VERIFY_PASSWORD")"
receiver_session="$(sign_in "$RECEIVER_EMAIL" "$VERIFY_PASSWORD")"

giver_id="$(jq -r '.user.id // empty' <<<"$giver_session")"
receiver_id="$(jq -r '.user.id // empty' <<<"$receiver_session")"
giver_token="$(jq -r '.access_token // empty' <<<"$giver_session")"
receiver_token="$(jq -r '.access_token // empty' <<<"$receiver_session")"

if [[ -z "$giver_id" || -z "$giver_token" || -z "$receiver_id" || -z "$receiver_token" ]]; then
  echo "Did not receive a usable session for both users." >&2
  exit 1
fi

echo "3. Waiting for profile rows..."
giver_profile="$(wait_for_profile "$giver_id" "$giver_token")"
receiver_profile="$(wait_for_profile "$receiver_id" "$receiver_token")"

assert_equals "true" "$(jq -r '.[0].can_give' <<<"$giver_profile")" "giver can_give"
assert_equals "false" "$(jq -r '.[0].can_receive' <<<"$giver_profile")" "giver can_receive"
assert_equals "false" "$(jq -r '.[0].can_give' <<<"$receiver_profile")" "receiver can_give"
assert_equals "true" "$(jq -r '.[0].can_receive' <<<"$receiver_profile")" "receiver can_receive"

echo "4. Creating a listing as the giver..."
listing_payload="$(
  jq -cn \
    --arg giver_id "$giver_id" \
    --arg quantity_text "Journey verification $RUN_ID" \
    --arg detail "Created by scripts/verify-user-journey.sh" \
    --arg latitude "$VERIFY_LATITUDE" \
    --arg longitude "$VERIFY_LONGITUDE" \
    '{
      giver_id: $giver_id,
      photo_paths: [],
      quantity_text: $quantity_text,
      bag_size: "medium",
      latitude: ($latitude | tonumber),
      longitude: ($longitude | tonumber),
      detail: $detail
    }'
)"

created_listing="$(
  api_request \
    POST \
    "$SUPABASE_URL/rest/v1/listings?select=id,status,giver_id,collector_id,created_at" \
    "$giver_token" \
    "$listing_payload" \
    "return=representation"
)"

listing_id="$(jq -r '.[0].id // empty' <<<"$created_listing")"
assert_equals "available" "$(jq -r '.[0].status // empty' <<<"$created_listing")" "listing status after create"

if [[ -z "$listing_id" ]]; then
  echo "Did not receive a listing id from the create step." >&2
  exit 1
fi

echo "5. Claiming the listing as the receiver..."
rpc_payload="$(jq -cn --arg listing_id "$listing_id" '{p_listing_id: $listing_id}')"
api_request POST "$SUPABASE_URL/rest/v1/rpc/claim_listing" "$receiver_token" "$rpc_payload" >/dev/null

pending_listing="$(fetch_listing "$listing_id" "$receiver_token")"
assert_equals "pending_pickup" "$(jq -r '.[0].status // empty' <<<"$pending_listing")" "listing status after claim"
assert_equals "$receiver_id" "$(jq -r '.[0].collector_id // empty' <<<"$pending_listing")" "collector after claim"

echo "6. Marking the listing as done after pickup..."
api_request POST "$SUPABASE_URL/rest/v1/rpc/mark_listing_picked_up" "$receiver_token" "$rpc_payload" >/dev/null

completed_listing="$(fetch_listing "$listing_id" "$receiver_token")"
assert_equals "completed" "$(jq -r '.[0].status // empty' <<<"$completed_listing")" "listing status after mark done"
assert_equals "$receiver_id" "$(jq -r '.[0].collector_id // empty' <<<"$completed_listing")" "collector after mark done"

echo ""
echo "Journey verification succeeded."
echo ""
jq -n \
  --arg run_id "$RUN_ID" \
  --arg giver_email "$GIVER_EMAIL" \
  --arg receiver_email "$RECEIVER_EMAIL" \
  --arg listing_id "$listing_id" \
  --arg final_status "$(jq -r '.[0].status // empty' <<<"$completed_listing")" \
  '{
    run_id: $run_id,
    giver_email: $giver_email,
    receiver_email: $receiver_email,
    listing_id: $listing_id,
    final_status: $final_status
  }'

echo ""
echo "Note: this script leaves the created users and completed listing in Supabase for auditability."
