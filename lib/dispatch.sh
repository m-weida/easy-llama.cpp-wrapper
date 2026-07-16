# shellcheck shell=bash
# Top-level command dispatch.

main() {
  local cmd="${1:-help}"

  case "$cmd" in
    list)
      shift
      cmd_list "$@"
      ;;
    start)
      shift
      cmd_start "$@"
      ;;
    remove)
      shift
      cmd_remove "$@"
      ;;
    hf)
      shift
      cmd_hf "$@"
      ;;
    fit-params)
      shift
      cmd_fit_params "$@"
      ;;
    check-updates)
      shift
      cmd_check_updates "$@"
      ;;
    update)
      shift
      cmd_update "$@"
      ;;
    install)
      shift
      cmd_install "$@"
      ;;
    uninstall)
      shift
      cmd_uninstall "$@"
      ;;
    help|-h|--help)
      print_help
      ;;
    *)
      usage_error "unknown command: $cmd"
      ;;
  esac
}
