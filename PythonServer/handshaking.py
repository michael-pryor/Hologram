import uuid
import logging
from client import Client

__author__ = 'pryormic'

logger = logging.getLogger(__name__)

class UdpConnectionLink(object):
    def __init__(self, udpHash, waitingClient):
        super(UdpConnectionLink, self).__init__()
        if waitingClient is not None:
            assert isinstance(waitingClient, Client)
        self.udp_hash = udpHash
        self.waiting_client = waitingClient
        self.registered_addresses = set()

    def __hash__(self):
        return hash(self.udp_hash)

    def __eq__(self, other):
        if isinstance(other, UdpConnectionLink):
            return self.udp_hash == other.udp_hash
        elif isinstance(other, basestring):
            return self.udp_hash == other
        else:
            return False


class UdpConnectionLinker(object):
    def __init__(self):
        super(UdpConnectionLinker, self).__init__()
        self.waiting_hashes = dict()

    def registerInterest(self, udpHash, waitingClient):
        obj = UdpConnectionLink(udpHash, waitingClient)
        if obj in self.waiting_hashes:
            logger.warn("Duplicate UDP hash detected [%s], not registering interest" % udpHash)
            return False

        self.waiting_hashes[obj] = obj
        logger.info("Interest registered in UDP hash [%s]" % udpHash)
        return True

    def generateHash(self):
        # Generate a truly unique hash.
        while True:
            newHash = str(uuid.uuid4())
            if newHash not in self.waiting_hashes:
                return newHash


    def registerInterestGenerated(self, waitingClient, newHash = None):
        provided = newHash is not None

        while True:
            # it is possible for a race condition to occur where same hash generated at
            # similar time and attempted to be added. Allowing for failure here solves that problem.
            if newHash is None:
                newHash = self.generateHash()
            success = self.registerInterest(newHash, waitingClient)
            if success or provided:
                return newHash

    def registerPrematureCompletion(self, udpHash, waitingClient):
        logger.info("UDP connection with hash [%s] was prematurely aborted" % udpHash)
        self.waiting_hashes.remove(UdpConnectionLink(udpHash, waitingClient))

    def registerCompletion(self, udpHash, clientUdp):
        try:
            hashObj = self.waiting_hashes[UdpConnectionLink(udpHash, None)]
            assert isinstance(hashObj, UdpConnectionLink)

            if hashObj.waiting_client.setUdp(clientUdp):
                del self.waiting_hashes[hashObj]

            logger.info("UDP connection with hash [%s] and connection details [%s] has been established" % (udpHash, unicode(clientUdp.remote_address)))
            return hashObj.waiting_client
        except KeyError:
            pass
            #logger.warn("An invalid UDP hash was received from [%s], discarding" % unicode(clientUdp.remote_address))
