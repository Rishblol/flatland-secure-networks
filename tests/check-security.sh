#!/usr/bin/env bash
set -eu

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
runner="$root/scripts/check-security.sh"

real_bash=$BASH
stub_dir=$(mktemp -d)
trap 'rm -f -- "$stub_dir/bash" "$stub_dir/docker" "$stub_dir/probe"; rmdir -- "$stub_dir"' EXIT
export PATH="$stub_dir:$PATH" STUB_DIR="$stub_dir"
cat >"$stub_dir/bash" <<'STUB'
#!/usr/bin/env sh
[ "$1" = scripts/check-business.sh ] && [ "$2" = "$LAYOUT" ] || exit 90
printf 'Business control fixture (%s)\n' "$2"
STUB
cat >"$stub_dir/docker" <<'STUB'
#!/usr/bin/env sh
set -eu
if [ "$1" = inspect ]; then
    case "$4" in
        workstation) printf '10.149.240.10\n' ;;
        app) printf '10.149.240.138\n' ;;
        database) printf '10.149.240.139\n' ;;
        file) printf '10.149.240.140\n' ;;
        *) exit 91 ;;
    esac
    exit
fi
[ "$1 $2 $3 $4 $5 $6 $7" = "compose -p flatland-$LAYOUT -f lab/compose.services.yaml -f lab/compose.$LAYOUT.yaml" ] || exit 92
shift 7
case "$1" in
    ps)
        if [ "$2" = --format ]; then
            for service in workstation web app database file; do
                [ "$SCENARIO" != unhealthy ] || [ "$service" != file ] || continue
                printf '%s|running|healthy\n' "$service"
            done
            printf 'jump|running|\n'
            if [ "$LAYOUT" = segmented ]; then printf 'router|running|healthy\n'; fi
        else
            printf '%s\n' "$5"
        fi
        ;;
    exec)
        case "$*" in
            *' file sh -c '*)
                if [ "$SCENARIO" = fixture-present ]; then printf 'present\n'; else printf 'absent\n'; fi
                ;;
            *' workstation sh -c '*)
                if [ "$SCENARIO" = unreadable-source ]; then exit 1; fi
                ;;
            *' workstation date -u '*) printf '2026-11-21T05:12:50.000000000Z\n' ;;
            *' workstation nc '*)
                next=''
                for arg do
                    prev=$next
                    next=$arg
                done
                sport=$(printf '%s\n' "$*" | sed -n 's/.* -p \([0-9]*\) .*/\1/p')
                printf '%s %s %s\n' "$sport" "$prev" "$next" >"$STUB_DIR/probe"
                if [ "$LAYOUT" = flat ] || { [ "$SCENARIO" = bypass ] && [ "$next" = 22 ]; }; then
                    printf 'connection succeeded\n'
                    exit 0
                fi
                printf 'connection timed out\n' >&2
                exit 1
                ;;
            *) exit 93 ;;
        esac
        ;;
    logs)
        [ "$2" = --since ] && [ "$3" = '2026-11-21T05:12:50.000000000Z' ] || exit 94
        read -r sport dest port <"$STUB_DIR/probe"
        if [ "$SCENARIO" = logs-error ] && [ "$port" = 22 ]; then exit 1; fi
        if [ "$SCENARIO" = unrelated ] && [ "$port" = 22 ]; then sport=$((sport + 1)); fi
        printf '2026-11-21T05:12:50.200000000Z flatland-forward-drop IN=zone-user OUT=zone-server SRC=10.149.240.10 DST=%s PROTO=TCP SPT=%s DPT=%s SYN\n' "$dest" "$sport" "$port"
        ;;
    *) exit 95 ;;
esac
STUB
chmod +x "$stub_dir/bash" "$stub_dir/docker"

run() {
    local layout=$1 scenario=$2 expected_status=$3
    status=0
    output=$(LAYOUT="$layout" SCENARIO="$scenario" "$real_bash" "$runner" "$layout" 2>&1) || status=$?
    if [[ $status != "$expected_status" ]]; then
        printf 'Expected exit %s, got %s (%s/%s)\n%s\n' "$expected_status" "$status" "$layout" "$scenario" "$output" >&2
        exit 1
    fi
}
run flat pass 0
grep -q '^S01-app PASS' <<<"$output"
grep -q '^L01 BASELINE' <<<"$output"
grep -q '^S04 NOT_RUN' <<<"$output"
run segmented pass 0
for id in S01-app S01-database S01-file S02 S03 L01; do
    grep -q "^$id PASS" <<<"$output"
done
run segmented unrelated 1
grep -q '^S02 FAIL' <<<"$output"
grep -q '^L01 FAIL' <<<"$output"
run segmented bypass 1
grep -q '^S02 FAIL' <<<"$output"
run flat unhealthy 2
[[ $output != *'S01-app '* ]]
run segmented logs-error 2
grep -q '^INCONCLUSIVE .*S02' <<<"$output"
run flat unreadable-source 2
grep -q '^INCONCLUSIVE .*fixture' <<<"$output"
run flat fixture-present 1
grep -q '^S04-FIXTURE FAIL' <<<"$output"
printf 'PASS: both layouts, log correlation and availability, unexpected access, readiness and fixture controls\n'
