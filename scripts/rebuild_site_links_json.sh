#!/usr/bin/env bash

set -euo pipefail

INPUT_HTML="${1:-index.html}"
OUTPUT_JSON="${2:-data/site-links.json}"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required but not installed" >&2
  exit 1
fi

if [[ ! -f "$INPUT_HTML" ]]; then
  echo "error: input HTML not found: $INPUT_HTML" >&2
  exit 1
fi

EXISTING_JSON=""
if [[ -f "$OUTPUT_JSON" ]]; then
  EXISTING_JSON="$OUTPUT_JSON"
else
  EXISTING_JSON="$(mktemp)"
  echo '{"schemaVersion":1,"generatedAt":null,"links":[]}' > "$EXISTING_JSON"
fi

TMP_PARSED="$(mktemp)"
TMP_PARSED_ARRAY="$(mktemp)"
TMP_OUTPUT="$(mktemp)"
trap 'rm -f "$TMP_PARSED" "$TMP_PARSED_ARRAY" "$TMP_OUTPUT"' EXIT

perl -MJSON::PP -ne '
  next if /<!--/;
  next unless /<li>/ && /<\/li>/ && /<a\b[^>]*href="/;

  my ($li) = /<li>(.*)<\/li>/;
  next unless defined $li;

  my $license = undef;
  if ($li =~ /\[\s*License\s+Info\s*:\s*(.*?)\]/i) {
    $license = $1;
    $license =~ s/<[^>]+>//g;
    $license =~ s/\s+/ /g;
    $license =~ s/^\s+|\s+$//g;
  }

  my @anchors = ($li =~ m{<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>}g);
  next unless @anchors;

  my $anchor_count = scalar(@anchors) / 2;

  for (my $i = 0; $i < @anchors; $i += 2) {
    my $href = $anchors[$i];
    my $text = $anchors[$i + 1];

    next if $href =~ /^#/;
    next if $href =~ /creativecommons\.org/i;

    $text =~ s/<[^>]+>//g;
    $text =~ s/\s+/ /g;
    $text =~ s/^\s+|\s+$//g;

    my $description_raw = "";

    if ($anchor_count == 1) {
      if ($li =~ /<a\b[^>]*href="\Q$href\E"[^>]*>.*?<\/a>\s*-\s*(.*)$/) {
        $description_raw = $1;
      } elsif ($li =~ /<a\b[^>]*href="\Q$href\E"[^>]*>.*?<\/a>\s*(.*)$/) {
        $description_raw = $1;
      }
    } else {
      $description_raw = $li;
    }

    $description_raw =~ s/\[\s*License\s+Info\s*:.*$//i;
    $description_raw =~ s/<[^>]+>//g;
    $description_raw =~ s/\s+/ /g;
    $description_raw =~ s/^\s+|\s+$//g;

    if ($anchor_count > 1 && length($text)) {
      $description_raw =~ s/^\Q$text\E\s*//;
    }

    my %obj = (
      href => $href,
      text => $text,
      description => $description_raw,
      license => $license,
    );

    print encode_json(\%obj), "\n";
  }
' "$INPUT_HTML" > "$TMP_PARSED"

jq -s '
  def normalize_href:
    if test("^(https?://|ftp://)") then . else "https://secrepo.com/" + ltrimstr("/") end;

  map(. + {normalizedHref: (.href | normalize_href)})
  | sort_by(.normalizedHref)
  | group_by(.normalizedHref)
  | map({
      sourceHref: .[0].href,
      href: .[0].normalizedHref,
      text: .[0].text,
      description: .[0].description,
      license: ((map(.license) | map(select(. != null and . != "")) | .[0]) // null),
      variants: (map({text, description, license}) | unique)
    })
' "$TMP_PARSED" > "$TMP_PARSED_ARRAY"

jq \
  --arg generated "$NOW_UTC" \
  --slurpfile parsed "$TMP_PARSED_ARRAY" \
  --slurpfile existing "$EXISTING_JSON" \
  '
  def normalize_href:
    if test("^(https?://|ftp://)") then . else "https://secrepo.com/" + ltrimstr("/") end;

  def existing_map:
    reduce ($existing[0].links // [])[] as $e ({}; .[($e.href | normalize_href)] = $e);

  ($parsed[0] // []) as $newLinks |
  (existing_map) as $emap |
  {
    schemaVersion: 1,
    generatedAt: $generated,
    links: (
      $newLinks | map(
        . as $n |
        ($emap[$n.href] // {}) as $old |
        {
          id: ($n.sourceHref | @base64),
          sourceHref: $n.sourceHref,
          href: $n.href,
          text: $n.text,
          description: $n.description,
          license: $n.license,
          variants: $n.variants,
          active: ($old.active // true),
          status: ($old.status // "unknown"),
          httpStatus: ($old.httpStatus // null),
          finalUrl: ($old.finalUrl // null),
          lastChecked: ($old.lastChecked // null)
        }
      )
    )
  }
  ' "$EXISTING_JSON" > "$TMP_OUTPUT"

if [[ "$(jq '.links | length' "$TMP_OUTPUT")" -eq 0 ]]; then
  echo "error: no parseable list-item links were found in $INPUT_HTML" >&2
  exit 1
fi

mv "$TMP_OUTPUT" "$OUTPUT_JSON"

echo "rebuilt manifest: $OUTPUT_JSON"
echo "entries: $(jq '.links | length' "$OUTPUT_JSON")"
