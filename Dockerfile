# Set global arguments
ARG BASE_OS="bitnami/minideb"
ARG OS_VERSION="bookworm"
ARG TL_VERSION="latest"
ARG _BUILD_CONTEXT_PREFIX=""

# Base OS stage
FROM ${BASE_OS}:${OS_VERSION} AS base

# Combine package installations + add missing Perl dependency
RUN install_packages \
    locales \
    wget \
    curl \
    ca-certificates \
    perl \
    libyaml-tiny-perl \
    libfile-homedir-perl \
    libunicode-linebreak-perl \
    # Add missing dependency for latexindent
    liblog-log4perl-perl \
    liblog-dispatch-perl \
    make \
    gettext-base \
    python3 \
    python3-pygments \
    git \
    # cannot use `default-jre-headless`, see https://github.com/alexpovel/latex-cookbook/issues/17
    default-jre \
    inkscape \
    gnuplot-nox \
    ghostscript \
    poppler-utils \
    librsvg2-bin \
    pandoc \
    cabextract && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3 1 && \
    # Minideb already cleans by default; remove remnants if any
    rm -rf /var/lib/apt/lists/*

# Set global encoding
ENV LANG=C.utf8 LC_ALL=C.utf8

# Download stage
FROM base AS downloads

# Renew arguments for this stage
ARG TL_VERSION
ARG _BUILD_CONTEXT_PREFIX
ARG TL_INSTALL_ARCHIVE="install-tl-unx.tar.gz"
ARG EISVOGEL_ARCHIVE="Eisvogel.tar.gz"
ARG INSTALL_TL_DIR="install-tl"

WORKDIR /tmp

# Copy and process script
COPY ./${_BUILD_CONTEXT_PREFIX}/texlive.sh .
RUN chmod +x texlive.sh && \
    ./texlive.sh get_installer ${TL_VERSION} && \
    wget -nv https://github.com/Wandmalfarbe/pandoc-latex-template/releases/latest/download/${EISVOGEL_ARCHIVE} && \
    mkdir -p ${INSTALL_TL_DIR} eisvogel && \
    tar --extract --file=${TL_INSTALL_ARCHIVE} --directory=${INSTALL_TL_DIR} --strip-components 1 && \
    tar --extract --file=${EISVOGEL_ARCHIVE} --directory=eisvogel --strip-components=1

# Main stage
FROM base AS main

# Renew arguments for final stage
ARG TL_VERSION
ARG _BUILD_CONTEXT_PREFIX
ARG USER="tex"
ARG TL_PROFILE="texlive.profile"
ARG TMP_TL_PROFILE="${TL_PROFILE}.tmp"
ARG INSTALL_TL_DIR="install-tl"

# Create user with fixed UID/GID
RUN groupadd --gid 1000 ${USER} && \
    useradd --create-home --uid 1000 --gid 1000 --home-dir /home/${USER} ${USER}

LABEL maintainer="Wyatt Au <wyatt_au@protonmail.com>" \
      org.label-schema.description="OmniLaTeX required tooling" \
      org.label-schema.vcs-url="https://github.com/WyattAu/OmniLaTeX-docker"

# Setup installation environment
ARG INSTALL_DIR="/install"
WORKDIR ${INSTALL_DIR}

# Copy necessary files
COPY ${_BUILD_CONTEXT_PREFIX}/config/${TL_PROFILE} ${TMP_TL_PROFILE}
COPY --from=downloads /tmp/texlive.sh .
COPY ${_BUILD_CONTEXT_PREFIX}/config/.wgetrc /etc/wgetrc
COPY --from=downloads /tmp/${INSTALL_TL_DIR}/ .  

# Create pandoc directory and copy template
RUN mkdir -p /home/${USER}/.pandoc/templates && \
    chown ${USER}:${USER} /home/${USER}/.pandoc
COPY --from=downloads /tmp/eisvogel/eisvogel.latex /home/${USER}/.pandoc/templates/

# Process profile and install TeXLive
RUN cat "${TMP_TL_PROFILE}" | envsubst | tee "${TL_PROFILE}" && \
    rm "${TMP_TL_PROFILE}" && \
    ./texlive.sh install "${TL_VERSION}"

# Fix ownership and install class file
RUN chown -R ${USER}:${USER} /home/${USER} && \
    mkdir -p /home/${USER}/texmf/tex/latex && \
    wget --no-verbose -O /home/${USER}/texmf/tex/latex/acp.cls \
        https://collaborating.tuhh.de/m21/public/theses/itt-latex-template/-/raw/master/acp.cls

# Prepare user environment
USER ${USER}
WORKDIR /home/${USER}

# Initialize font cache
RUN luaotfload-tool --update || echo "luaotfload-tool update skipped"

# Final runtime configuration
CMD [ "--lualatex" ]
ENTRYPOINT [ "latexmk" ]
