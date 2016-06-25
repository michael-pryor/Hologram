import pymongo

from client import Client
from database.karma import Karma
from random import randint
import time

if __name__ == '__main__':
    mongoClient = pymongo.MongoClient("localhost", 27017)
    db = Karma(mongoClient)
    db.karma_collection.drop()

    amountToPush = 1000

    def getRandomClient():
        return Client.buildDummy()

    clientsList = [getRandomClient() for x in range(0,amountToPush)]
    karmaRatings = [randint(0, Client.KARMA_MAXIMUM) for x in range(0, amountToPush)]

    print "Inserting..."
    try:
        for client, karmaRating in zip(clientsList, karmaRatings):
            for n in range(0,karmaRating):
                db.pushKarmaDeduction(client)
    finally:
        db.listItems()

    print "Validating initial deductions..."
    for client, karmaRating in zip(clientsList, karmaRatings):
        result = db.getKarmaDeduction(client)
        if result != karmaRating:
            print "Mismatch: %s vs expected %s" % (result, karmaRating)

    # MongoDB expires data every 60 seconds, so lets wait twice that.
    sleepSeconds = Karma.KARMA_EXPIRY_TIME_SECONDS + 120
    print "Sleeping for %d seconds to wait for TTL" % sleepSeconds
    time.sleep(sleepSeconds)
    print "Validating TTL..."

    for client in clientsList:
        result = db.getKarmaDeduction(client)
        if result != 0:
            print "Mismatch: %s vs expected %s" % (result, 0)

    print "All finished"