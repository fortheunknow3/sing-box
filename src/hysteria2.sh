#!/bin/bash

# HY2 settings live in the inbound itself, so changing ports/passwords and fix
# can reuse them without a second state file. All user strings go through jq.
hy2_read_options() {
    hy2_options=$(jq -c '.inbounds[0] | {obfs, initial_packet_size,
        disable_path_mtu_discovery} | with_entries(select(.value != null))' <<<"$is_json_str") || return 1
    password=$(jq -r '.inbounds[0].users[0].password' <<<"$is_json_str")
}

hy2_set_obfs() {
    local kind=${1,,} secret=$2 old_kind
    old_kind=$(jq -r '.obfs.type // "off"' <<<"${hy2_options:-"{}"}")
    case $kind in
    off | none)
        [[ $secret ]] && { err "关闭混淆时不能指定混淆密码."; return 1; }
        hy2_options=$(jq -c 'del(.obfs)' <<<"${hy2_options:-"{}"}")
        ;;
    salamander | gecko)
        if [[ ! $secret && $old_kind == "$kind" ]]; then
            secret=$(jq -r '.obfs.password // empty' <<<"${hy2_options:-"{}"}")
        fi
        if [[ ! $secret || $secret == auto ]]; then
            secret=$("$is_core_bin" generate rand 32 --base64) || return 1
        fi
        [[ $secret ]] || { err "混淆密码不能为空."; return 1; }
        hy2_options=$(jq -c --arg kind "$kind" --arg secret "$secret" \
            '.obfs = {type: $kind, password: $secret}' <<<"${hy2_options:-"{}"}")
        ;;
    *) err "混淆类型可选: off、salamander、gecko."; return 1 ;;
    esac
}

hy2_set_packet_size() {
    case ${1,,} in
    auto | 0)
        hy2_options=$(jq -c 'del(.initial_packet_size)' <<<"${hy2_options:-"{}"}")
        ;;
    *)
        # Bound QUIC size; obfuscation and IP/UDP headers add more overhead.
        [[ $1 =~ ^[1-9][0-9]{3}$ && $1 -ge 1200 && $1 -le 1452 ]] || {
            err "初始 QUIC 报文大小可选: auto 或 1200-1452 字节."; return 1
        }
        hy2_options=$(jq -c --argjson size "$1" '.initial_packet_size = $size' <<<"${hy2_options:-"{}"}")
        ;;
    esac
}

hy2_set_mtu_discovery() {
    case ${1,,} in
    auto)
        hy2_options=$(jq -c 'del(.disable_path_mtu_discovery)' <<<"${hy2_options:-"{}"}")
        ;;
    on | true | 1)
        hy2_options=$(jq -c '.disable_path_mtu_discovery = false' <<<"${hy2_options:-"{}"}")
        ;;
    off | false | 0)
        hy2_options=$(jq -c '.disable_path_mtu_discovery = true' <<<"${hy2_options:-"{}"}")
        ;;
    *) err "MTU 探测可选: on、off、auto."; return 1 ;;
    esac
}

hy2_require_supported() {
    local version=${is_core_ver#v} major minor
    IFS=. read -r major minor _ <<<"$version"
    if jq -e 'has("initial_packet_size") or has("disable_path_mtu_discovery") or .obfs.type == "gecko"' \
        <<<"${hy2_options:-"{}"}" >/dev/null; then
        if [[ ! $major =~ ^[0-9]+$ || ! $minor =~ ^[0-9]+$ ]] ||
            (( major < 1 || (major == 1 && minor < 14) )); then
            err "初始报文大小、MTU 探测开关及 Gecko 需要 sing-box >= 1.14.0，请先执行: $is_core update core"
            return 1
        fi
    fi
}

# Preserve positional [port] [password], allow named options in any order.
hy2_parse_args() {
    hy2_args=()
    local kind secret kind_set= secret_set= option value
    while (($#)); do
        case $1 in
        --obfs | --obfs-password | --initial-packet-size | --mtu-discovery | --disable-path-mtu-discovery)
            option=$1
            [[ $# -ge 2 && $2 && $2 != --* ]] || { err "$option 缺少参数."; return 1; }
            value=$2
            case $option in
            --obfs) kind=$value; kind_set=1 ;;
            --obfs-password) secret=$value; secret_set=1 ;;
            --initial-packet-size) hy2_set_packet_size "$value" || return 1 ;;
            --mtu-discovery) hy2_set_mtu_discovery "$value" || return 1 ;;
            --disable-path-mtu-discovery)
                case ${value,,} in
                true | 1) hy2_set_mtu_discovery off ;;
                false | 0) hy2_set_mtu_discovery on ;;
                auto) hy2_set_mtu_discovery auto ;;
                *) err "$option 可选: true、false、auto."; return 1 ;;
                esac
                ;;
            esac
            shift 2
            ;;
        --) shift; hy2_args+=("$@"); break ;;
        --*) err "无法识别 HY2 参数: $1"; return 1 ;;
        *) hy2_args+=("$1"); shift ;;
        esac
    done
    ((${#hy2_args[@]} <= 2)) || { err "HY2 位置参数仅支持 [port] [password]."; return 1; }
    if [[ $kind_set || $secret_set ]]; then
        [[ $kind_set ]] || kind=$(jq -r '.obfs.type // "off"' <<<"${hy2_options:-"{}"}")
        hy2_set_obfs "$kind" "$secret" || return 1
    fi
    hy2_require_supported
}

hy2_prompt_obfs() {
    local kind secret
    printf '混淆类型 [off/salamander/gecko] (默认 off): '
    read -r kind || return 1
    kind=${kind:-off}
    if [[ $kind == salamander || $kind == gecko ]]; then
        printf '混淆密码 (回车随机生成): '
        read -rs secret || return 1
        printf '\n'
    fi
    hy2_set_obfs "$kind" "$secret"
}

hy2_prompt_packet_size() {
    local size
    printf '初始 QUIC 报文大小 [auto/1200-1452] (默认 auto): '
    read -r size || return 1
    hy2_set_packet_size "${size:-auto}"
}

hy2_prompt_mtu_discovery() {
    local discovery
    printf '路径 MTU 探测 [on/off/auto] (默认 auto): '
    read -r discovery || return 1
    hy2_set_mtu_discovery "${discovery:-auto}"
}

hy2_show_options() {
    local kind secret size discovery
    kind=$(jq -r '.obfs.type // "off"' <<<"${hy2_options:-"{}"}")
    secret=$(jq -r '.obfs.password // empty' <<<"${hy2_options:-"{}"}")
    size=$(jq -r '.initial_packet_size // "auto"' <<<"${hy2_options:-"{}"}")
    discovery=$(jq -r 'if has("disable_path_mtu_discovery") then
        (if .disable_path_mtu_discovery then "off" else "on" end) else "auto" end' <<<"${hy2_options:-"{}"}")
    printf '混淆 (obfs): %s\n' "$kind"
    [[ $kind != off ]] && printf '混淆密码 (obfs-password): %s\n' "$secret"
    printf '初始 QUIC 报文大小 (initial_packet_size): %s\n路径 MTU 探测: %s\n' "$size" "$discovery"
    printf '报文大小和 MTU 探测是服务端设置，不通过分享链接下发给客户端.\n'
}
