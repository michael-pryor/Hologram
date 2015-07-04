from twisted.internet.protocol import ClientFactory
from twisted.internet import reactor, defer
from protocol_client import ClientTcp
from byte_buffer import ByteBuffer
from utility import inet_addr

__author__ = 'pryormic'

import logging

logger = logging.getLogger(__name__)

class SubServer(object):
    class ConnectionStatus:
        WAITING_FOR_CONNECTION_DETAILS = 1
        CONNECTED = 2
        DISCONNECTED = 3

    def __init__(self, tcpClient, onCloseFunc):
        assert instance(tcpClient, ClientTcp)
        self.tcp = tcpClient
        self.tcp.parent
        self.on_close_func_parent = onCloseFunc
        self.connection_status = SubServer.ConnectionStatus.WAITING_FOR_CONNECTION_DETAILS
        self.forwardIpAddress = None
        self.forwardPortTcp = None
        self.forwardPortUdp = None
        self.forwardPacket = None

    def on_close_func(self, disconnected):
        self.connection_status = SubServer.ConnectionStatus.DISCONNECTED
        self.on_close_func_parent(disconnected)

    def handleTcpPacket(self, packet):
        assert isinstance(packet, ByteBuffer)

        if self.connection_status == SubServer.ConnectionStatus.WAITING_FOR_CONNECTION_DETAILS:
            self.forwardPortTcp = packet.getUnsignedInteger()
            self.forwardPortUdp = packet.getUnsignedInteger()
            self.forwardIpAddress = self.tcp.remote_address.host
            logger.info("Received address for sub server: [%s:%d]" % (self.forwardIpAddress, self.forwardPort))

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
    def __init__(self):
        self.sub_servers = list()
        self.round_robin = 0

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
        logger.info('TCP connection initiated with new client [%s]' % addr)
        tcp = ClientTcp(addr)
        subServer = SubServer(tcp, self.clientDisconnected)
        self.sub_servers.append(subServer)
        return tcp

class ServerRouter(ClientFactory):
    class RouterCodes:
        SUCCESS = 1
        FAILURE = 2

    def __init__(self, subServerCoordinator):
        assert instance(subServerCoordinator, SubServerCoordinator)
        self.subServerCoordinator = subServerCoordinator

    def buildProtocol(self, addr):
        logger.info('TCP connection initiated with new client [%s]' % addr)
        tcp = ClientTcp(addr)

        result = ByteBuffer()

        subServer = self.subServerCoordinator.getNextSubServer()
        if subServer is None:
            result.addUnsignedInteger(ServerRouter.RouterCodes.FAILURE)
            result.addString("No sub servers available")
        else:
            result.addUnsignedInteger(ServerRouter.RouterCodes.SUCCESS)
            result.addByteBuffer(subServer.forwardPacket, includePrefix=False)

        tcp.sendByteBuffer(result)
        return tcp


if __name__ == '__main__':
    logging.basicConfig(level = logging.DEBUG)

    server = SubServerCoordinator()
    router = ServerRouter()
    endpoint = TCP4ServerEndpoint(reactor, 12240)
    endpoint2 = TCP4ServerEndpoint(reactor, 12241)
    endpoint.listen(server)
    endpoint2.listen(router)

    reactor.run()