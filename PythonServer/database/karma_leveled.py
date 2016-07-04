import logging
logger = logging.getLogger(__name__)
from database.karma import Karma

class KarmaLeveled(object):
    # 1 hour.
    #
    # Each Karma deduction will take this amount of time to expire.
    # The first ban will last this long, thereafter bans exponentially increase.
    KARMA_BASE_EXPIRY_TIME_SECONDS = 60 * 60

    # We will start at x, and so assuming no expiration takes place:
    # Ban 1: banned for x seconds.
    # Ban 2: x^2
    # Ban 3: x^3
    # Ban 4: x^4
    MAX_EXPONENTIAL_INCREASES = 4

    # Karma ratings are from between 0 to 5.
    KARMA_MAXIMUM = 5

    def __init__(self, mongoClient):
        self.karma = Karma(mongoClient.db.karma, KarmaLeveled.KARMA_BASE_EXPIRY_TIME_SECONDS, shouldLinkTimes=False)

        # Most severe ban is first in the list (element 0).
        self.bans = []
        for n in range(KarmaLeveled.MAX_EXPONENTIAL_INCREASES, 0, -1):
            expirationTime = KarmaLeveled.KARMA_BASE_EXPIRY_TIME_SECONDS * n
            collectionName = "ban_%d" % n
            logger.info("MongoDB collection [%s] has expiration of %d seconds" % (collectionName, expirationTime))
            self.bans.append(Karma(getattr(mongoClient.db,collectionName), expiryTimeSeconds=expirationTime, shouldLinkTimes=True))

    def listItems(self):
        print "Karma: "
        self.karma.listItems()

        print
        print "Bans:"
        for item, n in zip(self.bans, range(len(self.bans),0,-1)):
            print "BAN_%d (%d seconds. %.2f minutes)" % (n, item.expiry_time_seconds, float(item.expiry_time_seconds) / 60.0)
            item.listItems()
            print

    def dropCollections(self):
        self.karma.karma_collection.drop()

        for ban in self.bans:
            ban.karma_collection.drop()

    def getKarma(self, client):
        #assert isinstance(client, Client)

        karmaDeduction = self.karma.getKarmaDeduction(client)
        maxKarma = KarmaLeveled.KARMA_MAXIMUM
        karma = maxKarma - karmaDeduction

        if karma > KarmaLeveled.KARMA_MAXIMUM:
            karma = KarmaLeveled.KARMA_MAXIMUM
        elif karma < 0:
            karma = 0

        return karma

    # Return true if client has been banned.
    def deductKarma(self, client, karmaOverride=None):
        if client is None:
            return False

        if karmaOverride is None:
            currentKarma = self.getKarma(client)
        else:
            currentKarma = karmaOverride

        if currentKarma < 0:
            return False

        self.karma.pushKarmaDeduction(client)
        if currentKarma > 0:
            return False

        # Ban may expire a bit before the MongoDB cleanup thread hits Karma, so better to wipe it.
        self.karma.clearKarma(client)
        for ban in self.bans:
            assert isinstance(ban, Karma)
            ban.pushKarmaDeduction(client)

        return True

    # Does not wipe the entire ban list, but clears the current ban, such
    # that on next ban time to wait and price increases.
    def clearKarma(self, client):
        if client is None:
            return

        self.karma.clearKarma(client)

        # Increment once on all levels until the one which actually banned us
        def processBans(client, karmaTracker, amountOverBanLimit):
            for n in range(0,amountOverBanLimit+1):
                karmaTracker.incrementKarma(client)
            return False

        self.processClientThroughBans(client, processBans)

    def processClientThroughBans(self, client, onBannedIteration = None):
        def defaultFunc(client, karmaTracker, amountOverBanLimit):
            return amountOverBanLimit >= 0

        if onBannedIteration is None:
            onBannedIteration = defaultFunc

        for banTimeMultiplier, karmaTracker in zip(range(KarmaLeveled.MAX_EXPONENTIAL_INCREASES, 0, -1), self.bans):
            assert isinstance(karmaTracker, Karma)

            banEntries, expirationTime = karmaTracker.getKarmaDeductionAndExpirationTime(client)
            if onBannedIteration(client, karmaTracker, banEntries - banTimeMultiplier):
                return banTimeMultiplier, expirationTime

        return None, None

    def getBanMagnitudeAndExpirationTime(self, client):
        return self.processClientThroughBans(client)

    def incrementKarma(self, client):
        if client is None:
            return

        self.karma.incrementKarma(client)