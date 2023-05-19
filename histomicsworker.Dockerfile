FROM python:3.10

RUN curl -sSL https://get.docker.com/ | sh

RUN pip install girder-slicer-cli-web[worker]

RUN cd /opt && \
    git clone https://github.com/DigitalSlideArchive/HistomicsUI && \
    cd /opt/HistomicsUI && \
    git checkout honor-the-wsgi && \
    pip install --no-cache-dir -e .

ENV C_FORCE_ROOT=true
