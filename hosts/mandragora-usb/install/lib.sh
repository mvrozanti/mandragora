#!/usr/bin/env bash
# shellcheck shell=bash

log_info()  { printf '[info] %s\n' "$*" >&2; }
log_warn()  { printf '[warn] %s\n' "$*" >&2; }
log_error() { printf '[error] %s\n' "$*" >&2; }
die()       { log_error "$*"; exit 1; }

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        die "this command must run as root"
    fi
}

validate_token() {
    local label="$1" value="$2"
    [[ "$value" =~ ^[a-zA-Z0-9_-]{1,63}$ ]] \
        || die "invalid $label: '$value' (must match ^[a-zA-Z0-9_-]{1,63}\$)"
}

confirm_typed() {
    local expected="$1"
    local prompt="$2"
    local got
    log_info "$prompt"
    log_info "Type ${expected} to continue:"
    read -r got
    [[ "$got" == "$expected" ]] || { log_error "got '$got', expected '$expected' — aborting."; return 1; }
}
