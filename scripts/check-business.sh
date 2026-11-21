#!/usr/bin/env bash
set -eu

if [[ $# != 1 || ( $1 != flat && $1 != segmented ) ]]; then
    printf 'Usage: %s {flat|segmented}\n' "$0" >&2
    exit 2
fi

layout=$1
project="flatland-$layout"
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

compose() {
    # Git Bash must pass Linux paths such as /dev/null through to the container.
    MSYS2_ARG_CONV_EXCL='*' docker compose -p "$project" \
        -f lab/compose.services.yaml -f "lab/compose.$layout.yaml" "$@"
}

if ! running=$(compose ps --status running --quiet) || [[ -z $running ]]; then
    printf 'Cannot find running containers in %s. See docs/runbook.md for startup.\n' "$project" >&2
    exit 2
fi

revision=$(git rev-parse --verify HEAD 2>/dev/null) || revision=unknown
printf 'Business validation | layout=%s | project=%s | revision=%s\n' "$layout" "$project" "$revision"

failures=0

matches_expected() {
    local match=$1 expected=$2 output=$3
    case "$match" in
        http-contains) [[ $output == *"$expected"*$'\nHTTP 200' ]] ;;
        http-exact) [[ $output == "$expected"$'\nHTTP 200' || $output == "$expected"$'\n\nHTTP 200' ]] ;;
        exact) [[ $output == "$expected" ]] ;;
    esac
}

run_check() {
    local id=$1 path=$2 match=$3 expected=$4
    shift 4
    local timestamp output status=0 result expected_result
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    output=$(compose exec -T "$@" 2>&1) || status=$?

    case "$match" in
        http-contains) expected_result="HTTP 200, body contains '$expected'" ;;
        http-exact) expected_result="HTTP 200, body is '$expected'" ;;
        exact) expected_result="output is '$expected'" ;;
    esac

    if (( status == 0 )) && matches_expected "$match" "$expected" "$output"; then
        result=PASS
    else
        result=FAIL
        failures=$((failures + 1))
    fi

    printf '%s %s %s %s\n' "$id" "$result" "$timestamp" "$path"
    printf '  Expected: %s\n  Observed: exit=%d output=%q\n' "$expected_result" "$status" "$output"
}

run_check B01 'workstation -> web:443 (HTTPS)' http-contains 'Flatland demo page' \
    --user lab workstation curl -q -fkSs --noproxy '*' --max-time 10 \
    --write-out '\nHTTP %{http_code}' https://web/

run_check B02 'web -> app:8080 (HTTP)' http-exact 'healthy' \
    web curl -q -fsS --noproxy '*' --max-time 10 \
    --write-out '\nHTTP %{http_code}' http://app:8080/health

run_check B03 'app -> database:5432 (PostgreSQL)' exact 'flatland-db-ok' \
    -e PGPASSWORD=flatland-reader-demo app timeout 10s psql -X -w -v ON_ERROR_STOP=1 \
    -h database -U lab_reader -d flatland -Atc 'SELECT value FROM lab_fixture WHERE id = 1'

ssh_check() {
    local id=$1 destination=$2
    run_check "$id" "jump -> $destination:22 (SSH)" exact 'lab' \
        -e SSHPASS=flatland-ssh-demo jump timeout 10s sshpass -e ssh \
        -o ConnectTimeout=5 -o NumberOfPasswordPrompts=1 \
        -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        "lab@$destination" id -un
}

ssh_check B04 workstation
ssh_check B05 web
ssh_check B06 app
ssh_check B07 database
ssh_check B08 file

printf 'Summary: %d passed, %d failed\n' "$((8 - failures))" "$failures"
if (( failures > 0 )); then
    exit 1
fi
