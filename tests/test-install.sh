#!/bin/bash
# Test archive layout and fork routing without root, network or an installation.
set -eo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$repo/test-results"
test_root=$(mktemp -d "$repo/test-results/install.XXXXXX")
case $test_root in "$repo"/test-results/install.*) ;; *) exit 1 ;; esac
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/package/sing-box-main"
cp -r "$repo/install.sh" "$repo/sing-box.sh" "$repo/src" "$test_root/package/sing-box-main/"
tar czf "$test_root/archive.tar.gz" -C "$test_root/package" sing-box-main
is_core=sing-box
is_core_name=sing-box
is_sh_repo=fortheunknow3/sing-box
msg() { :; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
_wget() {
    local url= output= arg
    while (($#)); do
        arg=$1
        case $arg in
        https://*) url=$arg; shift ;;
        -O) output=$2; shift 2 ;;
        *) shift ;;
        esac
    done
    if [[ $url == https://raw.githubusercontent.com/fortheunknow3/sing-box/main/sing-box.sh ]]; then
        cat "$repo/sing-box.sh"
    else
        printf '%s\n' "$url" >"$test_root/download-url"
        cp "$test_root/archive.tar.gz" "$output"
    fi
}

# Load only function definitions; never execute the installer's host setup/main.
source <(sed -n '/^download() {/,/^}/p' "$repo/install.sh")
source <(sed -n '/^install_script_files() {/,/^}/p' "$repo/install.sh")
tmpsh=$test_root/download.part
is_sh_ok=$test_root/download.tar.gz
is_sh_dir=$test_root/installed
mkdir "$is_sh_dir"
download sh
[[ $(cat "$test_root/download-url") == https://github.com/fortheunknow3/sing-box/archive/refs/heads/main.tar.gz ]]
local_install=
install_script_files
cmp "$repo/src/hysteria2.sh" "$is_sh_dir/src/hysteria2.sh"
[[ ! -d $is_sh_dir/sing-box-main ]]
printf 'PASS install archive from fork main\n'

is_sh_dir=$test_root/local
mkdir "$is_sh_dir"
local_install=1
(cd "$test_root/package/sing-box-main"; install_script_files)
cmp "$repo/sing-box.sh" "$is_sh_dir/sing-box.sh"
printf 'PASS local install\n'

source "$repo/src/download.sh"
is_sh_dir=$test_root/updated
mkdir "$is_sh_dir"
is_sh_bin=$is_sh_dir/sing-box.sh
touch "$is_sh_dir/sb"
download sh
[[ $(cat "$test_root/download-url") == https://github.com/fortheunknow3/sing-box/archive/refs/heads/main.tar.gz ]]
cmp "$repo/src/hysteria2.sh" "$is_sh_dir/src/hysteria2.sh"
printf 'PASS default update from fork main\n'
unset is_sh_ref
download sh v1.21
[[ $(cat "$test_root/download-url") == https://github.com/fortheunknow3/sing-box/archive/refs/tags/v1.21.tar.gz ]]
printf 'PASS explicit version update from fork tag\n'

# A failed version request must not fall through to an empty download URL.
_wget() { return 1; }
(get_latest_version sh) >/dev/null 2>&1 && exit 1
printf 'PASS update failure handling\n'
