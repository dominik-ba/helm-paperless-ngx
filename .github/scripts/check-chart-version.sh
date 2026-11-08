#!/usr/bin/env bash
# Fails when a change alters what the chart renders but keeps a chart version that
# is already released. Released versions are immutable (release workflow), so such a
# change would be merged to main without ever being published.
#
# Compared against the release tag v<version>:
#   - every file that defines the render: values.yaml, values.schema.json,
#     templates/, crds/, files/, Chart.lock
#   - Chart.yaml without its `version:` line (appVersion, dependencies, ...)
# Comment-only changes in values.yaml count as changes: `helm show values` shows them.
#
# Also fails when the chart version is lower than the newest release.
#
# Usage: check-chart-version.sh   (run from the chart root, needs git and network
# access to the public origin repository)

set -euo pipefail

version=$(awk '/^version:/ {print $2}' Chart.yaml | tr -d '"')
if [ -z "$version" ]; then
    echo "::error file=Chart.yaml::no version: found in Chart.yaml"
    exit 1
fi
echo "Chart version: $version"

latest=$(git ls-remote --tags --refs origin 'v*' | sed 's#.*refs/tags/v##' | sort -V | tail -n 1)
echo "Newest release: ${latest:-none}"

if [ -n "$latest" ]; then
    highest=$(printf '%s\n%s\n' "$latest" "$version" | sort -V | tail -n 1)
    if [ "$highest" != "$version" ]; then
        echo "::error file=Chart.yaml::chart version $version is lower than the newest release $latest"
        exit 1
    fi
fi

tag="v$version"
if ! git ls-remote --exit-code --tags --refs origin "refs/tags/$tag" >/dev/null; then
    echo "OK: $version is not released yet; merging this releases it."
    exit 0
fi

git fetch --quiet --depth=1 --no-tags origin "refs/tags/$tag:refs/tags/$tag"

render_paths=(values.yaml values.schema.json templates crds files Chart.lock)
changed=$(git diff --name-only "$tag" -- "${render_paths[@]}")

chart_yaml_diff=$(diff <(git show "$tag:Chart.yaml" | grep -v '^version:') \
    <(grep -v '^version:' Chart.yaml) || true)
if [ -n "$chart_yaml_diff" ]; then
    changed=$(printf '%s\nChart.yaml\n' "$changed")
fi

changed=$(printf '%s\n' "$changed" | sed '/^$/d')
if [ -z "$changed" ]; then
    echo "OK: $version is released, and nothing that affects the render changed since $tag."
    exit 0
fi

echo "Changed since $tag:"
printf '%s\n' "$changed" | sed 's/^/  /'
echo "::error file=Chart.yaml::these changes alter the chart, but version $version is already released (tag $tag). Bump version: in Chart.yaml (see Releases in AGENTS.md)."
exit 1
