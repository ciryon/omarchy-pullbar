#!/usr/bin/env bash
# Prints {"review":[...],"assigned":[...],"authored":[...]} of open PRs for the
# logged-in gh account. Any failing query degrades to an empty list.
set -uo pipefail

fields=number,title,url,repository,isDraft,updatedAt
limit="${1:-10}"

query() {
  gh search prs --state open --limit "$limit" --json "$fields" "$@" 2>/dev/null || echo '[]'
}

printf '{"review":%s,"assigned":%s,"authored":%s}\n' \
  "$(query --review-requested=@me)" \
  "$(query --assignee=@me)" \
  "$(query --author=@me)"
