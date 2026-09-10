#!/usr/bin/env bash
#
# Applies rabbitmq/definitions.json to the LOCAL broker through the management API.
#
# This is a development convenience, not the deploy path. In real environments the
# applications themselves declare this same file over AMQP during their release
# phase — see GC-253. Management-API import needs the `administrator` tag, which a
# CloudAMQP shared-plan user does not have, and it silently ignores objects that
# already exist with different arguments. An AMQP declare fails loudly instead.
#
#   make apply-definitions
#
# Import is a MERGE, not a sync: objects removed from definitions.json are not
# removed from the broker. Deletions stay manual, on purpose.
set -euo pipefail

MANAGEMENT_URL="${RABBIT_MQ_MANAGEMENT_URL:-http://localhost:15672}"
USERNAME="${RABBIT_MQ_USERNAME:-local_user}"
PASSWORD="${RABBIT_MQ_PASSWORD:-local_pass}"
VHOST="${RABBIT_MQ_VHOST:-/}"
DEFINITIONS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/definitions.json"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-60}"

[ -f "$DEFINITIONS" ] || { echo "definitions.json not found at $DEFINITIONS" >&2; exit 1; }

# definitions.json carries no vhost — the apps get it from their AMQP connection,
# and here it goes in the URL, so the same file serves both consumers.
VHOST_ENCODED="$(printf '%s' "$VHOST" | sed 's|/|%2F|g')"

# Credentials go to curl over stdin rather than argv, so they never show up in `ps`.
curl_auth() {
  curl --silent --show-error --config - "$@" <<<"user = \"$USERNAME:$PASSWORD\""
}

echo "Waiting for $MANAGEMENT_URL to answer..."
deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
until curl_auth --fail --output /dev/null "$MANAGEMENT_URL/api/overview" 2>/dev/null; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "Management API did not answer within ${TIMEOUT_SECONDS}s at $MANAGEMENT_URL" >&2
    exit 1
  fi
  sleep 2
done

echo "Applying $(basename "$DEFINITIONS") to $MANAGEMENT_URL, vhost $VHOST..."
curl_auth \
  --fail \
  --request POST \
  --header "content-type: application/json" \
  --data-binary "@$DEFINITIONS" \
  "$MANAGEMENT_URL/api/definitions/$VHOST_ENCODED"

echo "Definitions applied."
