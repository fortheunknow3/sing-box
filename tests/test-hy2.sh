#!/bin/bash
# Non-root regression tests. Never source the installed /etc/sing-box script.
set -o pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
: "${SING_BOX_BIN:?Set SING_BOX_BIN to a sing-box >= 1.14.0 executable}"
if command -v cygpath >/dev/null; then
    # Windows jq emits CRLF unless binary mode is requested.
    jq() { command jq -b "$@"; }
fi
mkdir -p "$repo/test-results"
test_root=$(mktemp -d "$repo/test-results/hy2.XXXXXX") || exit 1
case $test_root in "$repo"/test-results/hy2.*) ;; *) exit 1 ;; esac
trap 'rm -rf "$test_root"' EXIT
umask 077
load() { source "$repo/src/$1"; }
source "$repo/src/core.sh"
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
msg() { :; }
_green() { :; }
_yellow() { :; }
_red() { :; }
msg_ul() { printf '%s' "$*"; }
get_uuid() { tmp_uuid=01234567-89ab-4cde-8fab-0123456789ab; }
get_ip() { :; }
is_port_used() { :; }
manage() { :; }
footer_msg() { :; }

fixture() {
    is_core=sing-box
    is_core_name=sing-box
    is_core_bin=$SING_BOX_BIN
    is_core_ver=${TEST_CORE_VERSION:-1.14.4}
    is_core_dir=$test_root/$1
    # Native Windows cores need native paths inside JSON, not MSYS /tmp paths.
    if command -v cygpath >/dev/null; then is_core_dir=$(cygpath -m "$is_core_dir"); fi
    is_conf_dir=$is_core_dir/conf
    is_caddy_dir=$is_core_dir/caddy
    is_caddy_conf=$is_caddy_dir/233boy
    is_sh_repo=fortheunknow3/sing-box
    ip=192.0.2.1
    mkdir -p "$is_conf_dir" "$is_core_dir/bin"
}
assert_json() {
    jq -e "$2" "$1" >/dev/null || { printf 'FAIL JSON: %s\n' "$2" >&2; exit 1; }
}
check_config() { "$is_core_bin" check -c "$1" || exit 1; }
node() { printf '%s/Hysteria2-%s.json' "$is_conf_dir" "$1"; }
test_legacy() {
    fixture legacy
    main add hy2 22213 legacy-password || exit 1
    assert_json "$(node 22213)" '.inbounds[0] | .users[0].password == "legacy-password" and (has("obfs") | not) and (has("initial_packet_size") | not) and (has("disable_path_mtu_discovery") | not)'
    check_config "$(node 22213)"
}
test_options_and_uri() {
    fixture options
    local auth='auth @:#?&"\ // password' secret='obfs @:#?&"\ // 密码'
    main add hy2 --obfs-password "$secret" 22213 "$auth" --obfs salamander --initial-packet-size 1200 --mtu-discovery off || exit 1
    jq -e --arg auth "$auth" --arg secret "$secret" '.inbounds[0] | .users[0].password == $auth and .obfs.password == $secret and .obfs.type == "salamander" and .initial_packet_size == 1200 and .disable_path_mtu_discovery == true' "$(node 22213)" >/dev/null || exit 1
    [[ $is_url == *"$(jq -rn --arg value "$auth" '$value|@uri')@"* ]] || exit 1
    [[ $is_url == *"&obfs=salamander&obfs-password=$(jq -rn --arg value "$secret" '$value|@uri')#"* ]] || exit 1
    check_config "$(node 22213)"
}
test_changes_and_fix() {
    fixture preserve
    main add hy2 22213 first --obfs salamander --obfs-password 'keep // " me' --initial-packet-size 1200 --mtu-discovery off || exit 1
    local before
    before=$(jq -c '.inbounds[0] | {obfs,initial_packet_size,disable_path_mtu_discovery}' "$(node 22213)")
    # Each invocation gets clean shell state, as the installed command does.
    invoke port 22213 22214 || exit 1
    [[ ! -f $(node 22213) ]] || exit 1
    invoke passwd 22214 'new @ password' || exit 1
    invoke fix 22214 || exit 1
    [[ $before == "$(jq -c '.inbounds[0] | {obfs,initial_packet_size,disable_path_mtu_discovery}' "$(node 22214)")" ]] || exit 1
    assert_json "$(node 22214)" '.inbounds[0].users[0].password == "new @ password"'
    invoke full 22214 22215 another --initial-packet-size 1250 || exit 1
    assert_json "$(node 22215)" '.inbounds[0] | .initial_packet_size == 1250 and .disable_path_mtu_discovery == true and .obfs.password == "keep // \" me"'
    check_config "$(node 22215)"
}
invoke() (
    # Keep only the installation paths; reset state from previous commands.
    source "$repo/tests/invoke.sh"
)
test_change_commands() {
    fixture changes
    main add hy2 22213 first || exit 1
    invoke change 22213 obfs salamander 'different & secret' || exit 1
    invoke packet-size 22213 1200 || exit 1
    invoke mtu-discovery 22213 off || exit 1
    assert_json "$(node 22213)" '.inbounds[0] | .obfs.password == "different & secret" and .initial_packet_size == 1200 and .disable_path_mtu_discovery == true'
    invoke mtu-discovery 22213 on || exit 1
    assert_json "$(node 22213)" '.inbounds[0].disable_path_mtu_discovery == false'
    invoke obfs 22213 off || exit 1
    invoke packet-size 22213 auto || exit 1
    invoke mtu-discovery 22213 auto || exit 1
    assert_json "$(node 22213)" '.inbounds[0] | (has("obfs")|not) and (has("initial_packet_size")|not) and (has("disable_path_mtu_discovery")|not)'
}
test_generated_password_and_gecko() {
    fixture random
    main add hy2 22213 auth --obfs salamander || exit 1
    assert_json "$(node 22213)" '.inbounds[0].obfs.password | length >= 32'
    invoke obfs 22213 gecko auto || exit 1
    assert_json "$(node 22213)" '.inbounds[0].obfs.type == "gecko"'
    check_config "$(node 22213)"
}
test_gen() {
    fixture gen
    main gen hy2 22213 auth --initial-packet-size 1200 --disable-path-mtu-discovery true || exit 1
    [[ ! -f $(node 22213) ]] || exit 1
    jq -e '.inbounds[0] | .initial_packet_size == 1200 and .disable_path_mtu_discovery == true' <<<"$is_new_json" >/dev/null || exit 1
    printf '%s\n' "$is_new_json" >"$is_core_dir/generated.json"
    check_config "$is_core_dir/generated.json"
}
test_version_gate() {
    fixture old
    is_core_ver=1.13.12
    (main add hy2 22213 auth --initial-packet-size 1200) >/dev/null 2>&1 && exit 1
    (main add hy2 22213 auth --mtu-discovery on) >/dev/null 2>&1 && exit 1
    (main add hy2 22213 auth --obfs gecko) >/dev/null 2>&1 && exit 1
    main add hy2 22213 auth --obfs salamander --obfs-password legacy || exit 1
    [[ -f $(node 22213) ]] || exit 1
}
test_invalid_no_overwrite() {
    fixture invalid
    main add hy2 22213 auth --obfs salamander --obfs-password stable || exit 1
    local before
    before=$(cat "$(node 22213)")
    for size in 1199 1453 -1 1.5 01200 999999999999999999999; do
        (invoke packet-size 22213 "$size") >/dev/null 2>&1 && exit 1
    done
    (invoke mtu-discovery 22213 invalid) >/dev/null 2>&1 && exit 1
    (invoke obfs 22213 invalid) >/dev/null 2>&1 && exit 1
    (main gen hy2 22214 auth --initial-packet-size) >/dev/null 2>&1 && exit 1
    (main gen hy2 22214 auth --unknown-flag value) >/dev/null 2>&1 && exit 1
    (main gen hy2 22214 auth --obfs off --obfs-password secret) >/dev/null 2>&1 && exit 1
    [[ $before == "$(cat "$(node 22213)")" ]] || exit 1
}
test_core_check_failure() {
    fixture failure
    main add hy2 22213 auth --initial-packet-size 1200 || exit 1
    local before
    before=$(cat "$(node 22213)")
    # A core rejecting a candidate must leave the old file intact.
    (source "$repo/tests/invoke.sh" packet-size 22213 1250 --reject-core) >/dev/null 2>&1 && exit 1
    [[ $before == "$(cat "$(node 22213)")" ]] || exit 1
    [[ ! $(find "$is_conf_dir" -name '.hy2.*') ]] || exit 1
}
test_interactive() {
    fixture interactive
    is_main_start=1
    # Existing menu handles the port; HY2 prompts add these three answers.
    main add hy2 22213 auth <<<'salamander
interactive-secret
1200
off' || exit 1
    assert_json "$(node 22213)" '.inbounds[0] | .obfs.password == "interactive-secret" and .initial_packet_size == 1200 and .disable_path_mtu_discovery == true'
    invoke change 22213 <<<'6
on' || exit 1
    assert_json "$(node 22213)" '.inbounds[0].disable_path_mtu_discovery == false'
}
test_fix_all_and_other_protocols() {
    fixture multiple
    main add hy2 22213 first --obfs salamander --obfs-password one --initial-packet-size 1200 --mtu-discovery off || exit 1
    # Add another node in a clean invocation, then exercise the batch fix path.
    invoke add hy2 22214 second || exit 1
    invoke fix-all || exit 1
    assert_json "$(node 22213)" '.inbounds[0].obfs.password == "one" and .inbounds[0].initial_packet_size == 1200'
    assert_json "$(node 22214)" '.inbounds[0] | (has("obfs")|not) and (has("initial_packet_size")|not)'
    invoke add trojan 22215 trojan-password || exit 1
    assert_json "$is_conf_dir/Trojan-22215.json" '.inbounds[0] | .type == "trojan" and (has("obfs")|not)'
    (invoke packet-size 22215 1200) >/dev/null 2>&1 && exit 1
    check_config "$is_conf_dir/Trojan-22215.json"
}

failures=0
for name in legacy options_and_uri changes_and_fix change_commands generated_password_and_gecko gen version_gate invalid_no_overwrite core_check_failure interactive fix_all_and_other_protocols; do
    if ("test_$name"); then printf 'PASS %s\n' "$name"
    else printf 'FAIL %s\n' "$name"; ((failures++)); fi
done
((failures == 0))
