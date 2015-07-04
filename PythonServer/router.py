from twisted.internet.protocol import ClientFactory
from twisted.internet import reactor, defer
from protocol_client import ClientTcp
from byte_buffer import ByteBuffer
from utility import inet_addr
from twisted.internet.endpoints import TCP4ServerEndpoint

__author__ = 'pryormic'

import logging
import argparse

logger = logging.getLogger(__name__)

class SubServer(object):
    class ConnectionStatus:
        WAITING_FOR_CONNECTION_DETAILS = 1
        CONNECTED = 2
        DISCONNECTED = 3

    def __init__(self, tcpClient, onCloseFunc, governorHost = None):
        assert isinstance(tcpClient, ClientTcp)
        self.tcp = tcpClient
        self.tcp.parent = self
        self.onDisconnect = onCloseFunc
        self.connection_status = SubServer.ConnectionStatus.WAITING_FOR_CONNECTION_DETAILS
        self.forwardIpAddress = None
        self.forwardPortTcp = None
        self.forwardPortUdp = None
        self.forwardPacket = None
        self.governorHost = governorHost

    def onDisconnect(self, disconnected):
        self.connection_status = SubServer.ConnectionStatus.DISCONNECTED
        self.onDisconnect(disconnected)

    def handleTcpPacket(self, packet):
        assert isinstance(packet, ByteBuffer)

        if self.connection_status == SubServer.ConnectionStatus.WAITING_FOR_CONNECTION_DETAILS:
            self.forwardPortTcp = packet.getUnsignedInteger()
            self.forwardPortUdp = packet.getUnsignedInteger()
            self.forwardIpAddress = self.tcp.remote_address.host

            # override.
            if self.governorHost is not None and self.forwardIpAddress == "0.0.0.0" or self.forwardIpAddress == "127.0.0.1":
                self.forwardIpAddress = self.governorHost

            logger.info("Received address for sub server TCP: [%s:%d] and UDP: [%s:%d]" % (self.forwardIpAddress, self.forwardPortTcp, self.forwardIpAddress, self.forwardPortUdp))

            self.forwardPacket = ByteBuffer()
            self.forwardPacket.addUnsignedInteger(inet_addr(self.forwardIpAddress))
            self.forwardPacket.addUnsignedInteger(self.forwardPortTcp)
            self.forwardPacket.addUnsignedInteger(self.forwardPortUdp)

            self.connection_status = SubServer.ConnectionStatus.CONNECTED
        elif self.connection_status == SubServer.ConnectionStatus.CONNECTED:
            logger.error("Received packet from sub server while connected")
        elif self.connection_status == SubServer.ConnectionStatus.DISCONNECTED:
            logger.error("Received packet from sub server while disconnected")
        else:
            logger.error("Received packet from sub server while in unknown connection state")

    def __hash__(self):
        return hash(self.tcp)

    def __eq__(self, other):
        return self.tcp == other.tcp


class SubServerCoordinator(ClientFactory):
    def __init__(self, governorHost = None):
        self.sub_servers = list()
        self.round_robin = 0
        self.governor_host = governorHost

    def getNextSubServer(self):
        for index, value in enumerate(self.sub_servers):
            try:
                result = self.sub_servers[self.round_robin % len(self.sub_servers)]
                self.round_robin += 1
                if result.connection_status == SubServer.ConnectionStatus.CONNECTED:
                    return result
            except KeyError:
                pass

        return None

    def clientDisconnected(self, client):
        assert isinstance(client, SubServer)
        logger.info("Client disconnected, deleting [%s]" % client)
        self.sub_servers.remove(client)

    def buildProtocol(self, addr):
        logger.info('A new governor server has connected with details [%s]' % addr)
        tcp = ClientTcp(addr)
        subServer = SubServer(tcp, self.clientDisconnected, self.governor_host)
        self.sub_servers.append(subServer)
        return tcp

class ServerRouter(ClientFactory):
    class RouterCodes:
        SUCCESS = 1
        FAILURE = 2

    def __init__(self, subServerCoordinator):
        assert isinstance(subServerCoordinator, SubServerCoordinator)
        self.subServerCoordinator = subServerCoordinator

    def buildProtocol(self, addr):
        logger.info('TCP connection initiated with new client [%s]' % addr)
        self.tcp = ClientTcp(addr)
        self.tcp.parent = self

        return self.tcp

    def onConnectionMade(self):
        result = ByteBuffer()

        subServer = self.subServerCoordinator.getNextSubServer()
        if subServer is None:
            result.addUnsignedInteger(ServerRouter.RouterCodes.FAILURE)
            result.addString("No sub servers available")
        else:
            result.addUnsignedInteger(ServerRouter.RouterCodes.SUCCESS)
            result.addByteBuffer(subServer.forwardPacket, includePrefix=False)

        self.tcp.sendByteBuffer(result)


if __name__ == '__main__':
    logging.basicConfig(level = logging.DEBUG)

    parser = argparse.ArgumentParser(description='Commander Server', argument_default=argparse.SUPPRESS)
    parser.add_argument('--governor_logon_port', help='Port to bind to via TCP; governor servers register themselves on this port. Defaults to 12240', default="12240")
    parser.add_argument('--client_logon_port', help='Port to bind to via UDP; clients connect to this port. Defaults to 12241.', default="12241")
    parser.add_argument('--governor_host', help='Host to use with governors in the event that the host provided is local', default="")
    args = parser.parse_args()

    governor_logon_port = int(args.governor_logon_port)
    client_logon_port = int(args.client_logon_port)

    try:
        governor_host = args.governor_host
    except AttributeError:
        governor_host = None

    server = SubServerCoordinator(governor_host)
    router = ServerRouter(server)
    endpoint = TCP4ServerEndpoint(reactor, governor_logon_port)
    endpoint2 = TCP4ServerEndpoint(reactor, client_logon_port)
    endpoint.listen(server)
    endpoint2.listen(router)

    reactor.run()