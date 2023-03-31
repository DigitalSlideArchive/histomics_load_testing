FROM python:3.10

RUN pip install girder-slicer-cli-web[girder]
ENV C_FORCE_ROOT=true
