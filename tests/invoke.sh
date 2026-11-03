# Test helper: retain fixture paths and functions, remove per-command state.
# Sourced only inside a subshell by test-hy2.sh.
for var in $(compgen -v); do
    case $var in
    is_core | is_core_name | is_core_bin | is_core_ver | is_core_dir | is_conf_dir | is_caddy_dir | is_caddy_conf | is_sh_repo) ;;
    is_* | hy2_* | password | uuid | port | net | net_type | host | path | ss_* | username | door_* | json_str | tmp_* | old_host) unset "$var" ;;
    esac
done
if [[ ${*: -1} == --reject-core ]]; then
    reject_core() { return 1; }
    is_core_bin=reject_core
    set -- "${@:1:$#-1}"
fi
main "$@"
