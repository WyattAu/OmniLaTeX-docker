#!/usr/bin/env bash

# Maintains original arguments: $1 = get_installer|install, $2 = latest|version

set -euo pipefail
shopt -s nullglob

### Constants
readonly HISTORIC_BASE="ftp://tug.org/historic/systems/texlive"
readonly CTAN_MIRROR="https://mirror.ctan.org/systems/texlive/tlnet"
readonly DEFAULT_MIRROR="https://ftp.rrzn.uni-hannover.de/pub/mirror/tex-archive/systems/texlive/tlnet/"
readonly TEXLIVE_ROOT="/usr/local/texlive"
readonly SYMLINK_DIR="/usr/local/bin"

### Functions
die() {
  echo "ERROR: $*" >&2
  exit 1
}

log_info() {
  echo "INFO: $*"
}

log_warn() {
  echo "WARNING: $*" >&2
}

validate_input() {
  if [[ $# -ne 2 ]]; then
    log_warn "Invalid arguments: $*"
    usage
    exit 64  # EX_USAGE
  fi

  [[ "$1" =~ ^(get_installer|install)$ ]] || {
    log_warn "Invalid action: $1"
    usage
    exit 64
  }

  [[ "$2" == "latest" ]] || [[ "$2" =~ ^[0-9]{4}$ ]] || die "Invalid version format: $2 (expected 'latest' or YYYY)"
}

usage() {
  echo "Usage: ${0##*/} get_installer|install latest|version (YYYY)"
}

check_installation() {
  if command -v tex &>/dev/null; then
    log_info "TeX installation verified: $(tex --version | head -n1)"
    return 0
  fi
  log_warn "TeX installation not found in PATH"
  return 1
}

fetch_installer() {
  local src_url
  if [[ "$1" == "latest" ]]; then
    src_url="${CTAN_MIRROR}/${TL_INSTALL_ARCHIVE}"
  else
    src_url="${HISTORIC_BASE}/${1}/tlnet-final/${TL_INSTALL_ARCHIVE}"
  fi

  log_info "Downloading installer from: ${src_url}"
  wget --progress=dot:giga "${src_url}" || die "Installer download failed"
}

run_install() {
  local install_opts=(
    "--profile=${TL_PROFILE}"
    "--logfile=install-tl.log"
    "--no-interaction"
  )

  log_info "Starting TeX Live installation (this may take several minutes)"
  log_info "Version: $1"

  if [[ "$1" == "latest" ]]; then
    install_opts+=( "--location=${DEFAULT_MIRROR}" )
  else
    install_opts+=(
      "--location=${DEFAULT_MIRROR}"
      "--repository=${HISTORIC_BASE}/${1}/tlnet-final"
    )
  fi

  # Run installer
  perl install-tl "${install_opts[@]}" || die "Installation failed - see install-tl.log"
  log_info "Base installation completed"

  # Verify installation and automatically adjust PATH
  check_installation && return 0

  # Attempt to locate bin directory
  local bin_dirs=("${TEXLIVE_ROOT}/"20[0-9][0-9]/bin/*/)
  if [[ ${#bin_dirs[@]} -eq 0 ]]; then
    die "No TeXLive binary directories found under ${TEXLIVE_ROOT}"
  fi

  local bin_dir="${bin_dirs[-1]}"  # Use most recent installation
  log_info "Found TeXLive binaries: ${bin_dir}"

  # Attempt to configure PATH via tlmgr
  log_info "Registering binaries with system PATH"
  if "${bin_dir}/tlmgr" path add; then
    log_info "PATH registration via tlmgr successful"
  else
    log_warn "tlmgr path command failed - using manual symlinks"
    create_symlinks "${bin_dir}"
  fi

  # Final verification
  check_installation || die "TeX installation incomplete. PATH=$PATH"
}

create_symlinks() {
  local bin_dir="$1"
  [[ -d "${SYMLINK_DIR}" ]] || mkdir -p "${SYMLINK_DIR}"
  
  log_info "Creating symlinks in ${SYMLINK_DIR}"
  for binary in "${bin_dir}"/*; do
    local target="${SYMLINK_DIR}/$(basename "${binary}")"
    [[ -e "${target}" ]] && continue
    ln -sf "${binary}" "${target}" || log_warn "Failed to create symlink: ${binary}"
  done
}

### Main ###
validate_input "$@"
readonly ACTION="$1"
readonly VERSION="$2"

case "${ACTION}" in
  get_installer)
    fetch_installer "${VERSION}"
    ;;
    
  install)
    run_install "${VERSION}"
    log_info "TeX Live installation completed successfully"
    ;;
    
  *)
    usage
    exit 64
    ;;
esac
