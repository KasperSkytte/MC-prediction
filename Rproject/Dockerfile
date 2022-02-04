FROM rocker/rstudio:4.1.2

#multithreaded make
ARG num_threads=10
ENV MAKEFLAGS="-j ${num_threads}"
ENV PASSWORD=supersafepassword

COPY renv.lock .
COPY rstudio-prefs.json /home/rstudio/.config/rstudio/rstudio-prefs.json

#install nice-to-have system dependencies for R, and netstat to scan ports
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qqy && \
apt-get install -y --no-install-recommends --no-install-suggests \
    libxml2-dev \
    libcairo2-dev \
    libxt-dev \
    libjpeg-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev

#install renv, and install all packages in the lock file to /usr/local/lib/R/site-library/ in container
RUN Rscript -e "install.packages('renv', Ncpus = ${num_threads})" \
    && Rscript -e "renv::consent(provided = TRUE)" \
    && Rscript -e "renv::restore( \
        library = '/usr/local/lib/R/site-library/', \
        rebuild = TRUE, \
        clean = TRUE, \
        lockfile = 'renv.lock', \
        prompt = FALSE)"

#enable users to install R packages
RUN chown 1000:1000 -R /usr/local/lib/R/site-library /usr/local/lib/R/library /home/rstudio/

#silence RStudio warnings about not being able to write dictionary stuff to /root
VOLUME /root
