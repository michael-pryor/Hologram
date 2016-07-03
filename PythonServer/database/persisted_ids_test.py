import pymongo

from client import Client
from database.persisted_ids import PersistedIds

if __name__ == '__main__':
    mongoClient = pymongo.MongoClient("localhost", 27017)
    db = PersistedIds(mongoClient)
    db.collection.drop()

    amountToPush = 1000

    def getRandomId():
        return Client.buildDummy().login_details.persisted_unique_id

    clientsList = [getRandomId() for x in range(0,amountToPush)]

    for client in clientsList:
        result = db.validateId(client)
        if not result:
            print "Failed to validate unexpectedly"


    for client in clientsList:
        result = db.validateId(client)
        if result:
            print "Validated unexpectedly"