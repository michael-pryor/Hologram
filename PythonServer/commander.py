from twisted.internet.protocol import ClientFactory
from twisted.internet import reactor, defer, ssl
from protocol_client import ClientTcp
from byte_buffer import ByteBuffer
from utility import inet_addr, Throttle, parseLogLevel
from twisted.internet.endpoints import TCP4ServerEndpoint, SSL4ServerEndpoint
from threading import RLock
from twisted.internet.error import AlreadyCalled, AlreadyCancelled

import logging
import argparse
import os

__author__ = 'pryormic'


logger = logging.getLogger(__name__)

class CommanderGovernor(object):
    TIMEOUT=15

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
        self.serverName = None
        self.disconnect_timeout = reactor.callLater(CommanderGovernor.TIMEOUT, self.forceDisconnect)

    def forceDisconnect(self):
        logger.warn("Forcefully disconnecting governor, not received ping within timeout: [%s]", self)
        if self.tcp.transport is not None:
            self.tcp.transport.loseConnection()
        else:
            logger.error("Attempted to forcefully disconnect governor, due to ping timeout, but TCP transport not setup yet: [%s]", self)

        self.onDisconnect()

    def onDisconnect(self):
        self.connection_status = CommanderGovernor.ConnectionStatus.DISCONNECTED
        self.on_close_func(self)

    def handleTcpPacket(self, packet):
        assert isinstance(packet, ByteBuffer)

        try:
            self.disconnect_timeout.reset(CommanderGovernor.TIMEOUT)
        except (AlreadyCalled, AlreadyCancelled):
            pass

        if self.connection_status == CommanderGovernor.ConnectionStatus.WAITING_FOR_CONNECTION_DETAILS:
            passwordEnvVariable = os.environ['HOLOGRAM_PASSWORD']
            if len(passwordEnvVariable) == 0:
               raise RuntimeError('HOLOGRAM_PASSWORD env variable must be set')

            passwordFromGovernor = packet.getString()
            if passwordFromGovernor != passwordEnvVariable:
                logger.warn('Invalid governor password of: %s' % passwordFromGovernor)
                self.tcp.transport.loseConnection()
                return

            self.serverName = packet.getString()
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
        self.sub_servers_by_name = dict()

        self.best_sub_server = None

    @Throttle(2)
    def updateBestSubServer(self):
        self.sub_servers_lock.acquire()
        try:
            lowest_load = -1;
            lowestSubServer = None
            for subServer in self.sub_servers:
                assert isinstance(subServer, CommanderGovernor)
                if subServer.serverName is not None and subServer.serverName not in self.sub_servers_by_name:
                    self.sub_servers_by_name[subServer.serverName] = subServer

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

    def getSubServerByName(self, name):
        self.sub_servers_lock.acquire()
        try:
            return self.sub_servers_by_name.get(name)
        finally:
            self.sub_servers_lock.release()

    def clientDisconnected(self, client):
        assert isinstance(client, CommanderGovernor)
        self.sub_servers_lock.acquire()
        try:
            logger.info("Governor disconnected, deleting [%s]" % client)
            self.sub_servers.remove(client)
            if client.serverName is not None:
                self.sub_servers_by_name.remove(client.serverName)
            if client is self.best_sub_server:
                self.best_sub_server = None
                logger.info("Cleared best sub server: [%s]" % client)
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
    TIMEOUT = 10

    class RouterCodes:
        SUCCESS = 1
        FAILURE = 2

    def __init__(self, subServerCoordinator):
        assert isinstance(subServerCoordinator, CommanderGovernorController)
        self.subServerCoordinator = subServerCoordinator
        self.timeout_action = None
        self.tcp = None

    def buildProtocol(self, addr):
        logger.info('TCP connection initiated with new client [%s]' % addr)
        self.tcp = ClientTcp(addr)
        self.tcp.parent = self

        return self.tcp

    def terminate(self):
        logger.warn("Terminating inactive client connection [%s]" % self.tcp)
        if self.tcp is not None:
            self.tcp.transport.loseConnection()

    def startFactory(self):
        self.timeout_action = reactor.callLater(CommanderClientRouting.TIMEOUT, self.terminate)

    def stopFactory(self):
        self.cancelTimeoutAction()

    def cancelTimeoutAction(self):
        try:
            if self.timeout_action is not None:
                self.timeout_action.cancel(self, delay)
        except AlreadyCalled:
            pass
        except AlreadyCancelled:
            pass

    def handleTcpPacket(self, packet):
        nameOfServer = packet.getString()

        if nameOfServer is not None and len(nameOfServer) > 0:
            subServer = self.subServerCoordinator.getSubServerByName(nameOfServer)
            if subServer is None:
                logger.warn("Could not find sub server named: %s, defaulting to primary governor" % nameOfServer)
            else:
                if logger.isEnabledFor(logging.DEBUG):
                    logger.debug("Directed client to requested server named %s" % nameOfServer)
        else:
            subServer = self.subServerCoordinator.getNextSubServer()


        if subServer is None:
            self.sendFailure("No governors available")
        else:
            self.sendSuccess(subServer)

        self.tcp.transport.loseConnection()

    def sendSuccess(self, subServer):
        result = ByteBuffer()

        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("Directed client to governor: [%s]" % subServer)
        result.addUnsignedInteger8(CommanderClientRouting.RouterCodes.SUCCESS)
        result.addByteBuffer(subServer.forwardPacket, includePrefix=False)

        self.tcp.sendByteBuffer(result)

    def sendFailure(self, failureMessage):
        logger.warn("Failed to retrieve server, rejecting client, reason: %s" % failureMessage)
        result = ByteBuffer()
        result.addUnsignedInteger8(CommanderClientRouting.RouterCodes.FAILURE)
        result.addString(failureMessage)
        self.tcp.sendByteBuffer(result)

    def onConnectionMade(self):
        pass




if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Commander Server', argument_default=argparse.SUPPRESS)
    parser.add_argument('--governor_logon_port', help='Port to bind to via TCP; governor servers register themselves on this port. Defaults to 12240', default="12240")
    parser.add_argument('--client_logon_port', help='Port to bind to via UDP; clients connect to this port. Defaults to 12241.', default="12241")
    parser.add_argument('--governor_host', help='Host to use with governors in the event that the host provided is local', default="")
    parser.add_argument('--log_level', help="ERROR, WARN, INFO or DEBUG", default="INFO")
    args = parser.parse_args()

    logLevel = parseLogLevel(args.log_level)
    logging.basicConfig(level = logLevel, format = '%(asctime)-30s %(name)-20s %(levelname)-8s %(message)s')

    logger.info("COMMANDER STARTED")

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