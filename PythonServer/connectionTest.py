__author__ = 'pryormic'

import logging
import time
import threading

logger = logging.getLogger(__name__)

from twisted.internet.protocol import Protocol, ClientFactory
import twisted

def clientSendingThread(transport):
    assert isinstance(transport, twisted.internet.tcp.Client)

    iteration = 1
    while True:
        time.sleep(0)
        logger.info("sending message")
        transport.write("Hello universe, this is iteration: %d" % iteration)
        transport
        iteration += 1


class Echo(Protocol):
    def connectionMade(self):
        logger.info("Starting client sending thread")
        print type(self.transport)
        t = threading.Thread(target=clientSendingThread, args = (self.transport,))
        t.daemon = True
        t.start()


    def dataReceived(self, data):
        logger.info("Client received data: [%s]" % data)

class EchoClientFactory(ClientFactory):
    def startedConnecting(self, connector):
        logger.info('Started to connect.')

    def buildProtocol(self, addr):
        logger.info('Connected.')
        return Echo()

    def clientConnectionLost(self, connector, reason):
        logger.info('Lost connection.  Reason:')

    def clientConnectionFailed(self, connector, reason):
        logger.info('Connection failed. Reason:')

if __name__ == "__main__":
    logging.basicConfig(level = logging.DEBUG)

    host = ""
    port = 12340

    from twisted.internet import reactor
    reactor.connectTCP(host, port, EchoClientFactory())
    reactor.run()