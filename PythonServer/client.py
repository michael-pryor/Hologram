import logging
from multiprocessing import Lock
from byte_buffer import ByteBuffer
from protocol_client import ClientTcp, ClientUdp
from utility import getEpoch
from twisted.internet import task
from twisted.internet.error import AlreadyCalled, AlreadyCancelled
from special_collections import OrderedSet

__author__ = 'pryormic'

logger = logging.getLogger(__name__)

# Representation of client from server's perspective.
class Client(object):
    MINIMUM_VERSION = 1

    # Don't rematch with a previously skipped client for first x seconds while we
    # wait for a more suitable match, after x seconds give up and match anyways.
    PRIOR_MATCH_LIST_TIMEOUT_SECONDS = 10

    WAITING_FOR_RATING_TIMEOUT = 5

    class ConnectionStatus:
        WAITING_LOGON = 1
        WAITING_UDP = 2
        CONNECTED = 3
        NOT_CONNECTED = 4

    class UdpOperationCodes:
        OP_REJECT_LOGON = 1
        OP_ACCEPT_LOGON = 2
        OP_ACCEPT_UDP = 3
        OP_UDP_HASH = 4

    class TcpOperationCodes:
        OP_NAT_PUNCHTHROUGH_ADDRESS = 2
        OP_NAT_PUNCHTHROUGH_CLIENT_DISCONNECT = 3
        OP_SKIP_PERSON = 4  # Client tells server that they want to skip

        OP_TEMP_DISCONNECT = 6
        OP_PERM_DISCONNECT = 7 # Indicate to client that its end point permanently disconnected (from server to client)
                               # Or client sends this to server to say that it has moved to another screen and won't be coming back.
        OP_SKIPPED_DISCONNECT = 8  # Indicate to client that they were skipped

        OP_PING = 10

        OP_RATING = 9 # give a rating of the previous conversation.

    class RejectCodes:
        SUCCESS = 0
        REJECT_HASH_TIMEOUT = 1
        REJECT_VERSION = 2

    class ConversationRating:
        OKAY = 0
        BAD = 1
        BLOCK = 2
        GOOD = 3

    class LoginDetails(object):
        def __init__(self, uniqueId, name, shortName, age, gender, interestedIn, longitude, latitude):
            super(Client.LoginDetails, self).__init__()
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

    # Designed to prevent immediately rematching with person that the client skipped.
    class HistoryTracking(object):
        def __init__(self, maxSize=10):
            super(Client.HistoryTracking, self).__init__()
            self.prior_matches = OrderedSet()
            self.max_size = maxSize

        def addMatch(self, identifier):
            if len(self.prior_matches) >= self.max_size:
                self.prior_matches.pop(False)

            self.prior_matches.add(identifier)

        def isPriorMatch(self, identifier):
            return identifier in self.prior_matches

        def __str__(self):
            return str(self.prior_matches)


    def __init__(self, reactor, tcp, onCloseFunc, udpConnectionLinker, house):
        super(Client, self).__init__()
        assert isinstance(tcp, ClientTcp)

        self.reactor = reactor
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
                    logger.debug("Dropping client [%s] which has been inactive for %.2f seconds" % (self, timeDiff))
                    self.closeConnection()
                else:
                    pass
                    # logger.debug("Client [%s] last pinged %.2f seconds ago" % (self, timeDiff))

        self.timeout_check = task.LoopingCall(timeoutCheck)
        self.timeout_check.start(2.0)

        # Track time between queries to database.
        self.house_match_timer = None

        # Track previous matches which we have skipped
        self.match_skip_history = Client.HistoryTracking()

        # Track time of last successful match, so we know if we've been waiting a while to ignore the skip list.
        self.started_waiting_for_match_timer = None

        # Client we were speaking to in last conversation, may not still be connected.
        self.client_from_previous_conversation = None
        self.waiting_for_rating_task = None

        logger.debug("New client connected, awaiting logon message")

    def isConnectedTcp(self):
        return self.connection_status != Client.ConnectionStatus.NOT_CONNECTED

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

        logger.debug("UDP socket has connected: [%s]" % unicode(clientUdp))
        self.udp = clientUdp;
        self.connection_status = Client.ConnectionStatus.CONNECTED

        # don't need this anymore.
        self.udp_connection_linker = None

        logger.debug("Client UDP stream activated, client is fully connected")

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
            logger.debug("Reconnect accepted, hash: %s", self.udp_hash)
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

        logger.debug("(Full details) Login processed with details, udp hash: [%s], full name: [%s], short name: [%s], age: [%d], gender [%d], interested in [%d], GPS: [(%d,%d)]" % (self.udp_hash, fullName, shortName, age, gender, interestedIn, longitude, latitude))
        logger.info("Login processed with udp hash: [%s]; identifier: [%s/%d]" % (self.udp_hash, shortName, age))
        return Client.RejectCodes.SUCCESS, self.udp_hash

    def handleTcpPacket(self, packet):
        assert isinstance(packet, ByteBuffer)
        if self.connection_status == Client.ConnectionStatus.WAITING_LOGON:
            response = ByteBuffer()

            rejectCode, dataString = self.handleLogon(packet)
            if rejectCode == Client.RejectCodes.SUCCESS:
                self.connection_status = Client.ConnectionStatus.WAITING_UDP
                logger.debug("Logon accepted, waiting for UDP connection")

                response.addUnsignedInteger8(Client.UdpOperationCodes.OP_ACCEPT_LOGON)
                response.addString(dataString) # the UDP hash code.
            else:
                logger.debug("Logon rejected, closing connection, reject code [%d], reject reason [%s]" % (rejectCode, dataString))
                response.addUnsignedInteger8(Client.UdpOperationCodes.OP_REJECT_LOGON)
                response.addUnsignedInteger8(rejectCode)
                response.addString("Reject reason: %s" % dataString)
                self.closeConnection()

            logger.debug("Sending response accept/reject to TCP client: %s", self.tcp)
            self.tcp.sendByteBuffer(response)

        elif self.connection_status == Client.ConnectionStatus.WAITING_UDP:
            logger.debug("TCP packet received while waiting for UDP connection to be established, dropping packet")
            pass
        elif self.connection_status == Client.ConnectionStatus.CONNECTED:
            self.onFriendlyPacketTcp(packet)
        else:
            logger.error("Client in unsupported connection state: %d" % self.parent.connection_status)
            self.closeConnection()

    def handleUdpPacket(self, packet):
        if self.connection_status != Client.ConnectionStatus.CONNECTED:
            logger.debug("Client is not connected, discarding UDP packet")
            return

        self.onFriendlyPacketUdp(packet)

    def onFriendlyPacketTcp(self, packet):
        assert isinstance(packet, ByteBuffer)

        opCode = packet.getUnsignedInteger8()
        if opCode == Client.TcpOperationCodes.OP_PING:
            self.last_received_data = getEpoch()
        elif opCode == Client.TcpOperationCodes.OP_SKIP_PERSON:
            logger.debug("Client [%s] asked to skip person, honouring request" % self)
            otherClient = self.house.releaseRoom(self, self.house.disconnected_skip)

            # Record that we skipped this client, so that we don't rematch immediately.
            if otherClient is not None:
                assert isinstance(otherClient, Client)
                self.match_skip_history.addMatch(otherClient.udp_hash)
                self.setToWaitForRatingOfPreviousConversation(otherClient)
        elif opCode == Client.TcpOperationCodes.OP_RATING:
            if self.client_from_previous_conversation is None:
                logger.debug("No previous conversation to rate")
                return

            rating = packet.getUnsignedInteger8()
            self.setRatingOfOtherClient(rating)
        elif opCode == Client.TcpOperationCodes.OP_PERM_DISCONNECT:
            logger.debug("Client [%s] has permanently disconnected with immediate impact" % self)
            self.house.releaseRoom(self, self.house.disconnected_permanent)
            self.closeConnection()
        else:
            # Must be debug in case rogue client sends us garbage data
            logger.debug("Unknown TCP packet received from client [%s]" % self)
            self.closeConnection()

    def setRatingOfOtherClient(self, rating):
        try:
            if self.waiting_for_rating_task is not None:
                self.waiting_for_rating_task.cancel()
        except (AlreadyCalled, AlreadyCancelled):
            pass
        else:
            self.client_from_previous_conversation.handleRating(rating)
            if self.client_from_previous_conversation.waiting_for_rating_task is None:
                logger.debug("Both clients have received ratings, putting them back into house [%s, %s]" % (self, self.client_from_previous_conversation))
                # At this point, both sides will have set their rating so let's put them back in the queue.
                self.waiting_for_rating_task = None
                self.house.attemptTakeRoom(self.client_from_previous_conversation)
                self.house.attemptTakeRoom(self)

            self.client_from_previous_conversation = None

        self.waiting_for_rating_task = None

    # This is somebody rating us.
    def handleRating(self, rating):
        if rating == Client.ConversationRating.BAD:
            logger.debug("Bad rating for client [%s] received" % self)
        elif rating == Client.ConversationRating.BLOCK:
            logger.debug("Block for client [%s] received" % self)
        elif rating == Client.ConversationRating.GOOD:
            logger.debug("Good rating for client [%s] received" % self)
        elif rating == Client.ConversationRating.OKAY:
            logger.debug("Okay rating for client [%s] received" % self)
        else:
            logger.debug("Invalid rating received, dropping client: %d" % rating)
            self.closeConnection()

    # We need to wait for the client to send a rating, indicating how they felt about their previous conversation.
    def setToWaitForRatingOfPreviousConversation(self, clientFromPreviousConversation):
        self.client_from_previous_conversation = clientFromPreviousConversation
        self.waiting_for_rating_task = self.reactor.callLater(Client.WAITING_FOR_RATING_TIMEOUT, self._onWaitingForRatingTimeout)
        logger.debug("Client [%s] is waiting for rating from previous conversation with client [%s]" % (self, clientFromPreviousConversation))

    def _onWaitingForRatingTimeout(self):
        self.waiting_for_rating_task = None
        logger.debug("Client [%s] timed out waiting for rating from previous client [%s], defaulting value" % (self, self.client_from_previous_conversation))
        self.setRatingOfOtherClient(Client.ConversationRating.OKAY)

    # Must be protected by house lock.
    def shouldMatch(self, client, recurse=True):
        assert isinstance(client, Client)

        # It is a two way relationship.
        if recurse and not client.shouldMatch(self, False):
            return False

        if self.started_waiting_for_match_timer is None:
            secondsWaitingForMatch = 0
        else:
            secondsWaitingForMatch = getEpoch() - self.started_waiting_for_match_timer

        isPriorMatch = self.match_skip_history.isPriorMatch(client.udp_hash)

        result = (not isPriorMatch)  or secondsWaitingForMatch >= Client.PRIOR_MATCH_LIST_TIMEOUT_SECONDS
        logger.debug("Client [%s] has been waiting %.2f seconds for a match; is prior match [%s], match successful: [%s]" % (self, secondsWaitingForMatch, isPriorMatch, result))

        return result

    # After reconnecting, a client will have a fresh client object, which may be missing some
    # state information e.g. history of recent matches, we copy this over before disposing of the old object.
    def consumeMetaState(self, client):
        assert isinstance(client, Client)
        self.match_skip_history = client.match_skip_history

    # Must be protected by house lock.
    def onWaitingForMatch(self):
        if self.started_waiting_for_match_timer is None:
            self.started_waiting_for_match_timer = getEpoch()

    # Must be protected by house lock.
    def onSuccessfulMatch(self):
        self.started_waiting_for_match_timer = None


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