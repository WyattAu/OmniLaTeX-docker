#!/usr/bin/env bash
set -Eeuo pipefail

# Script to install TeXLive in a containerized environment

usage() {
    echo "Usage: $0 get_installer|install latest|version (YYYY)"
    exit 1
}

check_dependencies() {
    local deps=("perl" "wget")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo >&2 "Error: Required dependency '$dep' not found"
            exit 1
        fi
    done
}

validate_install() {
    if tex --version &>/dev/null; then
        echo "TeX installation verified successfully"
        return 0
    fi
    echo >&2 "TeX not found in PATH after installation"
    return 1
}

find_texlive_bin() {
    local depth=7
    find /usr/local -maxdepth "$depth" -type d \
        -regextype posix-extended -regex '.*/texlive/[0-9]{4}/bin/[^/]+' \
        -print -quit 2>/dev/null
}

setup_path() {
    local symlink_dir="/usr/local/bin"
    if [[ ":$PATH:" != *":${symlink_dir}:"* ]]; then
        echo >&2 "Error: Symlink target $symlink_dir not in PATH"
        return 1
    fi

    if [[ ${1:-} ]]; then
        # Create versioned symlinks
        echo "Creating version-specific symlinks in $symlink_dir"
        ln -sfv "${1}/"* "$symlink_dir" || true
    else
        echo >&2 "Error: No TeXLive bin directory provided for symlinking"
        return 1
    fi
}

case "${1:-}" in
    get_installer)
        [[ $# -ne 2 ]] && usage
        base_url="${2}/tlnet-final"
        file="install-tl-unx.tar.gz"
        
        echo "Fetching installer from $base_url/$file"
        wget -nv --tries=3 --show-progress "$base_url/$file"
        ;;
        
    install)
        [[ $# -ne 2 ]] && usage
        check_dependencies
        
        local profile=${TL_PROFILE:-}
        [[ -z "$profile" ]] && { echo >&2 "Error: TL_PROFILE not set"; exit 1; }
        
        echo "Starting TeXLive installation"
        [[ "$2" == "latest" ]] && repo="${TL_REPO:-https://mirror.ctan.org/systems/texlive/tlnet}" || repo="$2"
        
        perl install-tl --profile="$profile" --location "$repo"
        echo "Base installation completed"

        # Primary PATH check after installation
        validate_install && exit 0
        echo >&2 "PATH not updated automatically, attempting fallback methods"

        # Version-specific PATH setup
        local bin_dir
        if bin_dir=$(find_texlive_bin); then
            echo "Found TeXLive binaries at: $bin_dir"
            echo "Registering binaries with tlmgr"
            "$bin_dir/tlmgr" path add || true
            
            validate_install && exit 0
            setup_path "$bin_dir"
            validate_install && exit 0
        fi

        echo >&2 "All installation methods failed"
        exit 1
        ;;
        
    *)
        usage
        ;;
esac
