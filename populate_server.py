# Please ensure the server is active before running this script
# references https://github.com/DigitalSlideArchive/digital_slide_archive/blob/master/devops/dsa/provision.py
import argparse
import os
import requests
from pathlib import Path
from tqdm import tqdm

from girder.models.assetstore import Assetstore
from girder.models.collection import Collection
from girder.models.folder import Folder
from girder.models.item import Item
from girder.models.upload import Upload
from girder.models.user import User
from girder_large_image.models.image_item import ImageItem


def create_admin_user():
    # If there is are no admin users, create an admin user
    if User().findOne({"admin": True}) is None:
        adminParams = {
            "login": "admin",
            "password": "myadminpass",
            "firstName": "Admin",
            "lastName": "Admin",
            "email": "admin@nowhere.nil",
            "public": True,
        }
        User().createUser(admin=True, **adminParams)
    adminUser = User().findOne({"admin": True})
    return adminUser


def create_assetstore():
    # Make sure we have an assetstore
    root = Path(".").absolute() / "assetstore"
    if Assetstore().findOne() is None:
        Assetstore().createFilesystemAssetstore(name="Root", root=root)


def create_collection_folder(adminUser, collName, folderName):
    if Collection().findOne({"lowerName": collName.lower()}) is None:
        Collection().createCollection(collName, adminUser)
    collection = Collection().findOne({"lowerName": collName.lower()})
    if (
        Folder().findOne(
            {"parentId": collection["_id"], "lowerName": folderName.lower()}
        )
        is None
    ):
        Folder().createFolder(
            collection,
            folderName,
            parentType="collection",
            public=True,
            creator=adminUser,
        )
    folder = Folder().findOne(
        {"parentId": collection["_id"], "lowerName": folderName.lower()}
    )
    return folder


def upload_example(filepath, folder, adminUser):
    filename = str(filepath).split("/")[-1]
    item = Item().createItem(
        filename, creator=adminUser, folder=folder, reuseExisting=True
    )
    with open(filepath, "rb") as f:
        large_image_file = Upload().uploadFromFile(
            f,
            os.path.getsize(filepath),
            name=filename,
            parentType="item",
            parent=item,
            user=adminUser,
        )

    if "largeImage" not in item:
        ImageItem().createImageItem(
            item,
            large_image_file,
            adminUser,
            # createJob=False,
        )
    return item


if __name__ == "__main__":
    argparser = argparse.ArgumentParser(
        prog="Populate Histomics Server",
        description="Add example large images to a local histomics server",
    )
    argparser.add_argument(
        "-n",
        "--num_files",
        help="Number of distinct large image files to add to server"
        "Default is 1, only the file included in the repository will be used."
        "If num_files > 1, remaining files will be downloaded from data.kitware.com.",
        type=int,
        default=1,
    )
    args = argparser.parse_args()
    num_files = args.num_files
    filepaths = [Path("data/example.tiff")]

    if num_files > 1:
        resp = requests.get(
            "https://data.kitware.com/api/v1/item/57b345d28d777f126827dc25/files"
        )
        resp.raise_for_status()
        if num_files > len(resp.json()) + 1:
            raise ValueError(
                f"num_files too large; found only {len(resp.json()) + 1} files for upload."
            )
        for file_info in resp.json()[:num_files]:
            filepath = Path("data", file_info["name"])
            if not filepath.exists():
                print(f"Downloading {filepath} from data.kitware.com...")
                with requests.get(
                    f"https://data.kitware.com/api/v1/file/{file_info['_id']}/download",
                    stream=True,
                ) as r, tqdm(
                    total=file_info.get("size", 0),
                    unit="B",
                    unit_scale=True,
                ) as progress_bar, open(
                    filepath, "wb"
                ) as f:
                    r.raise_for_status()
                    for data in r.iter_content(2048):
                        progress_bar.update(f.write(data))

            filepaths.append(filepath)

    adminUser = create_admin_user()
    create_assetstore()
    folder = create_collection_folder(adminUser, "Examples", "Data")
    for filepath in filepaths:
        print(upload_example(filepath, folder, adminUser))
