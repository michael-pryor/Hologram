__author__ = 'pryormic'

import logging
import time
import threading

logger = logging.getLogger(__name__)

from twisted.internet.protocol import Protocol, ClientFactory
import twisted
from twisted.internet.endpoints import TCP4ServerEndpoint
from twisted.internet import reactor, task, protocol

from twisted.protocols.basic import IntNStringReceiver

import struct

class Echo(IntNStringReceiver):
    structFormat = "<L"
    MAX_LENGTH = 100000000
    prefixLength = struct.calcsize(structFormat)

    def connectionMade(self):
        logger.info("Connection made to client")

    def stringReceived(self, data):
        logger.info("Client received data, length: %d" % (len(data)))
        self.sendString(data);

class EchoClientFactory(ClientFactory):
    def __init__(self):
        self.clients = []
        self.lc = task.LoopingCall(self.announce)
        self.lc.start(1)

    def startedConnecting(self, connector):
        logger.info('Started to connect.')

    def buildProtocol(self, addr):
        logger.info('Connected.')
        client = Echo()
        self.clients.append(client)
        return client

    def clientConnectionLost(self, connector, reason):
        logger.info('Lost connection.  Reason:')

    def clientConnectionFailed(self, connector, reason):
        logger.info('Connection failed. Reason:')

    def announce(self):
        pass
        #logger.info("sending messages..")
        #for client in self.clients:
            #logger.info("sent message")
            #client.sendString("hello world")

if __name__ == "__main__":
    logging.basicConfig(level = logging.DEBUG)

    host = ""
    port = 12340

    endpoint = TCP4ServerEndpoint(reactor, 12340)
    endpoint.listen(EchoClientFactory())
    reactor.run()