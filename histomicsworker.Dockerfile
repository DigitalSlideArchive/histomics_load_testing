FROM python:3.10

RUN curl -sSL https://get.docker.com/ | sh

RUN pip install girder-slicer-cli-web[girder]
ENV C_FORCE_ROOT=true
