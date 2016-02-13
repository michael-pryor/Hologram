import logging
from multiprocessing import Lock
from byte_buffer import ByteBuffer
from protocol_client import ClientTcp, ClientUdp
from utility import getEpoch
from twisted.internet import task

__author__ = 'pryormic'

logger = logging.getLogger(__name__)

# Representation of client from server's perspective.
class Client(object):
    MINIMUM_VERSION = 1

    class ConnectionStatus:
        WAITING_LOGON = 1
        WAITING_UDP = 2
        CONNECTED = 3
        NOT_CONNECTED = 4

    class UdpOperationCodes:
        OP_REJECT_LOGON = 1
        OP_ACCEPT_LOGON = 2
        OP_ACCEPT_UDP = 3

    class TcpOperationCodes:
        OP_SLOW_DOWN_SEND_RATE = 1
        OP_NAT_PUNCHTHROUGH_ADDRESS = 2
        OP_NAT_PUNCHTHROUGH_CLIENT_DISCONNECT = 3
        OP_SKIP_PERSON = 4  # Client tells server that they want to skip
        OP_RESET_SEND_RATE = 5

        OP_TEMP_DISCONNECT = 6
        OP_PERM_DISCONNECT = 7 # Indicate to client that its end point permanently disconnected (from server to client)
                               # Or client sends this to server to say that it has moved to another screen and won't be coming back.
        OP_SKIPPED_DISCONNECT = 8  # Indicate to client that they were skipped

        OP_PING = 10

    class RejectCodes:
        SUCCESS = 0
        REJECT_HASH_TIMEOUT = 1
        REJECT_VERSION = 2

    class LoginDetails:
        def __init__(self, uniqueId, name, shortName, age, gender, interestedIn, longitude, latitude):
            self.unique_id = uniqueId
            self.name = name
            self.short_name = shortName
            self.age = age
            self.gender = gender
            self.interested_in = interestedIn
            self.longitude = longitude
            self.latitude = latitude

        def __hash__(self):
            return hash(self.unique_id)

        def __eq__(self, other):
            return self.unique_id == other

        def __str__(self):
            return "[Name: %s, age: %d, gender: %d, interested_in: %d, longitude: %.2f, latitude: %.2f]" % (self.name, self.age, self.gender, self.interested_in, self.longitude, self.latitude)

    def __init__(self, tcp, onCloseFunc, udpConnectionLinker, house):
        super(Client, self).__init__()
        assert isinstance(tcp, ClientTcp)

        self.udp = None
        self.tcp = tcp
        self.tcp.parent = self
        self.connection_status = Client.ConnectionStatus.WAITING_LOGON
        self.on_close_func = onCloseFunc
        self.udp_connection_linker = udpConnectionLinker
        self.udp_hash = None
        self.udp_remote_address = None
        self.house = house

        self.last_received_data = None

        def timeoutCheck():
            if self.last_received_data is not None:
                timeDiff = getEpoch() - self.last_received_data
                if timeDiff > 5.0:
                    logger.warn("Dropping client [%s] which has been inactive for %.2f seconds" % (self, timeDiff))
                    self.closeConnection()
                else:
                    pass
                    # logger.debug("Client [%s] last pinged %.2f seconds ago" % (self, timeDiff))

        self.timeout_check = task.LoopingCall(timeoutCheck)
        self.timeout_check.start(2.0)


        self.house_match_timer = None

        logger.info("New client connected, awaiting logon message")

    # Just a way of passing the TCP disconnection to the governor, do not use directly.
    def onTcpSocketDisconnect(self):
        self.timeout_check.stop()

        if self.udp_hash is not None:
            if self.udp_connection_linker is not None:
                self.udp_connection_linker.registerPrematureCompletion(self.udp_hash, self)

            # Needs a UDP hash as that is our identifier.
            # Client has disconnected so temporarily pause that room.
            self.house.pauseRoom(self)

        self.on_close_func(self)


    def setUdp(self, clientUdp):
        assert isinstance(clientUdp, ClientUdp)

        logger.info("UDP socket has connected: [%s]" % unicode(clientUdp))
        self.udp = clientUdp;

        if self.udp is not None:
            self.connection_status = Client.ConnectionStatus.CONNECTED

            # don't need this anymore.
            self.udp_connection_linker = None

            logger.info("Client UDP stream activated, client is fully connected")
            return True
        else:
            return False

    # Closes the TCP socket, triggering indirectly onDisconnect to be called.
    def closeConnection(self):
        self.connection_status = Client.ConnectionStatus.NOT_CONNECTED
        self.tcp.transport.loseConnection()

    def handleLogon(self, packet):
        assert isinstance(packet, ByteBuffer)

        isSessionHash = packet.getUnsignedInteger8() > 0
        if isSessionHash:
            # Reconnection attempt, UDP hash included in logon.
            self.udp_hash = packet.getString()
            if self.udp_hash not in self.udp_connection_linker.clients_by_udp_hash:
                return Client.RejectCodes.REJECT_HASH_TIMEOUT, "Hash timed out, please reconnect fresh"

            # This indicates that a logon ACK should be sent via TCP.
            self.udp_hash = self.udp_connection_linker.registerInterestGenerated(self, self.udp_hash)
            logger.info("Reconnect accepted, hash: %s", self.udp_hash)
        else:
            self.udp_hash = self.udp_connection_linker.registerInterestGenerated(self)

        # Versioning.
        version = packet.getUnsignedInteger()
        if version < Client.MINIMUM_VERSION:
            rejectText = "Invalid version %d vs required %d" % (version, Client.MINIMUM_VERSION)
            return Client.RejectCodes.REJECT_VERSION, rejectText

        # See quark login.
        fullName = packet.getString()
        shortName = packet.getString()
        age = packet.getUnsignedInteger()
        gender = packet.getUnsignedInteger()
        interestedIn = packet.getUnsignedInteger()

        latitude = packet.getFloat()
        longitude = packet.getFloat()

        self.login_details = Client.LoginDetails(self.udp_hash, fullName, shortName, age, gender, interestedIn, longitude, latitude)

        logger.info("Login processed with details, udp hash: [%s], full name: [%s], short name: [%s], age: [%d], gender [%d], interested in [%d], GPS: [(%d,%d)]" % (self.udp_hash, fullName, shortName, age, gender, interestedIn, longitude, latitude))
        return Client.RejectCodes.SUCCESS, self.udp_hash

    def handleTcpPacket(self, packet):
        assert isinstance(packet, ByteBuffer)
        if self.connection_status == Client.ConnectionStatus.WAITING_LOGON:
            response = ByteBuffer()

            rejectCode, dataString = self.handleLogon(packet)
            if rejectCode == Client.RejectCodes.SUCCESS:
                self.connection_status = Client.ConnectionStatus.WAITING_UDP
                logger.info("Logon accepted, waiting for UDP connection")

                response.addUnsignedInteger8(Client.UdpOperationCodes.OP_ACCEPT_LOGON)
                response.addString(dataString) # the UDP hash code.
            else:
                logger.warn("Logon rejected, closing connection, reject code [%d], reject reason [%s]" % (rejectCode, dataString))
                response.addUnsignedInteger8(Client.UdpOperationCodes.OP_REJECT_LOGON)
                response.addUnsignedInteger8(rejectCode)
                response.addString("Reject reason: %s" % dataString)
                self.closeConnection()

            logger.debug("Sending response accept/reject to TCP client: %s", self.tcp)
            self.tcp.sendByteBuffer(response)

        elif self.connection_status == Client.ConnectionStatus.WAITING_UDP:
            logger.warn("TCP packet received while waiting for UDP connection to be established, dropping packet")
            pass
        elif self.connection_status == Client.ConnectionStatus.CONNECTED:
            self.onFriendlyPacketTcp(packet)
        else:
            logger.error("Client in unsupported connection state: %d" % self.parent.connection_status)
            self.closeConnection()

    def handleUdpPacket(self, packet):
        if self.connection_status != Client.ConnectionStatus.CONNECTED:
            logger.warn("Client is not connected, discarding UDP packet")
            return

        self.onFriendlyPacketUdp(packet)

    def onFriendlyPacketTcp(self, packet):
        assert isinstance(packet, ByteBuffer)
        # logger.info("Received a friendly TCP packet with length: %d" % packet.used_size)

        opCode = packet.getUnsignedInteger8()
        if opCode == Client.TcpOperationCodes.OP_PING:
            self.last_received_data = getEpoch()
        elif opCode == Client.TcpOperationCodes.OP_SKIP_PERSON:
            logger.debug("Client [%s] asked to skip person, honouring request" % self)
            self.house.releaseRoom(self, self.house.disconnected_skip)
            self.house.attemptTakeRoom(self)
        elif opCode == Client.TcpOperationCodes.OP_SLOW_DOWN_SEND_RATE:
            endPoint = self.house.room_participant.get(self)
            logger.debug("Forwarding slow down request to client [%s]" % endPoint)
            if endPoint is not None:
                endPoint.tcp.sendByteBuffer(packet)
        elif opCode == Client.TcpOperationCodes.OP_PERM_DISCONNECT:
            logger.debug("Client [%s] has permanently disconnected with immediate impact" % self)
            self.house.releaseRoom(self, self.house.disconnected_permanent)
            self.closeConnection()
        else:
            logger.error("Unknown TCP packet received from client [%s]" % self)

    def onFriendlyPacketUdp(self, packet):
        self.house.handleUdpPacket(self, packet)

    def __str__(self):
        if self.tcp is not None:
            tcpString = unicode(self.tcp)
        else:
            tcpString = "No TCP connection"

        if self.udp is not None:
            udpString = unicode(self.udp)
        else:
            udpString = "No UDP connection"

        return "{Client: [%s] and [%s]}" % (tcpString, udpString)

    def __eq__(self, other):
        assert isinstance(other, Client)
        return self.udp_hash == other.udp_hash

    def __hash__(self):
        return hash(self.udp_hash)