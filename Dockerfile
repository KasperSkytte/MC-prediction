#Dockerfile inspired by https://sourcery.ai/blog/python-docker/
#exact dockerfile used for base image: https://github.com/tensorflow/tensorflow/blob/0a1c3d28aa5ecbb68b6fa8e85395b9d0127787f6/tensorflow/tools/dockerfiles/dockerfiles/gpu-jupyter.Dockerfile
FROM tensorflow/tensorflow:2.7.0-gpu as base

WORKDIR /opt

# locales
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

#stop Python from generating .pyc files
ENV PYTHONDONTWRITEBYTECODE 1

#enable Python tracebacks on segfaults
ENV PYTHONFAULTHANDLER 1

#matplotlib temp dir
ENV MPLCONFIGDIR /tmp

#set R version
ENV R_VERSION 4.1.2

#lock files to manage python and R packages
COPY Pipfile .
COPY Pipfile.lock .
COPY renv.lock .

#upgrade pip, install pipenv and python pkgs according to the lock file (system-wide)
RUN python3 -m pip install --upgrade pip \
  && pip install pipenv \
  && pipenv install --python /usr/bin/python3 --deploy --system

#download and install R, required system dependencies, and R packages
RUN export DEBIAN_FRONTEND=noninteractive \
  && apt-get update -qqy \
  && apt-get -y install --fix-broken --no-install-recommends --no-install-suggests \
    git \
    wget \
    jq \
    gdebi-core \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libxt-dev \
    libcairo2-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libtiff5-dev \
    pandoc \
  #install R from pre-compiled binary
  && curl -O https://cdn.rstudio.com/r/ubuntu-2004/pkgs/r-${R_VERSION}_1_amd64.deb \
  && gdebi --non-interactive r-${R_VERSION}_1_amd64.deb \
  #create symlinks
  && ln -s /opt/R/${R_VERSION}/bin/R /usr/local/bin/R \
  && ln -s /opt/R/${R_VERSION}/bin/Rscript /usr/local/bin/Rscript \
  #enable multithreaded compilation of packages
  && mkdir -p ~/.R \
  && echo "MAKEFLAGS = -j" > ~/.R/Makevars \
  #set CRAN repo to RSPM snapshot on Oct 23, 2021 for ubuntu18
  && echo "options(repos = c(CRAN = 'https://packagemanager.rstudio.com/cran/__linux__/focal/2021-11-30'), download.file.method = 'libcurl')" >> /opt/R/${R_VERSION}/lib/R/etc/Rprofile.site \
  #set default renv package cache for all users
  && echo "RENV_PATHS_CACHE=/opt/R/${R_VERSION}/lib/R/renv-cache/" >> /opt/R/${R_VERSION}/lib/R/etc/Renviron \
  #remove user library from .libPaths() as it will be used if present in home directory (and mounted)
  && sed -i s/^R_LIBS_USER=/#R_LIBS_USER=/g /opt/R/${R_VERSION}/lib/R/etc/Renviron \
  #install renv + required R packages according to the lock file
  && R -e "install.packages('renv')" \
  && R -e "renv::consent(provided = TRUE)"

#install R pkgs from lock file
RUN R -e "renv::restore(library = '/opt/R/${R_VERSION}/lib/R/site-library/', clean = TRUE, lockfile = '/opt/renv.lock', prompt = FALSE)" \
  # clean up after yourself, mommy doesn't work here
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/* \
    /tmp/* \
    /opt/r-${R_VERSION}_1_amd64.deb \
    /opt/Pipfile \
    /opt/*.lock

WORKDIR /tf
