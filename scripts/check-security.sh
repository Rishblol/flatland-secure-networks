#!/usr/bin/env bash
set -eu
set -o pipefail

if [[ $# != 1 || ( $1 != flat && $1 != segmented ) ]]; then
    printf 'Usage: %s {flat|segmented}\n' "$0" >&2
    exit 2
fi

layout=$1
project="flatland-$layout"
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export MSYS2_ARG_CONV_EXCL='*'

compose() {
    docker compose -p "$project" -f lab/compose.services.yaml -f "lab/compose.$layout.yaml" "$@"
}

inconclusive() {
    printf 'INCONCLUSIVE | %s\n' "$1" >&2
    exit 2
}

require_health() {
    local phase=$1 snapshot service
    snapshot=$(compose ps --format '{{.Service}}|{{.State}}|{{.Health}}') ||
        inconclusive "Cannot read $phase service health for $project."
    printf 'Service health (%s)\n%s\n' "$phase" "$snapshot"
    for service in workstation web app database file; do
        grep -Fxq "$service|running|healthy" <<<"$snapshot" ||
            inconclusive "$service is unready ($phase)."
    done
    grep -Fxq 'jump|running|' <<<"$snapshot" || inconclusive "jump is unready ($phase)."
    if [[ $layout == segmented ]]; then
        grep -Fxq 'router|running|healthy' <<<"$snapshot" || inconclusive "router is unready ($phase)."
    fi
}

service_ip() {
    local service=$1 zone=$2 container address
    if [[ $layout == flat ]]; then zone=flat; fi
    container=$(compose ps --status running --quiet "$service") || return 1
    [[ -n $container && $container != *$'\n'* ]] || return 1
    address=$(docker inspect --format "{{with index .NetworkSettings.Networks \"${project}_${zone}\"}}{{.IPAddress}}{{end}}" "$container") || return 1
    [[ $address =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    printf '%s\n' "$address"
}

fixture_state() {
    compose exec -T --user lab file sh -c '
        [ -d /srv/transfer ] && [ -x /srv/transfer ] || exit 1
        if [ -e /srv/transfer/transfer.txt ] || [ -L /srv/transfer/transfer.txt ]; then
            printf "present\n"
        else
            printf "absent\n"
        fi
    '
}

matching_drop() {
    local started_at=$1 destination=$2 source_port=$3 port=$4 drops attempt
    for attempt in 1 2 3; do
        drops=$(compose logs --since "$started_at" --timestamps --no-color --no-log-prefix router |
            awk -v source="$workstation_ip" -v destination="$destination" -v source_port="$source_port" -v port="$port" '
                {
                    line = " " $0 " "
                    if (index(line, " flatland-forward-drop ") && index(line, " IN=zone-user ") &&
                        index(line, " OUT=zone-server ") && index(line, " PROTO=TCP ") && index(line, " SYN ") &&
                        index(line, " SRC=" source " ") && index(line, " DST=" destination " ") &&
                        index(line, " SPT=" source_port " ") && index(line, " DPT=" port " ")) {
                        sub(/[[:space:]]+$/, "")
                        print
                    }
                }
            ') || return 2
        if [[ -n $drops ]]; then
            printf '%s\n' "$drops"
            return 0
        fi
        if (( attempt < 3 )); then sleep 0.25; fi
    done
    return 1
}

run_probe() {
    local id=$1 service=$2 destination=$3 port=$4
    local expected started_at output status=0 drops='' log_status=0
    local source_port=$next_port
    next_port=$((next_port + 1))
    started_at=$(compose exec -T --user lab workstation date -u '+%Y-%m-%dT%H:%M:%S.%NZ') ||
        inconclusive 'Cannot obtain the workstation clock.'
    output=$(compose exec -T -e LC_ALL=C --user lab workstation nc -4 -n -z -v -w 2 \
        -p "$source_port" "$destination" "$port" 2>&1) || status=$?

    probe_result=FAIL
    if [[ $layout == flat ]]; then
        expected='TCP connection succeeds'
        if (( status == 0 )); then probe_result=PASS; fi
    else
        expected='TCP connection times out and router logs the matching SYN drop'
        if (( status == 1 )) && [[ $output == *'timed out'* ]]; then
            drops=$(matching_drop "$started_at" "$destination" "$source_port" "$port") || log_status=$?
            case "$log_status" in
                0) probe_result=PASS; correlated=$((correlated + 1)) ;;
                2) probe_result=INCONCLUSIVE ;;
            esac
        fi
    fi
    if [[ $probe_result == FAIL ]]; then failures=$((failures + 1)); fi

    printf '%s %s | %s | workstation %s:%s -> %s %s:%s (TCP)\n' \
        "$id" "$probe_result" "$started_at" "$workstation_ip" "$source_port" "$service" "$destination" "$port"
    printf '  Expected: %s\n  Observed: exit=%d output=%q\n' "$expected" "$status" "$output"
    if [[ -n $drops ]]; then
        printf '  Router evidence:\n%s\n' "$drops"
    elif (( log_status == 2 )); then
        inconclusive "Cannot read router logs for $id."
    elif [[ $layout == segmented ]]; then
        printf '  Router evidence: no matching drop confirmed for this observation\n'
    fi
}

revision=$(git rev-parse --verify HEAD 2>/dev/null) || revision=unknown
printf 'Security validation | layout=%s | project=%s | revision=%s\n' "$layout" "$project" "$revision"
require_health before
workstation_ip=$(service_ip workstation user) || inconclusive 'Cannot resolve the workstation lab address.'
app_ip=$(service_ip app server) || inconclusive 'Cannot resolve the app lab address.'
database_ip=$(service_ip database server) || inconclusive 'Cannot resolve the database lab address.'
file_ip=$(service_ip file server) || inconclusive 'Cannot resolve the file server lab address.'
compose exec -T --user lab workstation sh -c '
    fixture=/fixtures/transfer.txt
    [ -f "$fixture" ] && [ -r "$fixture" ] && [ -s "$fixture" ]
' ||
    inconclusive 'The workstation synthetic fixture is unavailable.'
fixture_before=$(fixture_state) || inconclusive 'Cannot check the destination fixture before validation.'

printf 'Business controls\n'
bash scripts/check-business.sh "$layout" || inconclusive 'A business control failed.'

failures=0
correlated=0
next_port=$((20000 + RANDOM % 9000))
run_probe S01-app app "$app_ip" 8080
run_probe S01-database database "$database_ip" 5432
run_probe S01-file file "$file_ip" 445
printf 'S03 %s | SMB transport | Uses the identical S01-file observation and the file service health checks.\n' "$probe_result"
run_probe S02 database "$database_ip" 22

fixture_after=$(fixture_state) || inconclusive 'Cannot check the destination fixture after validation.'
require_health after

fixture_result=PASS
if [[ $fixture_before != absent || $fixture_after != absent ]]; then
    fixture_result=FAIL
    failures=$((failures + 1))
fi
printf 'S04-FIXTURE %s | source=available | destination before=%s after=%s\n' \
    "$fixture_result" "$fixture_before" "$fixture_after"
printf 'S04 NOT_RUN | End-to-end SMB copy | See S03 for the transport result.\n'

if [[ $layout == flat ]]; then
    printf 'L01 BASELINE | Router evidence applies to the segmented layout.\n'
elif (( correlated == 4 )); then
    printf 'L01 PASS | 4 of 4 fixed TCP probes matched router drop logs.\n'
else
    printf 'L01 FAIL | %d of 4 fixed TCP probes matched router drop logs.\n' "$correlated"
fi

if (( failures > 0 )); then
    printf 'Summary: FAIL (transport or fixture controls)\n'
    exit 1
fi
printf 'Summary: PASS (transport and fixture controls)\n'
