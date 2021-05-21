#Dockerfile inspired by https://sourcery.ai/blog/python-docker/
#exact dockerfile used for base image: https://github.com/tensorflow/tensorflow/blob/0a1c3d28aa5ecbb68b6fa8e85395b9d0127787f6/tensorflow/tools/dockerfiles/dockerfiles/gpu-jupyter.Dockerfile
FROM tensorflow/tensorflow:2.4.1-gpu-jupyter as base

# locales
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

#stop Python from generating .pyc files
ENV PYTHONDONTWRITEBYTECODE 1

#enable Python tracebacks on segfaults
ENV PYTHONFAULTHANDLER 1

#matplotlib temp dir
ENV MPLCONFIGDIR /tmp

COPY Pipfile .
COPY Pipfile.lock .

#upgrade pip, install pipenv and compilation dependencies
RUN python3 -m pip install --upgrade pip && \
  pip install pipenv

# Install python dependencies system wide
RUN pipenv install --python /usr/bin/python3 --deploy --system

# Install application into container
COPY . .
