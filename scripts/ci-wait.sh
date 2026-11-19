#!/usr/bin/env bash
# Czeka na run GitHub Actions dla bieżącego commita i zwraca jego wynik.
# Przy błędzie wypisuje końcówkę logów nieudanych kroków.
set -euo pipefail
SHA="$(git rev-parse HEAD)"
ID=""
for _ in $(seq 1 30); do
  ID="$(gh run list --commit "$SHA" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
  [ -n "$ID" ] && break
  sleep 5
done
[ -n "$ID" ] || { echo "Brak runu CI dla $SHA"; exit 1; }
echo "Run CI: $ID"
if ! gh run watch "$ID" --exit-status --interval 20 > /dev/null; then
  gh run view "$ID" --log-failed | tail -120
  echo "CI: FAIL"
  exit 1
fi
echo "CI: PASS"
