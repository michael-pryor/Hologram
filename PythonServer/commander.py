from twisted.internet.protocol import ClientFactory
from twisted.internet import reactor, defer, ssl
from protocol_client import ClientTcp
from byte_buffer import ByteBuffer
from utility import inet_addr, Throttle
from twisted.internet.endpoints import TCP4ServerEndpoint, SSL4ServerEndpoint
from threading import RLock

import logging
import argparse
import os

__author__ = 'pryormic'


logger = logging.getLogger(__name__)

class CommanderGovernor(object):
    class ConnectionStatus:
        WAITING_FOR_CONNECTION_DETAILS = 1
        CONNECTED = 2
        DISCONNECTED = 3

    def __init__(self, tcpClient, onCloseFunc, governorHost = None):
        assert isinstance(tcpClient, ClientTcp)
        self.tcp = tcpClient
        self.tcp.parent = self
        self.on_close_func = onCloseFunc
        self.connection_status = CommanderGovernor.ConnectionStatus.WAITING_FOR_CONNECTION_DETAILS
        self.forwardIpAddress = None
        self.forwardPortTcp = None
        self.forwardPortUdp = None
        self.forwardPacket = None
        self.governorHost = governorHost
        self.current_load = 0

    def onDisconnect(self):
        self.connection_status = CommanderGovernor.ConnectionStatus.DISCONNECTED
        self.on_close_func(self)

    def handleTcpPacket(self, packet):
        assert isinstance(packet, ByteBuffer)

        if self.connection_status == CommanderGovernor.ConnectionStatus.WAITING_FOR_CONNECTION_DETAILS:
            passwordEnvVariable = os.environ['HOLOGRAM_PASSWORD']
            if len(passwordEnvVariable) == 0:
               raise RuntimeError('HOLOGRAM_PASSWORD env variable must be set')

            passwordFromGovernor = packet.getString()
            if passwordFromGovernor != passwordEnvVariable:
                logger.warn('Invalid governor password of: %s' % passwordFromGovernor)
                self.tcp.transport.loseConnection()
                return

            self.forwardPortTcp = packet.getUnsignedInteger()
            self.forwardPortUdp = packet.getUnsignedInteger()
            self.forwardIpAddress = self.tcp.remote_address.host

            # override.
            if self.governorHost is not None and self.forwardIpAddress == "0.0.0.0" or self.forwardIpAddress == "127.0.0.1":
                self.forwardIpAddress = self.governorHost

            logger.info("Received address for governor TCP: [%s:%d] and UDP: [%s:%d]" % (self.forwardIpAddress, self.forwardPortTcp, self.forwardIpAddress, self.forwardPortUdp))

            self.forwardPacket = ByteBuffer()
            self.forwardPacket.addUnsignedInteger(inet_addr(self.forwardIpAddress))
            self.forwardPacket.addUnsignedInteger(self.forwardPortTcp)
            self.forwardPacket.addUnsignedInteger(self.forwardPortUdp)

            self.connection_status = CommanderGovernor.ConnectionStatus.CONNECTED
        elif self.connection_status == CommanderGovernor.ConnectionStatus.CONNECTED:
            load = packet.getUnsignedInteger()
            logger.info("Received load of [%d] from governor [%s]" % (load, self))
            self.current_load = load
        elif self.connection_status == CommanderGovernor.ConnectionStatus.DISCONNECTED:
            logger.error("Received packet from governor while disconnected")
        else:
            logger.error("Received packet from governor while in unknown connection state")

    def __hash__(self):
        return hash(self.tcp)

    def __eq__(self, other):
        return self.tcp == other.tcp

    def __str__(self):
        return str(self.tcp)


class CommanderGovernorController(ClientFactory):
    def __init__(self, governorHost = None):
        self.sub_servers = list()
        self.sub_servers_lock = RLock()
        self.governor_host = governorHost

        self.best_sub_server = None

    @Throttle(2)
    def updateBestSubServer(self):
        self.sub_servers_lock.acquire()
        try:
            lowest_load = -1;
            lowestSubServer = None
            for subServer in self.sub_servers:
                assert isinstance(subServer, CommanderGovernor)
                currentLoad = subServer.current_load
                if currentLoad < lowest_load or lowestSubServer is None:
                    lowest_load = currentLoad
                    lowestSubServer = subServer

            if lowestSubServer is self.best_sub_server:
                logger.info("Recalculated best sub server, remains unchanged with load of [%d], and server: [%s]" % (lowest_load, self.best_sub_server))
            else:
                self.best_sub_server = lowestSubServer
                logger.info("Recalculated best sub server, changed with load of [%d], and new server: [%s]" % (lowest_load, self.best_sub_server))
        finally:
            self.sub_servers_lock.release()


    def getNextSubServer(self):
        self.sub_servers_lock.acquire()
        try:
            self.updateBestSubServer()
            if self.best_sub_server is None and len(self.sub_servers) > 0:
                return self.sub_servers[0]

            return self.best_sub_server
        finally:
            self.sub_servers_lock.release()

    def clientDisconnected(self, client):
        assert isinstance(client, CommanderGovernor)
        self.sub_servers_lock.acquire()
        try:
            logger.info("Governor disconnected, deleting [%s]" % client)
            self.sub_servers.remove(client)
        finally:
            self.sub_servers_lock.release()


    def buildProtocol(self, addr):
        logger.info('A new governor server has connected with details [%s]' % addr)
        tcp = ClientTcp(addr)
        subServer = CommanderGovernor(tcp, self.clientDisconnected, self.governor_host)
        self.sub_servers_lock.acquire()
        try:
            self.sub_servers.append(subServer)
        finally:
            self.sub_servers_lock.release()

        return tcp

class CommanderClientRouting(ClientFactory):
    class RouterCodes:
        SUCCESS = 1
        FAILURE = 2

    def __init__(self, subServerCoordinator):
        assert isinstance(subServerCoordinator, CommanderGovernorController)
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
            logger.warn("Failed to retrieve governor, rejecting client")
            result.addUnsignedInteger8(CommanderClientRouting.RouterCodes.FAILURE)
            result.addString("No governors available")
        else:
            logger.info("Directed client to governor: [%s]" % subServer)
            result.addUnsignedInteger8(CommanderClientRouting.RouterCodes.SUCCESS)
            result.addByteBuffer(subServer.forwardPacket, includePrefix=False)

        self.tcp.sendByteBuffer(result)



if __name__ == '__main__':
    logging.basicConfig(level = logging.DEBUG, format = '%(asctime)-30s %(name)-20s %(levelname)-8s %(message)s')

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

    server = CommanderGovernorController(governor_host)
    router = CommanderClientRouting(server)
    endpoint = SSL4ServerEndpoint(reactor,
                                  governor_logon_port,
                                  ssl.DefaultOpenSSLContextFactory(
                                  '../security/hologram.key',
                                  '../security/hologram.crt'))
    endpoint2 = TCP4ServerEndpoint(reactor, client_logon_port)
    endpoint.listen(server)
    endpoint2.listen(router)

    reactor.run()