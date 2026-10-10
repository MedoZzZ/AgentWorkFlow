#!/usr/bin/env bash
# Invoke with bash; no Windows paths, eval, or shell-joined arguments.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
command -v pwsh >/dev/null || { printf '%s\n' 'PowerShell 7.2+ (pwsh) is required.' >&2; exit 127; }
case "${1:-}" in
  drive|resume)
    action="$1"; shift
    [[ $# -ge 1 ]] || { printf '%s\n' 'Usage: bash workflow/scripts/workflow.sh drive|resume PLAN_FILE [controller arguments]' >&2; exit 2; }
    plan_file="$1"; shift
    exec pwsh -NoProfile -File "$script_dir/Invoke-Workflow.ps1" -ProjectRoot "$PWD" -PlanFile "$plan_file" -Action "$action" "$@"
    ;;
  dashboard)
    shift
    exec pwsh -NoProfile -File "$script_dir/Start-Dashboard.ps1" -ProjectRoot "$PWD" "$@"
    ;;
  preflight)
    shift
    exec pwsh -NoProfile -File "$script_dir/Preflight.ps1" -ProjectRoot "$PWD" "$@"
    ;;
  *) printf '%s\n' 'Usage: bash workflow/scripts/workflow.sh drive|resume PLAN_FILE | dashboard | preflight' >&2; exit 2 ;;
esac
