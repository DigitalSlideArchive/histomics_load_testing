from locust import HttpUser, task, between
import random


class HistomicsUser(HttpUser):
    wait_time = between(1, 5)

    def on_start(self):
        self.client.base_url = f"{self.host}/api/v1/"
        target_collection = self.client.get("collection").json()[0]
        target_folder = self.client.get(f"folder?parentType=collection&parentId={target_collection['_id']}").json()
        if len(target_folder) == 0:
            raise Exception("Server must be populated. See README.md.")
        self.target_items = self.client.get(
            f"item?folderId={target_folder[0]['_id']}"
        ).json()

    @task
    def get_tiles(self):
        target_item = random.choice(self.target_items)
        target_item_id = target_item["_id"]
        r = self.client.get(f"item/{target_item_id}/tiles")
        r.raise_for_status()
        target_tile_metadata = r.json()

        # Attempt to get all tiles in image at greatest resolution
        z = target_tile_metadata["levels"] - 1
        for y in range(
            int(target_tile_metadata["sizeY"] / target_tile_metadata["tileHeight"])
        ):
            for x in range(
                int(target_tile_metadata["sizeX"] / target_tile_metadata["tileWidth"])
            ):
                self.client.get(
                    f"item/{target_item_id}/tiles/zxy/{z}/{x}/{y}",
                    name="/tiles/zxy/z/x/y",
                )
