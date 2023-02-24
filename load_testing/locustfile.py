from locust import HttpUser, task, between
import configparser
from girder_client import GirderClient


config = configparser.ConfigParser()
config.read("../login.cfg")


class HistomicsUser(HttpUser):
    wait_time = between(1, 5)

    def on_start(self):
        self.client = GirderClient()
        self.client.authenticate(
            config["LOGIN"]["USERNAME"],
            config["LOGIN"]["PASSWORD"],
        )

    @task
    def get_tiles(self):
        # user = self.client.get("user/me")
        public_folders = self.client.get("folder?text=Public")
        if len(public_folders) == 0:
            raise Exception("No public folders found on server.")
        public_folder = public_folders[0]
        target_items = self.client.get(f"item?folderId={public_folder['_id']}")
        print(target_items)
