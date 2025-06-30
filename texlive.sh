#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "Error at line $LINENO. Exit code: ${?}" >&2' ERR

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
    [[ "$1" == "latest" ]] && return 0
    [[ "$1" =~ ^[0-9]{4}$ ]] && (( $1 >= 2008 && $1 <= $(date +%Y) )) && return 0
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
    
    # Always look in pre-built directories first to avoid slow find
    local -a base_prefixes=("${KNOWN_PREFIXES[@]}")
    shopt -s nullglob
    
    # Predefined patterns in priority order
    local patterns=(
        "${TEXLIVE_PREFIX}/${version}/bin"/* 
        ${HOME}/texlive/${version}/bin/*
    )
    
    # Extended search locations
    if [[ -z "$version" || "$version" == "latest" ]]; then
        # For 'latest', get sorted list of versions
        mapfile -t versions < <(find "${base_prefixes[@]}" -maxdepth 1 -type d -regex '.*/[0-9]{4}$' -printf "%f\n" 2>/dev/null | sort -Vr)
        for v in "${versions[@]}"; do
            patterns+=("${TEXLIVE_PREFIX}/${v}/bin"/*)
        done
    else  # Specific version
        for prefix in "${base_prefixes[@]}"; do
            patterns+=("${prefix}/${version}/bin"/*)
        done
    fi

    # Check predefined patterns first
    for dir in "${patterns[@]}"; do
        if [[ -d "$dir" && -x "${dir}/tex" ]]; then
            echo "$(realpath "$dir")"
            shopt -u nullglob
            return 0
        fi
    done

    # Fallback to system-wide search if needed
    echo "Searching system-wide (this may take time)..." >&2
    local pattern
    if [[ "$version" == "latest" ]]; then
        pattern='.*/texlive/[0-9]{4}/bin/.*'
    else
        pattern=".*/texlive/${version}/bin/.*"
    fi
    
    local found_path
    found_path=$(find / -type d -regextype egrep -regex "$pattern" -exec test -x '{}/tex' \; -print -quit 2>/dev/null)
    
    shopt -u nullglob
    [[ -d "$found_path" ]] && echo "$found_path" || return 1
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
version="$2"
validate_version "$version" || die "Invalid version: $version"

# Repository configuration - fixed historic URL format
if [[ "$version" == "latest" ]]; then
    repo_url="https://mirror.ctan.org/systems/texlive/tlnet"
else
    repo_url="ftp://tug.org/historic/systems/texlive/${version}/tlnet-final"
fi

case "$command" in
    get_installer)
        wget "${repo_url}/${TL_INSTALL_ARCHIVE}"
        ;;
        
    install)
        # Handle tarball extraction if needed
        if [[ -f "$TL_INSTALL_ARCHIVE" && ! -f "install-tl" ]]; then
            tar -xzf "$TL_INSTALL_ARCHIVE" --strip-components=1
        fi
        
        [[ -f "$TL_PROFILE" ]] || die "Profile missing: $TL_PROFILE"
        [[ -f "install-tl" ]] || die "Missing installer script"
        
        # Ensure single quotes around profile path to handle spaces
        perl install-tl --profile="$TL_PROFILE" --repository="$repo_url"
        
        if check_path; then
            exit 0
        fi
        
        bin_dir=$(locate_bin_dir "$version" 2>&1)
        [[ -z "$bin_dir" || ! -d "$bin_dir" ]] && die "Could not locate TeX binaries"
        echo "Found binaries: ${bin_dir}"
        
        echo "Attempting to configure PATH via tlmgr..."
        if "${bin_dir}/tlmgr" path add; then
            if check_path; then exit 0; fi
        else
            echo "tlmgr path command failed, trying manual symlinks"
        fi
        
        symlink_texlive_binaries "$bin_dir"
        check_path || die "TeX binaries detected at ${bin_dir}, but PATH not configured. Add to PATH or symlink manually."
        ;;
        
    *)  
        usage
        die "Invalid command: $command"
        ;;
esac
