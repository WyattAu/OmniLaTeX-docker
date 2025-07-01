# ==================== Global Build Arguments ====================
ARG BASE_OS="debian"
ARG OS_VERSION="bookworm"
ARG TL_VERSION="latest"
ARG _BUILD_CONTEXT_PREFIX=""

# ==================== Base Image Stage ====================
FROM ${BASE_OS}:${OS_VERSION} AS base

# Set default locale and encoding
ENV DEBIAN_FRONTEND=noninteractive 

# Install system dependencies
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    # Core utilities
    ca-certificates \
    curl \
    git \
    gettext-base \
    locales \
    make \
    perl \
    wget \
    \
    # LaTeX tools dependencies
    python3 \
    python3-pygments \
    libyaml-tiny-perl \
    libfile-homedir-perl \
    libunicode-linebreak-perl \
    liblog-log4perl-perl \
    liblog-dispatch-perl \
    \
    # Graphical tools
    default-jre \
    ghostscript \
    gnuplot-nox \
    inkscape \
    poppler-utils \
    \
    # Pandoc and related
    cabextract \
    librsvg2-bin \
    pandoc \
    && \
    rm -f /usr/lib/locale/locale-archive && \
    # Configure locales
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    echo "en_US ISO-8859-1" >> /etc/locale.gen && \
    # Generate locales
    locale-gen en_US.UTF-8 && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=${LANG} && \
    # Set Python3 as default
    update-alternatives --install /usr/bin/python python /usr/bin/python3 1 && \
    # Cleanup
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8


# ==================== Downloads Stage ====================
FROM base AS downloads

ARG TL_VERSION
ARG _BUILD_CONTEXT_PREFIX
ARG TL_INSTALL_ARCHIVE="install-tl-unx.tar.gz"
ARG EISVOGEL_ARCHIVE="Eisvogel.tar.gz"
ARG INSTALL_TL_DIR="install-tl"

# Copy and prepare installation scripts
COPY ./${_BUILD_CONTEXT_PREFIX}/texlive.sh .
RUN chmod +x texlive.sh && \
    ./texlive.sh get_installer ${TL_VERSION} && \
    wget -q https://github.com/Wandmalfarbe/pandoc-latex-template/releases/latest/download/${EISVOGEL_ARCHIVE}

# Extract archives
RUN mkdir ${INSTALL_TL_DIR} && \
    tar -xf ${TL_INSTALL_ARCHIVE} -C ${INSTALL_TL_DIR} --strip-components 1 && \
    tar -xf ${EISVOGEL_ARCHIVE} --strip-components=1

# ==================== Final Image Stage ====================
FROM base AS main

ARG TL_VERSION
ARG _BUILD_CONTEXT_PREFIX
ARG USER="tex"
ARG TL_PROFILE="texlive.profile"
ARG INSTALL_DIR="/install"

# Create non-root user
RUN useradd --create-home ${USER}

# Configure image metadata
LABEL maintainer="Wyatt Au <wyatt_au@protonmail.com>" \
      org.label-schema.description="OmniLaTeX required tooling" \
      org.label-schema.vcs-url="https://github.com/WyattAu/OmniLaTeX-docker" \
      org.label-schema.schema-version="0.0.1"


WORKDIR ${INSTALL_DIR}

# Copy installation files
COPY ${_BUILD_CONTEXT_PREFIX}/config/${TL_PROFILE} .
COPY --from=downloads /install-tl/ /texlive.sh ./
COPY --from=downloads /eisvogel.latex /home/${USER}/.pandoc/templates/
COPY ${_BUILD_CONTEXT_PREFIX}/config/.wgetrc /etc/wgetrc

# Install TeXLive
RUN ./texlive.sh install "${TL_VERSION}" 

# Set ownership and switch to user

WORKDIR /workdir
USER ${USER}

# Update font cache
RUN luaotfload-tool --update || true 

USER root
RUN chown -R ${USER}:${USER} /home/${USER}

    # Cleanup installation
RUN rm -rf ${INSTALL_DIR} && \
    # Install LaTeX template
    mkdir -p /home/${USER}/texmf/tex/latex/ && \
    wget -q -P /home/${USER}/texmf/tex/latex/ \
      https://collaborating.tuhh.de/m21/public/theses/itt-latex-template/-/raw/master/acp.cls && \
    # Final cleanup
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/*

USER ${USER}

# Configure entrypoint
ENTRYPOINT [ "latexmk" ]
CMD [ "--lualatex" ]
