#!/usr/bin/env bash
# Checks that the artifacthub.io/images annotation lists exactly the images the chart deploys with
# every bundled service on, so Artifact Hub's security report scans what users really run.
set -euo pipefail
chart=charts/open-archiver

rendered=$(helm template ci "$chart" -f "$chart/ci/bundled-values.yaml" --skip-tests \
  | sed -nE 's/^ *image: *"?([^"@ ]+)(@[^" ]*)?"? *$/\1/p' | sort -u)
annotated=$(helm show chart "$chart" \
  | sed -n '/artifacthub.io\/images:/,/^[^ ]/p' | sed -nE 's/^ *image: *([^ ]+) *$/\1/p' | sort -u)

if [ "$rendered" != "$annotated" ]; then
  echo "artifacthub.io/images in Chart.yaml does not match the rendered images."
  diff <(echo "$annotated") <(echo "$rendered") | sed 's/^</  annotated only:/; s/^>/  rendered only: /' | grep -v -e '^[0-9]' -e '^---'
  exit 1
fi
echo "artifacthub.io/images matches the $(echo "$rendered" | wc -l | tr -d ' ') rendered images"
