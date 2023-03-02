from itertools import product

from locust import HttpUser, task, between
from gevent.pool import Pool

# This value is intended to reflect the number of simultaneous requests a typical web browser
# makes while actively interacting with the tile server.
CLIENT_CONCURRENCY = 5


class HistomicsUser(HttpUser):
    wait_time = between(1, 5)

    def on_start(self):
        self.client.base_url = f"http://{self.host}/api/v1/"
        target_items = self.client.get("item?text=example.tiff").json()
        if len(target_items) != 1:
            raise Exception("Server must be populated. See README.md.")
        self.example_item_id = target_items[0]["_id"]
        self.tile_metadata = self.client.get(
            f"item/{self.example_item_id}/tiles"
        ).json()
        z = self.tile_metadata["levels"] - 1
        self.all_tiles = [(z, y, x) for y, x in product(
            range(int(self.tile_metadata["sizeY"] / self.tile_metadata["tileHeight"])),
            range(int(self.tile_metadata["sizeX"] / self.tile_metadata["tileWidth"])),
        )]

    @task
    def get_tiles(self):
        tile_count = len(self.all_tiles)
        tiles_per_worker = tile_count // CLIENT_CONCURRENCY

        def fetch_tiles(start: int, count: int):
            for z, y, x in self.all_tiles[start:start+count]:
                self.client.get(
                    f"item/{self.example_item_id}/tiles/zxy/{z}/{x}/{y}",
                    name="/tiles/zxy/z/x/y",
                )

        pool = Pool()
        for i in range(CLIENT_CONCURRENCY):
            pool.spawn(
                fetch_tiles,
                start=int((i / CLIENT_CONCURRENCY) * tile_count),
                count=tiles_per_worker
            )
        pool.join()
