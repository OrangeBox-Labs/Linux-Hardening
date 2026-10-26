#!/usr/bin/env bash
# Shared service checks/actions for systemd and legacy SysV init.
# Return codes: 0=yes/success, 1=no/not active, 2=state/action cannot be determined.

ob_service_is_enabled_sysv() {
  local svc="$1" output
  command -v chkconfig >/dev/null 2>&1 || return 2
  output="$(chkconfig --list "$svc" 2>/dev/null)" || return 1
  printf '%s\n' "$output" | grep -Eq '(^|[[:space:]])(3|4|5):on([[:space:]]|$)'
}

ob_service_is_active_sysv() {
  local svc="$1"
  command -v service >/dev/null 2>&1 || return 2
  if service "$svc" status >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

ob_service_is_enabled() {
  local svc="$1"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-enabled "$svc" >/dev/null 2>&1
    return $?
  fi
  ob_service_is_enabled_sysv "$svc"
}

ob_service_is_active() {
  local svc="$1"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active "$svc" >/dev/null 2>&1
    return $?
  fi
  ob_service_is_active_sysv "$svc"
}

ob_service_enable() {
  local svc="$1"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable "$svc"
    return $?
  fi
  command -v chkconfig >/dev/null 2>&1 || return 2
  chkconfig "$svc" on
}

ob_service_start() {
  local svc="$1"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl start "$svc"
    return $?
  fi
  command -v service >/dev/null 2>&1 || return 2
  service "$svc" start
}

ob_service_restart() {
  local svc="$1"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart "$svc"
    return $?
  fi
  command -v service >/dev/null 2>&1 || return 2
  service "$svc" restart
}
