#!/usr/bin/env bash

set -euo pipefail

INPUT_JSON="${1:-data/site-links.json}"
OUTPUT_JSON="${2:-data/site-links.updated.json}"

if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required but not installed" >&2
    exit 1
fi

if [[ ! -f "$INPUT_JSON" ]]; then
    echo "error: input manifest not found: $INPUT_JSON" >&2
    exit 1
fi

TMP_UPDATES="$(mktemp)"
TMP_UPDATES_JSON="$(mktemp)"
trap 'rm -f "$TMP_UPDATES" "$TMP_UPDATES_JSON"' EXIT

NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

jq -c '.links[] | select(.active == true)' "$INPUT_JSON" | while IFS= read -r link; do
    LINK_ID="$(jq -r '.id' <<<"$link")"
    HREF="$(jq -r '.href' <<<"$link")"
    STATUS="skipped"
    HTTP_STATUS="null"
    FINAL_URL="$HREF"

    if [[ "$HREF" =~ ^https?:// ]]; then
        RESPONSE="$(curl -L -sS --max-time 20 -o /dev/null -w '%{http_code}|%{url_effective}' "$HREF" || true)"
        HTTP_STATUS="${RESPONSE%%|*}"
        FINAL_URL="${RESPONSE#*|}"

        if [[ "$HTTP_STATUS" =~ ^2[0-9][0-9]$ || "$HTTP_STATUS" =~ ^3[0-9][0-9]$ ]]; then
            STATUS="ok"
        else
            STATUS="broken"
        fi
    fi

    jq -nc \
        --arg id "$LINK_ID" \
        --arg status "$STATUS" \
        --arg checked "$NOW_UTC" \
        --arg final "$FINAL_URL" \
        --arg http "$HTTP_STATUS" \
        '{
            id: $id,
            status: $status,
            lastChecked: $checked,
            finalUrl: $final,
            httpStatus: (if $http == "null" then null else ($http | tonumber?) end)
        }' >> "$TMP_UPDATES"
done

jq -s '.' "$TMP_UPDATES" > "$TMP_UPDATES_JSON"

jq \
    --arg generated "$NOW_UTC" \
    --argjson updates "$(cat "$TMP_UPDATES_JSON")" \
    '
    .generatedAt = $generated |
    .links = (
        .links | map(
            . as $link |
            (first($updates[] | select(.id == $link.id))) as $update |
            if $update then
                . + {
                    status: $update.status,
                    httpStatus: $update.httpStatus,
                    finalUrl: $update.finalUrl,
                    lastChecked: $update.lastChecked
                }
            else
                .
            end
        )
    )
    ' "$INPUT_JSON" > "$OUTPUT_JSON"

TOTAL_COUNT="$(jq '.links | length' "$OUTPUT_JSON")"
CHECKED_COUNT="$(jq '[.links[] | select(.status == "ok" or .status == "broken")] | length' "$OUTPUT_JSON")"
BROKEN_COUNT="$(jq '[.links[] | select(.status == "broken")] | length' "$OUTPUT_JSON")"
SKIPPED_COUNT="$(jq '[.links[] | select(.status == "skipped")] | length' "$OUTPUT_JSON")"

echo "checked manifest: $INPUT_JSON"
echo "wrote updated manifest: $OUTPUT_JSON"
echo "summary: total=$TOTAL_COUNT checked=$CHECKED_COUNT broken=$BROKEN_COUNT skipped=$SKIPPED_COUNT"
