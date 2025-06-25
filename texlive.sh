#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "Error at line $LINENO. Exit code: $?" >&2' ERR

readonly TL_INSTALL_ARCHIVE="install-tl-unx.tar.gz"
readonly TEXLIVE_PREFIX="${TEXLIVE_PREFIX:-/usr/local/texlive}"
readonly TL_PROFILE="${TL_PROFILE:-texlive.profile}"
declare -a KNOWN_PREFIXES=(
    "${TEXLIVE_PREFIX}"
    "/opt/texlive"
    "${HOME}/texlive"
    "${HOME}/.texlive"
)

usage() {
    echo "Usage: $0 COMMAND VERSION"
    echo
    echo "Commands:"
    echo "  get_installer  Download TexLive installer"
    echo "  install        Install TexLive distribution"
    echo
    echo "Versions:"
    echo "  latest         Use current release"
    echo "  YYYY           Use historic release (e.g., 2023)"
    echo
    echo "Environment variables:"
    echo "  TL_PROFILE     Installation profile (default: texlive.profile)"
    echo "  TEXLIVE_PREFIX Installation root (default: /usr/local/texlive)"
}

die() {
    echo -e "\033[1;31mERROR:\033[0m $*" >&2
    exit 1
}

validate_version() {
    [[ "$1" =~ ^[0-9]{4}$ ]] && (( $1 >= 2008 && $1 <= $(date +%Y) )) && return 0
    [[ "$1" == "latest" ]] && return 0
    return 1
}

check_path() {
    if command -v tex >/dev/null 2>&1; then
        tex --version | head -n1
        echo "TeX installation verified. PATH configured correctly."
        return 0
    fi
    return 1
}

locate_bin_dir() {
    local version="$1"
    # Define possible locations in priority order
    local candidates=(
        "${TEXLIVE_PREFIX}/${version}/bin"/* 
        ${HOME}/texlive/${version}/bin/*
    )
    
    # Handle 'latest' version
    if [[ "$version" == "latest" ]]; then
        candidates+=($(compgen -G "${TEXLIVE_PREFIX}/2*/bin"/* | sort -Vr))
    fi

    for dir in "${candidates[@]}"; do
        if [[ -d "$dir" && -x "${dir}/tex" ]]; then
            realpath "$dir"
            return 0
        fi
    done

    # Fallback to system-wide search if not found
    echo "Searching system-wide (this may take time)..." >&2
    find "${KNOWN_PREFIXES[@]}" -maxdepth 4 \
        -type d -path '*/bin/*' -exec test -x '{}/tex' \; -print -quit 2>/dev/null
}

symlink_texlive_binaries() {
    local bin_dir="$1" symlink_dir="/usr/local/bin"
    [[ ":$PATH:" != *":${symlink_dir}:"* ]] && die "Target $symlink_dir not in PATH"
    
    echo "Creating symlinks from ${bin_dir} to ${symlink_dir}"
    ln --symbolic --verbose --target-directory="$symlink_dir" "$bin_dir"/*
}

# Input validation
[[ $# -ne 2 ]] && { usage; die "Incorrect arguments"; }

command="$1"
version_arg="$2"
validate_version "$version_arg" || die "Invalid version: $version_arg"

# Repository configuration
if [[ "$version_arg" == "latest" ]]; then
    repo_url="https://mirror.ctan.org/systems/texlive/tlnet"
else
    repo_url="https://tug.org/texlive/historic/${version_arg}/tlnet-final"
fi

case "$command" in
    get_installer)
        wget --show-progress --progress=bar:force "${repo_url}/${TL_INSTALL_ARCHIVE}"
        echo "Downloaded: ${TL_INSTALL_ARCHIVE}"
        ;;
        
    install)
        [[ $EUID -eq 0 ]] || die "Installation requires root privileges"
        [[ -f "$TL_PROFILE" ]] || die "Profile missing: $TL_PROFILE"
        [[ -f "install-tl" ]] || die "Missing installer script"
        
        perl install-tl --profile="$TL_PROFILE" --repository="$repo_url"
        
        if check_path; then
            exit 0
        fi
        
        bin_dir=$(locate_bin_dir "$version_arg")
        [[ ! -d "$bin_dir" ]] && die "Could not locate TeX binaries"
        echo "Found binaries: ${bin_dir}"
        
        echo "Attempting to configure PATH via tlmgr..."
        if "$bin_dir/tlmgr" path add; then
            if check_path; then exit 0; fi
        else
            echo "tlmgr path command failed, trying manual symlinks"
        fi
        
        symlink_texlive_binaries "$bin_dir"
        check_path || die "Failed to configure PATH. Manual intervention required."
        ;;
        
    *)  
        usage
        die "Invalid command: $command"
        ;;
esac
