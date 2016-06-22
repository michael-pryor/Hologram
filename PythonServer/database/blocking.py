import logging
import pymongo
import time
from client import Client
from protocol_client import ClientTcp, ClientUdp
import uuid
import random
import pymongo.errors
import random

logger = logging.getLogger(__name__)

class Blocking(object):
    RANDOM_FACTOR = 20

    def __init__(self, mongoClient):
        self.mongo_client = mongoClient
        self.block_collection = self.mongo_client.db.blocked

    # find a match which is fit enough for the specified client.
    def canMatch(self, clientA, clientB):
        assert isinstance(clientA, Client)
        assert isinstance(clientB, Client)
        loginDetailsA = clientA.login_details
        loginDetailsB = clientB.login_details

        # If they don't care what gender they want, then don't include gender as part of the query.
        if genderWanted == 3:
            query = {}
        else:
            query = {'gender' : genderWanted}

        query.update({'server': self.server_name,
                      'gender_wanted' : {'$in' : matchWithGenderWanted},
                      # Age over complicates things for now, because we need age selection on GUI.
                      # If we get loads of users we can put this in.
                      #'age' : {'$gt': 0,
                      #         '$lt': loginDetails.age+40},
                      'location' :
                           {'$nearSphere' :
                                  {'$geometry' :
                                       {'type' : 'Point',
                                        'coordinates' : [loginDetails.longitude, loginDetails.latitude]
                                       }
                                  }
                           },
                      '_id' : {'$ne' : loginDetails.unique_id}
                    })

        try:
            cursor = self.block_collection.find(query).limit(Matching.RANDOM_FACTOR)
        except Exception as e:
            raise ValueError(e)

        # Of the results returned, randomly select one person to talk to.
        # Seeded on current time epoch at time random was imported.
        randomIndex = random.randint(0, Matching.RANDOM_FACTOR - 1) # randint is inclusive left and right.

        matches = list()
        for matchIndex in range(0, randomIndex+1): # range is inclusive left and exclusive right.
            try:
                matchClient = cursor.next()
            except StopIteration:
                # No matches
                endRange = len(matches)-1
                if endRange == -1:
                    pass
                elif endRange == 0:
                    randomIndex = 0
                else:
                    # In this case we got less results back than our random index, so we need a smaller random number.
                    randomIndex = random.randint(0, endRange) # randint is inclusive left and right.

                break
            matches.append(matchClient)

        if len(matches) == 0:
            return None

        return matches[randomIndex]

    # push a client into the waiting list, ready to be found by findMatch.
    def pushWaiting(self, client):
        assert isinstance(client, Client)

        loginDetails = client.login_details

        self.block_collection.create_index([("server", pymongo.ASCENDING),
                                            ("gender", pymongo.ASCENDING),
                                            ("gender_wanted", pymongo.ASCENDING),
                                            ("age", pymongo.ASCENDING),
                                            ("location", pymongo.GEOSPHERE)])

        self.block_collection.create_index([("server", pymongo.ASCENDING),
                                            ("gender_wanted", pymongo.ASCENDING),
                                            ("age", pymongo.ASCENDING),
                                            ("location", pymongo.GEOSPHERE)])

        recordToInsert = {"_id" : loginDetails.unique_id,
                          "server" : self.server_name,
                          "age" : loginDetails.age,
                          "gender": loginDetails.gender,
                          "location": [loginDetails.longitude, loginDetails.latitude],
                          "gender_wanted": loginDetails.interested_in}

        self.block_collection.insert_one(recordToInsert)

    def listItems(self):
        for item in self.block_collection.find():
            print item

if __name__ == '__main__':
    db = Matching("michael_governor", "localhost", 27017)
    db.match_collection.drop()

    amountToPush = 1000
    amountToTest = 1000

    def getRandomClient():
        dummyClient = Client(ClientTcp(("localhost",0)), None, None, None)
        dummyClient.login_details = Client.LoginDetails(str(uuid.uuid4()), "Mike P", "Mike", random.randint(18,30), random.randint(1,2), random.randint(1,3), random.randint(0,180), random.randint(0,90))
        return dummyClient

    try:
        for n in range(0,amountToPush):
            db.pushWaiting(getRandomClient())
    finally:
        db.listItems()

    count = 0
    total = 0
    for n in range(0,amountToTest):
        testClient = getRandomClient()
        result = db.findMatch(testClient)
        total += result['executionStats']['totalKeysExamined']
        if result['executionStats']['nReturned'] == 0:
            print 'oh dear'

        print result
        count+=1

    av = float(total) / float(count)
    pkeys = av / float(amountToPush) * 100
    print "Average number of lookups: %.2f" % av
    print "Average %% of records looked at: %.2f" % pkeys
