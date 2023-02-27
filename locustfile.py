from locust import HttpUser, task, between
from girder_client import GirderClient


class HistomicsUser(HttpUser):
    wait_time = between(1, 5)

    def on_start(self):
        self.client = GirderClient()

    @task
    def get_tiles(self):
        target_items = self.client.get("item", {"text": "example.tiff"})
        if len(target_items) != 1:
            raise Exception("Server must be populated. See README.md.")
        example_item_id = target_items[0]["_id"]
        tile_metadata = self.client.get(f"item/{example_item_id}/tiles")
        print(tile_metadata)
