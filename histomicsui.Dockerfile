FROM girder/tox-and-node
LABEL maintainer="Kitware, Inc. <kitware@kitware.com>"

ENV LANG en_US.UTF-8
# Make a virtualenv with our preferred python
RUN virtualenv --python 3.9 /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN cd /opt && \
    git clone https://github.com/girder/large_image.git && \
    cd /opt/large_image && \
    pip install .[sources] --no-cache-dir --find-links https://girder.github.io/large_image_wheels && \
    pip install ./girder_annotation && \
    pip install ./girder

RUN cd /opt && \
    git clone https://github.com/DigitalSlideArchive/HistomicsUI && \
    cd /opt/HistomicsUI && \
    git checkout honor-the-wsgi && \
    pip install --no-cache-dir -e .[analysis]

RUN cd /opt && \
    git clone https://github.com/girder/slicer_cli_web && \
    cd /opt/slicer_cli_web && \
    git checkout upload-task-specs-from-client && \
    pip install --no-cache-dir -e .[girder]

RUN pip install gunicorn girder-worker[girder] girder-sentry

WORKDIR /opt/HistomicsUI

# Build the girder web client
RUN girder build
