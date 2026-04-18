#!/usr/bin/env bash

VAULT="@VAULT@"
USER_HOME="@USER_HOME@"

is_persistent() {
    local path="$1"
    if findmnt -n -T "$path" | grep -q "$VAULT"; then
        return 0
    fi
    return 1
}

cmd_find() {
    local search_paths=("/etc" "/var" "$USER_HOME")
    
    for base in "${search_paths[@]}"; do
        if [ ! -d "$base" ]; then continue; fi
        
        find "$base" -maxdepth 2 -not -path "*/.*" -not -type l | while read -r path; do
            [[ "$path" =~ ^/tmp|/proc|/sys|/dev|/run|/nix|/persistent ]] && continue
            [[ "$path" == "$base" ]] && continue
            
            if ! is_persistent "$path"; then
                echo "$path"
            fi
        done
    done
}

cmd_adopt() {
    local target="$1"
    if [ -z "$target" ]; then
        exit 1
    fi

    local abs_path=$(realpath "$target")
    
    if is_persistent "$abs_path"; then
        return
    fi

    local vault_path="$VAULT$abs_path"
    
    sudo mkdir -p "$(dirname "$vault_path")"
    sudo mv "$abs_path" "$vault_path"
    sudo mkdir -p "$abs_path"
    sudo mount --bind "$vault_path" "$abs_path"
}

cmd_delete() {
    local target="$1"
    if [ -z "$target" ]; then exit 1; fi
    sudo rm -rf "$target"
}

case "$1" in
    find)   cmd_find ;;
    adopt)  cmd_adopt "$2" ;;
    delete) cmd_delete "$2" ;;
    *)      exit 1 ;;
esac
