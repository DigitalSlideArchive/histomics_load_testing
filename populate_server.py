# Please ensure the server is active before running this script
# references https://github.com/DigitalSlideArchive/digital_slide_archive/blob/master/devops/dsa/provision.py
import os
from pathlib import Path

from girder.models.assetstore import Assetstore
from girder.models.collection import Collection
from girder.models.file import File
from girder.models.folder import Folder
from girder.models.item import Item
from girder.models.upload import Upload
from girder.models.user import User
from girder_large_image.models.image_item import ImageItem

server_url = "http://localhost:8080/api/v1"


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


def upload_example(folder, adminUser):
    exampleFileName = "example.tiff"
    exampleFilePath = Path("data/example.tiff")

    item = Item().createItem(exampleFileName, creator=adminUser, folder=folder, reuseExisting=True)
    files = list(Item().childFiles(item=item, limit=1))
    if files:
        large_image_file = files[0]
    else:
        with open(exampleFilePath, "rb") as f:
            large_image_file = Upload().uploadFromFile(
                f,
                os.path.getsize(exampleFilePath),
                name=exampleFileName,
                parentType="item",
                parent=item,
                user=adminUser,
            )

    if "largeImage" not in item:
        ImageItem().createImageItem(
            item,
            large_image_file,
            adminUser,
            createJob=False,
        )
    return item


if __name__ == "__main__":
    adminUser = create_admin_user()
    create_assetstore()
    folder = create_collection_folder(adminUser, "Examples", "Data")
    print(upload_example(folder, adminUser))
