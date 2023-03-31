FROM girder/tox-and-node
LABEL maintainer="Kitware, Inc. <kitware@kitware.com>"

ENV LANG en_US.UTF-8
# Make a virtualenv with our preferred python
RUN virtualenv --python 3.9 /opt/venv
ENV PATH="/opt/venv/bin:$PATH"


RUN pip install large-image[sources] --no-cache-dir --find-links https://girder.github.io/large_image_wheels
RUN cd /opt && \
    git clone https://github.com/DigitalSlideArchive/HistomicsUI && \
    cd /opt/HistomicsUI && \
    git checkout honor-the-wsgi && \
    pip install --no-cache-dir -e .[analysis]

# TODO install slicer_cli_web plugin
RUN pip install gunicorn girder-worker[girder] girder-slicer-cli-web[girder]

WORKDIR /opt/HistomicsUI

# Build the girder web client
RUN girder build
