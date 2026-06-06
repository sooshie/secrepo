# Cleanup Notes After Design Selection

Status: visual direction approved (Option 2), implementation in progress.

## Newly requested requirements (next phase)
- Source of truth should move to a JSON document that drives all site URL/content entries.
- index.html should load and render site URLs from that JSON source.
- check_urls.sh should validate the URLs and output an updated JSON document usable by the site.
- check_urls output format should be directly translatable into the production site data file.

## Implemented in this phase
- Added JSON URL manifest at data/site-links.json (seeded from current index.html href values).
- index.html now loads data/site-links.json and applies href values to all anchors at runtime.
- check_urls.sh now reads JSON manifest input and writes updated manifest output with status, httpStatus, finalUrl, and lastChecked.
- Internal anchors (#...) and static legal links (for example Creative Commons attribution link) are intentionally excluded from the JSON manifest and remain static in HTML.
- Added scripts/rebuild_site_links_json.sh to rebuild data/site-links.json from list-item rows in index.html with fields: href, text, description, license.
- index.html now uses manifest text and description/license for simple single-anchor list items, so those rows are data-driven from JSON.
- Rebuild parser now captures nested multi-anchor sub-bullets (for example: Description -> Drive folder -> notebook rows).
- For duplicate href values that appear with different sub-bullet contexts, manifest stores all contexts in variants to avoid data loss.

## Current checker usage
- Run default input/output: ./check_urls.sh
- Run custom paths: ./check_urls.sh path/to/input.json path/to/output.json
- Suggested deploy flow: run checker and promote data/site-links.updated.json to data/site-links.json after review.

## Required cleanup tasks
- Remove duplicate analytics snippets in index.html and keep one approved telemetry block.
- Replace legacy jQuery + Bootstrap 3 script stack with the selected modern stack.
- Replace footer date placeholder flow with semantic build/deploy metadata injection (time element + datetime).
- Improve URL checker logic to validate only absolute http/https links and provide clearer reporting.

## URL checker follow-up details
- Skip anchors (#...), mailto:, tel:, javascript:, and local relative links.
- Capture HTTP status codes for failing links.
- Emit grouped output summary (count checked, count failed, failed list).

## Definition of done
- No duplicate analytics scripts.
- Footer date automatically set on deploy and visible in semantic markup.
- URL checker output can be used as a CI signal.
