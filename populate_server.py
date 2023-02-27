# Please ensure the server is active before running this script
# references https://github.com/DigitalSlideArchive/digital_slide_archive/blob/master/devops/dsa/provision.py
import configparser
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


config = configparser.ConfigParser()
config.read("../login.cfg")

server_url = "http://localhost:8080/api/v1"


def create_admin_user():
    # If there is are no admin users, create an admin user
    if User().findOne({"admin": True}) is None:
        adminParams = {
            "login": config["LOGIN"]["USERNAME"],
            "password": config["LOGIN"]["PASSWORD"],
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

    item = Item().findOne({"folderId": folder["_id"], "name": exampleFileName})
    if not item:
        item = Item().createItem(exampleFileName, creator=adminUser, folder=folder)
        with open(exampleFilePath, "rb") as f:
            Upload().uploadFromFile(
                f,
                os.path.getsize(exampleFilePath),
                name=exampleFileName,
                parentType="item",
                parent=item,
                user=adminUser,
            )
            files = list(Item().childFiles(item=item, limit=2))
            if len(files) == 1:
                large_image_file_id = str(files[0]["_id"])
                large_image_file = File().load(
                    large_image_file_id, force=True, exc=True
                )
                ImageItem().createImageItem(
                    item,
                    large_image_file,
                    adminUser,
                )
    print(item)
    return item


if __name__ == "__main__":
    adminUser = create_admin_user()
    create_assetstore()
    folder = create_collection_folder(adminUser, "Examples", "Data")
    upload_example(folder, adminUser)
