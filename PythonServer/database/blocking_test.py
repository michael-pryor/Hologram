import pymongo

from client import Client
from database.blocking import Blocking

if __name__ == '__main__':
    mongoClient = pymongo.MongoClient("localhost", 27017)
    db = Blocking(mongoClient)
    db.block_collection.drop()

    amountToPush = 1000

    def getRandomClient():
        return Client.buildDummy()

    clientsListA = [getRandomClient() for x in range(0,amountToPush)]
    clientsListB = [getRandomClient() for x in range(0, amountToPush)]

    try:
        for clientA, clientB in zip(clientsListA, clientsListB):
            db.pushBlock(clientA, clientB)
    finally:
        db.listItems()

    for clientA, clientB in zip(clientsListA, clientsListB):
        resultA = db.canMatch(clientA, clientB)
        resultB = db.canMatch(clientB, clientA)
        if resultA is True or resultB is True:
            print "ERROR: Blocked client returning canMatch = true (1)"

        if not db.canMatch(Client.buildDummy(), clientA):
            print "ERROR: Not blocked client returning canMatch = false (2)"

        if not db.canMatch(Client.buildDummy(), clientB):
            print "ERROR: Not blocked client returning canMatch = false (3)"

        if not db.canMatch(clientA, Client.buildDummy()):
            print "ERROR: Not blocked client returning canMatch = false (4)"

        if not db.canMatch(clientB, Client.buildDummy()):
            print "ERROR: Not blocked client returning canMatch = false (5)"

    for clientA, clientB in zip(reversed(clientsListA), clientsListB):
        if not db.canMatch(clientA, clientB):
            print "ERROR: Not blocked client returning canMatch = false (6)"

        if not db.canMatch(clientB, clientA):
            print "ERROR: Not blocked client returning canMatch = false (7)"

    for clientA, clientB in zip(clientsListA, reversed(clientsListB)):
        if not db.canMatch(clientA, clientB):
            print "ERROR: Not blocked client returning canMatch = false (8)"

        if not db.canMatch(clientB, clientA):
            print "ERROR: Not blocked client returning canMatch = false (9)"