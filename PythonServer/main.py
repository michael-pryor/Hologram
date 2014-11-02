__author__ = 'pryormic'

import logging

logger = logging.getLogger(__name__)

from twisted.internet import protocol, reactor, endpoints

class Echo(protocol.Protocol):
    def dataReceived(self, data):
        logger.info("Server received data: [%s], echoing back" % data)
        self.transport.write(data)

class EchoFactory(protocol.Factory):
    def buildProtocol(self, addr):
        logger.info("Got connection [%s]" % addr)
        return Echo()



if __name__ == "__main__":
    logging.basicConfig(level = logging.DEBUG)

    port = 12340

    logging.info("Starting server on port [%d]" % port)

    endpoints.serverFromString(reactor, "tcp:%d" % port).listen(EchoFactory())
    reactor.run()
