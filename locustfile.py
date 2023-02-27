from locust import HttpUser, task, between


class HistomicsUser(HttpUser):
    wait_time = between(1, 5)

    def on_start(self):
        self.client.base_url = "http://localhost:8080/api/v1/"
        target_items = self.client.get("item?text=example.tiff").json()
        if len(target_items) != 1:
            raise Exception("Server must be populated. See README.md.")
        self.example_item_id = target_items[0]["_id"]
        self.tile_metadata = self.client.get(
            f"item/{self.example_item_id}/tiles"
        ).json()

    @task
    def get_tiles(self):
        # Attempt to get all tiles in image at greatest resolution
        z = self.tile_metadata["levels"] - 1
        for y in range(self.tile_metadata["sizeY"])[:5]:
            for x in range(self.tile_metadata["sizeX"])[:5]:
                self.client.get(
                    f"item/{self.example_item_id}/tiles/zxy/{z}/{x}/{y}",
                    name="/tiles/zxy/z/x/y",
                )
