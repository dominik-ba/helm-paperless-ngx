#!/usr/bin/env bash
# Prints a Markdown report (stdout) of the digest-pinned Bitnami images whose pin
# differs between two values.yaml files, with the application version each digest
# contains (read from the image's OCI label / APP_VERSION in the registry).
#
# Why: the images are pinned as `latest@sha256:...`, so Renovate shows only two
# digests and the application version (e.g. a PostgreSQL major change) is invisible.
#
# Prints nothing when no digest-pinned image changed.
# Never fails because of a registry problem: the version is then reported as unknown.
#
# Usage: image-versions.sh <base-values.yaml> <head-values.yaml>
# Needs: yq (mikefarah), jq, curl. Only anonymous, read-only registry access.

set -uo pipefail

base_file=${1:?base values.yaml}
head_file=${2:?head values.yaml}

# values.yaml key -> product name used in the "This digest is <Name> <version>." comment
declare -A names=([postgresql]=PostgreSQL [redis]=Redis)

digest_re='^sha256:[0-9a-f]{64}$'
repo_re='^[a-z0-9][a-z0-9/_-]*$'
version_re='^[0-9][0-9A-Za-z._+-]*$'

registry_token=""
registry_token_repo=""

# resolve <repository> <digest> -> application version, or "unknown"
resolve() {
    local repo=$1 digest=$2 accept manifest media image_digest config version
    accept='application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json'

    if [ "$registry_token_repo" != "$repo" ]; then
        registry_token=$(curl -fsS --max-time 20 \
            "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repo}:pull" \
            | jq -r '.token // empty') || registry_token=""
        registry_token_repo=$repo
    fi
    [ -n "$registry_token" ] || { echo unknown; return; }

    get() { curl -fsSL --max-time 30 -H "Authorization: Bearer $registry_token" "$@"; }

    manifest=$(get -H "Accept: $accept" "https://registry-1.docker.io/v2/${repo}/manifests/${digest}") || { echo unknown; return; }
    media=$(jq -r '.mediaType // empty' <<<"$manifest")
    case "$media" in
        *manifest.list* | *image.index*)
            image_digest=$(jq -r '[.manifests[] | select(.platform.architecture=="amd64")][0].digest // .manifests[0].digest' <<<"$manifest")
            [[ "$image_digest" =~ $digest_re ]] || { echo unknown; return; }
            manifest=$(get -H "Accept: $accept" "https://registry-1.docker.io/v2/${repo}/manifests/${image_digest}") || { echo unknown; return; }
            ;;
    esac
    config=$(jq -r '.config.digest // empty' <<<"$manifest")
    [[ "$config" =~ $digest_re ]] || { echo unknown; return; }
    version=$(get "https://registry-1.docker.io/v2/${repo}/blobs/${config}" \
        | jq -r '.config.Labels["org.opencontainers.image.version"] // ((.config.Env // [])[] | select(startswith("APP_VERSION=")) | sub("^APP_VERSION=";"")) // empty' \
        | head -n 1) || version=""
    # The value comes from an external registry: accept only a plain version string.
    [[ "$version" =~ $version_re ]] && echo "$version" || echo unknown
}

major() { echo "${1%%.*}"; }

rows=""
notes=""
for key in postgresql redis; do
    old_tag=$(yq -r ".${key}.image.tag // \"\"" "$base_file")
    new_tag=$(yq -r ".${key}.image.tag // \"\"" "$head_file")
    repo=$(yq -r ".${key}.image.repository // \"\"" "$head_file")
    registry=$(yq -r ".${key}.image.registry // \"\"" "$head_file")
    [ "$old_tag" != "$new_tag" ] || continue
    [[ "$new_tag" == *@sha256:* ]] || continue

    old_digest=${old_tag#*@}
    new_digest=${new_tag#*@}
    if [ "$registry" != "registry-1.docker.io" ] || ! [[ "$repo" =~ $repo_re ]] \
        || ! [[ "$old_digest" =~ $digest_re ]] || ! [[ "$new_digest" =~ $digest_re ]]; then
        rows+="| \`${key}\` | unsupported image reference | | |"$'\n'
        continue
    fi

    old_v=$(resolve "$repo" "$old_digest")
    new_v=$(resolve "$repo" "$new_digest")
    name=${names[$key]}
    commented=$(grep -o "This digest is ${name} [0-9][0-9.]*" "$head_file" | awk '{print $NF}' | sed 's/\.$//' | head -n 1)

    if [ "$old_v" = unknown ] || [ "$new_v" = unknown ]; then
        status="⚠️ could not be read from the registry"
    elif [ "$(major "$old_v")" != "$(major "$new_v")" ]; then
        status="🛑 **major version change**"
        if [ "$key" = postgresql ]; then
            notes+="- **PostgreSQL major version change ($old_v → $new_v): the existing data directory needs a migration (pg_dump/restore). Do not merge without one.**"$'\n'
        else
            notes+="- Redis major version change ($old_v → $new_v): read the upstream release notes before merging."$'\n'
        fi
    elif [ "$old_v" = "$new_v" ]; then
        status="✅ same version (image rebuild)"
    else
        status="✅ same major version"
    fi

    rows+="| \`${key}\` | ${name} ${old_v} (\`${old_digest:7:7}\`) | ${name} ${new_v} (\`${new_digest:7:7}\`) | ${status} |"$'\n'

    if [ "$new_v" != unknown ] && [ "$commented" != "$new_v" ]; then
        notes+="- The comment above \`${key}.image\` in \`values.yaml\` says \"This digest is ${name} ${commented:-?}.\" but the new digest is ${name} ${new_v}. Update the comment."$'\n'
    fi
done

[ -n "$rows" ] || exit 0

cat <<EOF
### Image versions behind the changed digests

| Subchart | Before | After | Result |
|---|---|---|---|
${rows}
${notes}
_Read from the image's OCI label in the registry (amd64 manifest). Only the application version is compared, not the OS packages of the base image._
EOF
