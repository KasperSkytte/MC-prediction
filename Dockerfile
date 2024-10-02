#Dockerfile inspired by https://sourcery.ai/blog/python-docker/
FROM tensorflow/tensorflow:2.18.0rc0-gpu-jupyter

# Copy library scripts to execute
COPY .devcontainer/library-scripts/*.sh .devcontainer/library-scripts/*.env /tmp/library-scripts/

# [Option] Install zsh
ARG INSTALL_ZSH="false"
# [Option] Upgrade OS packages to their latest versions
ARG UPGRADE_PACKAGES="true"
# Install needed packages and setup non-root user. Use a separate RUN statement to add your own dependencies.
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID
# [Optional] Set the default user. Omit if you want to keep the default as root.
#USER $USERNAME

RUN export DEBIAN_FRONTEND=noninteractive \
  && apt-get update \
  # Remove imagemagick due to https://security-tracker.debian.org/tracker/CVE-2019-10131
  && apt-get purge -y imagemagick imagemagick-6-common \
  # Install common packages, non-root user
  && bash /tmp/library-scripts/common-debian.sh "${INSTALL_ZSH}" "${USERNAME}" "${USER_UID}" "${USER_GID}" "${UPGRADE_PACKAGES}" "true" "true" \
  && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

ENV TF_FORCE_GPU_ALLOW_GROWTH true
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONFAULTHANDLER 1
ENV MPLCONFIGDIR /tmp
ENV PIP_EXTRA_INDEX_URL 'https://pypi.nvidia.com'
ENV CONDA_DIR /opt/conda
ENV PATH=${CONDA_DIR}/bin:$PATH

COPY renv.lock environment.yml /opt/

RUN export DEBIAN_FRONTEND=noninteractive \
&& apt-get update -qqy \
&& apt-get upgrade -qqy \
&& apt-get -y install --fix-broken --no-install-recommends --no-install-suggests \
    git \
    wget \
    build-essential \
    jq \
    tmux \
    gdebi-core \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libglpk-dev \
    libxt-dev \
    libcairo2-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libtiff5-dev \
    pandoc \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    #enable multithreaded compilation of packages
    && mkdir -p ~/.R \
    && echo "MAKEFLAGS = -j" > ~/.R/Makevars
    #remove user library from .libPaths() as it will be used if present in home directory (and mounted)
    #&& sed -i s/^R_LIBS_USER=/#R_LIBS_USER=/g /opt/R/${R_VERSION}/lib/R/etc/Renviron

RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-py38_23.11.0-2-Linux-x86_64.sh -O /opt/miniconda.sh \
  && /bin/bash /opt/miniconda.sh -b -p /opt/conda \
  && rm -rf /opt/miniconda.sh \
  && conda env create -f /opt/environment.yml -n mc-prediction \
  && ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh \
  && echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc \
  && echo "conda activate mc-prediction" >> ~/.bashrc

# Make RUN commands use the new environment
SHELL ["conda", "run", "-n", "mc-prediction", "/bin/bash", "-c"]

#install R pkgs from lock file
RUN R -e "renv::restore(clean = TRUE, lockfile = '/opt/renv.lock', prompt = FALSE)"

# clean up after yourself, mommy doesn't work here
RUN export DEBIAN_FRONTEND=noninteractive \
  && apt-get update -qqy \
  && apt-get clean -y \
  && rm -rf \
    /tmp/* \
    /opt/environment.yml \
    /opt/renv.lock

# Install (minimal) LaTeX binaries for R, for the default user only
RUN R -e "tinytex::install_tinytex()"

WORKDIR /tf
ENTRYPOINT ["conda", "run", "--no-capture-output", "-n", "mc-prediction", "/bin/bash", "-l"]
