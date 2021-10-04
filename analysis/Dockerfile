FROM rocker/rstudio:4.1.0

#multithreaded make
ARG num_threads=10
ARG ampvis2_rel="2.7.11"
ENV MAKEFLAGS="-j ${num_threads}"
ENV PASSWORD=supersafepassword

COPY renv.lock .
COPY .devcontainer/startmsg.sh /opt/

#install nice-to-have system dependencies for R, and netstat to scan ports
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qqy && \
apt-get install -y --no-install-recommends --no-install-suggests \
    libxml2-dev \
    libcairo2-dev \
    libxt-dev \
    libjpeg-dev \
    screen \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev

#change CRAN mirror from https://packagemanager.rstudio.com to AAU mirror
#install renv, and install all packages in the lock file to /usr/local/lib/R/site-library/ in container
RUN Rscript -e "install.packages('renv', Ncpus = ${num_threads})" \
    && Rscript -e "renv::consent(provided = TRUE)" \
    && Rscript -e "renv::restore( \
        library = '/usr/local/lib/R/site-library/', \
        rebuild = TRUE, \
        clean = TRUE, \
        lockfile = 'renv.lock', \
        prompt = FALSE)"
RUN Rscript -e "renv::install('madsalbertsen/ampvis2@${ampvis2_rel}')"

#add default RStudio config
COPY .devcontainer/rstudio-prefs.json /home/rstudio/.config/rstudio/rstudio-prefs.json

#enable users to install R packages
RUN chown 1000:1000 -R /usr/local/lib/R/site-library /usr/local/lib/R/library /home/rstudio/

#silence RStudio warnings about not being able to write dictionary stuff to /root
VOLUME /root
