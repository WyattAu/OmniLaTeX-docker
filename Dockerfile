# syntax=docker/dockerfile:1.4

ARG BASE_OS="debian"
ARG OS_VERSION="bookworm"
ARG TL_VERSION="latest"
ARG _BUILD_CONTEXT_PREFIX=""

#---------------------------------------------
# Base image with common dependencies
#---------------------------------------------
FROM ${BASE_OS}:${OS_VERSION} AS base

# Renew ARGs after FROM
ARG BASE_OS
ARG OS_VERSION

# Install system dependencies 
RUN apt-get update -qq && \
    apt-get install --yes --no-install-recommends \
    # Core system utilities
    ca-certificates \
    locales \
    wget \
    curl \
    perl \
    \
    # TeXLive dependencies
    libyaml-tiny-perl \
    libfile-homedir-perl \
    libunicode-linebreak-perl \
    liblog-log4perl-perl \
    liblog-dispatch-perl \
    \
    # Build tools
    make \
    git \
    gettext-base \
    \
    # Python ecosystem
    python3 \
    python3-pygments \
    \
    # Graphics and plotting
    inkscape \
    gnuplot-nox \
    ghostscript \
    poppler-utils \
    \
    # Document conversion
    librsvg2-bin \
    pandoc \
    cabextract \
    \
    # JRE for auxiliary tools
    default-jre && \
    rm -rf /var/lib/apt/lists/*

# Configure Python alternatives safely
RUN if ! command -v python >/dev/null 2>&1; then \
    update-alternatives --install /usr/bin/python python /usr/bin/python3 1; \
    fi

# Set system-wide locale and encoding
ENV LANG=C.utf8 LC_ALL=C.utf8

#---------------------------------------------
# Download stage - separate layer for better caching
#---------------------------------------------
FROM base AS downloads

# Renew ARGs
ARG TL_VERSION
ARG _BUILD_CONTEXT_PREFIX

ARG TL_INSTALL_ARCHIVE="install-tl-unx.tar.gz"
ARG EISVOGEL_ARCHIVE="Eisvogel.tar.gz"
ARG INSTALL_TL_DIR="install-tl"

WORKDIR /downloads

# Copy and prepare installation script
COPY --chmod=755 ./${_BUILD_CONTEXT_PREFIX}/texlive.sh .

RUN ./texlive.sh get_installer "${TL_VERSION}" && \
    # Verify installer download
    if [ ! -f "${TL_INSTALL_ARCHIVE}" ]; then \
    echo "Error: Failed to download TeXLive installer" >&2; \
    exit 1; \
    fi && \
    # Download Eisvogel template
    wget --progress=dot:giga \
    https://github.com/Wandmalfarbe/pandoc-latex-template/releases/latest/download/${EISVOGEL_ARCHIVE}


RUN \
    mkdir -p "${INSTALL_TL_DIR}" && \
    tar --extract --file="${TL_INSTALL_ARCHIVE}" --directory="${INSTALL_TL_DIR}" --strip-components 1 || { \
    echo "Error: Failed to extract TeXLive installer" >&2; \
    exit 1; \
    } && \
    tar --extract --file="${EISVOGEL_ARCHIVE}" --strip-components=1 || { \
    echo "Error: Failed to extract Eisvogel template" >&2; \
    exit 1; \
    }

#---------------------------------------------
# Main build stage
#---------------------------------------------
FROM base AS main

# Renew ARGs
ARG TL_VERSION
ARG _BUILD_CONTEXT_PREFIX
ARG USER="tex"
ARG TL_PROFILE="texlive.profile"
ARG TMP_TL_PROFILE="${TL_PROFILE}.tmp"
ARG INSTALL_DIR="/install"

# Create unprivileged user 
RUN useradd --create-home --shell /bin/bash ${USER}

# Add metadata labels (OCI-compliant)
LABEL maintainer="Wyatt Au <wyatt_au@protonmail.com>" \
    org.opencontainers.image.title="OmniLatex-docker" \
    org.opencontainers.image.description="OmniLaTeX required tooling" \
    org.opencontainers.image.url="ghcr.io/wyattau/omnilatex-docker:latest" \
    org.opencontainers.image.source="https://github.com/WyattAu/OmniLaTeX-docker.git" \
    org.opencontainers.image.version="${TL_VERSION}" 
#org.opencontainers.image.created="${BUILD_DATE}" 

WORKDIR ${INSTALL_DIR}

# Copy installation artifacts
COPY --from=downloads /downloads/install-tl/ /downloads/texlive.sh ./
COPY --from=downloads /downloads/eisvogel.latex /home/${USER}/.pandoc/templates/

# Copy configuration files
COPY ${_BUILD_CONTEXT_PREFIX}/config/${TL_PROFILE} ${TMP_TL_PROFILE}
COPY ${_BUILD_CONTEXT_PREFIX}/config/.wgetrc /etc/wgetrc

# Process configuration template
RUN cat "${TMP_TL_PROFILE}" | envsubst | tee "${TL_PROFILE}" && \
    rm "${TMP_TL_PROFILE}"

# Install TeXLive (large layer)
RUN ./texlive.sh install "${TL_VERSION}"

# Post-installation setup
WORKDIR /home/${USER}

# Install custom class file
RUN mkdir -p texmf/tex/latex/ && \
    wget --quiet -P texmf/tex/latex/ \
    https://collaborating.tuhh.de/m21/public/theses/itt-latex-template/-/raw/master/acp.cls

# Update font cache as user
USER ${USER}
RUN luaotfload-tool --update --quiet || echo "Font cache update skipped"

# Final permissions and cleanup
USER root
RUN chown --recursive ${USER}:${USER} /home/${USER} && \
    find /home/${USER} -type d -exec chmod 755 {} \; && \
    find /home/${USER} -type f -exec chmod 644 {} \;

# Default container configuration
USER ${USER}
WORKDIR /workspace

ENTRYPOINT ["latexmk"]
CMD ["--lualatex"]
