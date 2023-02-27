## This repository is a testing suite for HistomicsUI Tile Serving.
See https://github.com/DigitalSlideArchive/HistomicsUI.


------

### Getting Started

 1. Run `docker-compose up` in the top-level directory to start HistomicsUI

 2. Run `python3 populate_server.py` to initialize your user and create the assetstore, collection, and example image item for testing

 3. Navigate to `localhost:8080` in your browser to view HistomicsUI. Click on "Collections". If Step 3 was successful, There should be an "Examples" collection, which contains a folder called "Data". Navigate inside this folder to view the example file.



### Running Locust with Web UI

 1. Run `locust` in the top-level directory to start Locust.

 2. Navigate to `localhost:8089` in your browser to view Locust, Enter any values for "number of users" and "spawn rate." Enter `http://localhost:8080` for "host". Click "Start Swarming."



### Running Locust via command line

Use the following command (with any numbers n and m):

```
locust --headless --users [n] --spawn-rate [m] -H http://localhost:8080
```
