import logging
import pymongo
import pymongo.errors
from datetime import datetime
logger = logging.getLogger(__name__)

class Karma(object):
    KARMA_EXPIRY_TIME_SECONDS=25

    def __init__(self, mongoClient):
        self.mongo_client = mongoClient
        self.karma_collection = self.mongo_client.db.karma

    # find a match which is fit enough for the specified client.
    def getKarmaDeduction(self, client):
        #assert isinstance(client, Client)

        clientFacebookId = client.login_details.facebook_id
        query = { "facebookId" : clientFacebookId }
        try:
            item = self.karma_collection.find(query)
            if item is None:
                return 0

            return item.count()
        except Exception as e:
            raise ValueError(e)

    def pushKarmaDeduction(self, client):
        if client is None:
            return

        #assert isinstance(client, Client)

        clientFacebookId = client.login_details.facebook_id

        self.karma_collection.create_index([("facebookId", pymongo.ASCENDING)])
        self.karma_collection.create_index([("date", pymongo.ASCENDING)], expireAfterSeconds=Karma.KARMA_EXPIRY_TIME_SECONDS)

        recordToInsert = {"facebookId" : clientFacebookId,
                          "date": datetime.utcnow() } # For TTL removing.

        logger.debug("Writing karma deduction to database for Facebook ID: [%s]" % (clientFacebookId))
        self.karma_collection.insert_one(recordToInsert)

    def listItems(self):
        for item in self.karma_collection.find():
            print item