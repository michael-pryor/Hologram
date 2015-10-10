import logging
import pymongo
import time
from client import Client
from protocol_client import ClientTcp, ClientUdp
import uuid
import random

logger = logging.getLogger(__name__)

class Database(object):

    def __init__(self, serverName, host, port):
        self.mongo_client = pymongo.MongoClient(host, port)
        self.match_collection = self.mongo_client.db.matcher
        self.server_name = serverName

    def removeMatchById(self, uniqueKey):
        self.match_collection.remove({'_id' : uniqueKey})

    def removeMatch(self, client):
        assert isinstance(client, Client)

        uniqueKey = client.login_details.unique_id
        self.removeMatchById(uniqueKey)

    # find a match which is fit enough for the specified client.
    def findMatch(self, client):
        assert isinstance(client, Client)
        loginDetails = client.login_details
        if loginDetails.age == 0:
            loginDetails.age = 18
        if loginDetails.gender == 0:
            loginDetails.gender = 1
        if loginDetails.interested_in == 0:
            loginDetails.interested_in = 3
        genderWanted = loginDetails.interested_in

        if genderWanted == 3:
            query = {}
        else:
            query = {'gender' : genderWanted}



        query.update({'server': self.server_name,
                      'gender_wanted' : {'$in' : [3, loginDetails.gender]},
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

        return self.match_collection.find_one(query)



    # push a client into the waiting list, ready to be found by findMatch.
    def pushWaiting(self, client):
        assert isinstance(client, Client)

        loginDetails = client.login_details

        self.match_collection.create_index([("server", pymongo.ASCENDING),
                                            ("gender", pymongo.ASCENDING),
                                            ("gender_wanted", pymongo.ASCENDING),
                                            ("age", pymongo.ASCENDING),
                                            ("location", pymongo.GEOSPHERE)])

        self.match_collection.create_index([("server", pymongo.ASCENDING),
                                            ("gender_wanted", pymongo.ASCENDING),
                                            ("age", pymongo.ASCENDING),
                                            ("location", pymongo.GEOSPHERE)])

        recordToInsert = {"_id" : loginDetails.unique_id,
                          "server" : self.server_name,
                          "age" : loginDetails.age,
                          "gender": loginDetails.gender,
                          "location": [loginDetails.longitude, loginDetails.latitude],
                          "gender_wanted": loginDetails.interested_in}

        self.match_collection.insert_one(recordToInsert)

    def listItems(self):
        for item in self.match_collection.find():
            print item

if __name__ == '__main__':
    db = Database("michael_governor", "localhost", 27017)
    db.match_collection.drop()

    amountToPush = 1000
    amountToTest = 1000

    def getRandomClient():
        dummyClient = Client(ClientTcp(("localhost",0)), None, None, None)
        dummyClient.login_details = Client.LoginDetails(str(uuid.uuid4()), "Mike P", random.randint(18,30), random.randint(1,2), random.randint(1,3), random.randint(0,180), random.randint(0,90))
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

