import logging
from multiprocessing import Lock
from byte_buffer import ByteBuffer
from protocol_client import ClientTcp, ClientUdp
from utility import getEpoch
from twisted.internet import task
from twisted.internet.error import AlreadyCalled, AlreadyCancelled
from special_collections import OrderedSet
from collections import namedtuple
from database.blocking import Blocking
import uuid
import random
from database.karma_leveled import KarmaLeveled
from database.persisted_ids import PersistedIds
from utility import htons, inet_addr
from remote_notification import RemoteNotification

__author__ = 'pryormic'

logger = logging.getLogger(__name__)

# Representation of client from server's perspective.
class Client(object):
    MINIMUM_VERSION = 5

    # Clients have absolute maximum of 20 seconds to give their rating before it defaults to an okay rating.
    # App is advised to send within 10 seconds.
    WAITING_FOR_RATING_ABSOLUTE_TIMEOUT = 20
    WAITING_FOR_RATING_TIMEOUT = WAITING_FOR_RATING_ABSOLUTE_TIMEOUT / 2

    # After client does not accept/reject anyone for 3 times, disconnect them.
    SKIPPED_TIMED_OUT_LIMIT = 3

    # Client has 60 seconds to accept or reject match.
    ACCEPTING_MATCH_EXPIRY = 60

    class ConnectionStatus:
        WAITING_LOGON = 1
        WAITING_UDP = 2
        CONNECTED = 3
        NOT_CONNECTED = 4

    class UdpOperationCodes:
        OP_UDP_HASH = 4

    class TcpOperationCodes:
        OP_REJECT_LOGON = 1
        OP_ACCEPT_LOGON = 2
        OP_ACCEPT_UDP = 3

        OP_NAT_PUNCHTHROUGH_ADDRESS = 2
        OP_NAT_PUNCHTHROUGH_CLIENT_DISCONNECT = 3
        OP_SKIP_PERSON = 4  # Client tells server that they want to skip

        OP_TEMP_DISCONNECT = 6
        OP_PERM_DISCONNECT = 7 # Indicate to client that its end point permanently disconnected (from server to client)
                               # Or client sends this to server to say that it has moved to another screen and won't be coming back.
        OP_SKIPPED_DISCONNECT = 8  # Indicate to client that they were skipped

        OP_PING = 10

        OP_RATING = 9 # give a rating of the previous conversation.

        # Note: the opposite of this is skipping the conversation or disconnecting.
        OP_ACCEPTED_CONVERSATION = 14

        OP_ADVISE_MATCH_INFORMATION = 15

        OP_REQUEST_NOTIFICATION = 16

    class RejectCodes:
        SUCCESS = 0
        REJECT_HASH_TIMEOUT = 1
        REJECT_VERSION = 2
        REJECT_BANNED = 3
        KARMA_REGENERATION_FAILED = 4
        PERSISTED_ID_CLASH = 5
        INACTIVE_TIMEOUT = 6

    class ConversationRating:
        BLOCK = 2
        GOOD = 3
        AUDIT = 4 # Don't do anything, we just want to recheck for ban.

    class State:
        # In the process of finding someone to talk to.
        MATCHING = 0

        # Found someone to talk to, waiting for both sides to accept each other.
        ACCEPTING_MATCH = 1

        # Waiting for a rating either of the accepting match stage, of of the matched stage.
        # This rating influences karma.
        RATING_MATCH = 2

        # In the middle of a full blown conversation.
        MATCHED = 3

        @staticmethod
        def parseToString(state):
            if (state == Client.State.MATCHING):
                return "MATCHING"
            elif (state == Client.State.ACCEPTING_MATCH):
                return "ACCEPTING_MATCH"
            elif (state == Client.State.RATING_MATCH):
                return "RATING_MATCH"
            elif (state == Client.State.MATCHED):
                return "MATCHED"


    class LoginDetails(object):
        def __init__(self, uniqueId, persistedUniqueId, name, shortName, age, gender, interestedIn, longitude, latitude, cardText, profilePicture, profilePictureOrientation):
            super(Client.LoginDetails, self).__init__()

            self.unique_id = uniqueId
            self.persisted_unique_id = persistedUniqueId
            self.name = name
            self.short_name = shortName
            self.age = age
            self.gender = gender
            self.interested_in = interestedIn
            self.longitude = longitude
            self.latitude = latitude

            self.card_text = cardText
            self.profile_picture = profilePicture
            self.profile_picture_orientation = profilePictureOrientation

        def __hash__(self):
            return hash(self.unique_id)

        def __eq__(self, other):
            return self.unique_id == other

        def __str__(self):
            return "[Name: %s, age: %d, gender: %d, interested_in: %d]" % (self.short_name, self.age, self.gender, self.interested_in)

    @classmethod
    def buildDummy(cls):
        item = cls(None, ClientTcp(namedtuple('Address', ['host', 'port'], verbose=False)), None, None, None, None, None, None, None, None)
        fbId = str(uuid.uuid4())
        item.login_details = Client.LoginDetails(str(uuid.uuid4()), fbId, "Mike P", "Mike", random.randint(18, 30),
                                                        random.randint(1, 2), random.randint(1, 3),
                                                        random.randint(0, 180), random.randint(0, 90), None, None, None)
        return item

    def __init__(self, reactor, tcp, onCloseFunc, udpConnectionLinker, house, karmaDatabase, paymentVerifier, persistedIdsVerifier, remoteNotification):
        super(Client, self).__init__()
        if tcp is not None:
            assert isinstance(tcp, ClientTcp)
        #assert isinstance(paymentVerifier, Payments)
        assert isinstance(persistedIdsVerifier, PersistedIds)

        if karmaDatabase is not None:
            assert isinstance(karmaDatabase, KarmaLeveled)

        assert isinstance(remoteNotification, RemoteNotification)

        self.cleanup_immediate = False
        self.login_details = None
        self.reactor = reactor
        self.udp = None
        self.tcp = tcp
        if self.tcp is not None:
            self.tcp.parent = self

        self.connection_status = Client.ConnectionStatus.WAITING_LOGON
        self.on_close_func = onCloseFunc
        self.udp_connection_linker = udpConnectionLinker
        self.udp_hash = None
        self.house = house

        self.last_received_data = None
        self.payment_verifier = paymentVerifier
        self.persisted_ids_verifier = persistedIdsVerifier

        if self.tcp is not None:
            self.client_matcher = task.LoopingCall(self.house.aquireMatch, self)
        else:
            self.client_matcher = None

        def timeoutCheck():
            if self.last_received_data is not None:
                timeDiff = getEpoch() - self.last_received_data
                if timeDiff > 5.0:
                    if logger.isEnabledFor(logging.DEBUG):
                        logger.debug("Dropping client [%s] which has been inactive for %.2f seconds" % (self, timeDiff))
                    self.closeConnection()
                else:
                    pass
                    # logger.debug("Client [%s] last pinged %.2f seconds ago" % (self, timeDiff))

        if self.tcp is not None:
            self.timeout_check = task.LoopingCall(timeoutCheck)
            self.timeout_check.start(2.0)
        else:
            self.timeout_check = None

        # Track time between queries to database.
        self.house_match_timer = None

        # Client we were speaking to in last conversation, may not still be connected.
        self.client_most_recently_matched_with = None
        self.waiting_for_rating_task = None

        self.karma_database = karmaDatabase

        # Need SocialID in order to do lookup, so preset with default value.
        self.karma_rating = KarmaLeveled.KARMA_MAXIMUM

        self.social_share_information_packet = None
        self.has_shared_social_information = False

        self.skipped_timed_out = 0
        self.state = Client.State.MATCHING
        self.accepting_match_expiry_action = None
        self.approved_match = False

        self.remote_notification_payload = None
        self.should_notify_on_match_accept = False
        self.remote_notification = remoteNotification
        self.has_been_notified = False

    def transitionState(self, startState, endState):
        if startState == endState:
            return

        self.house.house_lock.acquire()
        try:
            if self.state == endState:
                return

            if startState is None or self.state == startState:
                self.state = endState

                # Predicates which must always be enforced.
                if startState == Client.State.RATING_MATCH and endState == Client.State.MATCHING:
                    self.waiting_for_rating_task = None

                if endState == Client.State.MATCHING:
                    self.approved_match = False

                # Only when we're fully matched do we cancel the expiry.
                # Critical to avoid a race condition.
                if startState == Client.State.ACCEPTING_MATCH and endState == Client.State.MATCHED:
                    self.cancelAcceptingMatchExpiry()

                if logger.isEnabledFor(logging.DEBUG):
                    logger.debug("[STATE TRANSITION] [SUCCESS] (%s) -> (%s)" % (Client.State.parseToString(startState), Client.State.parseToString(endState)))
                return True

            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("[STATE TRANSITION] [FAIL] (%s) -> (%s) **(%s)**" % (Client.State.parseToString(startState), Client.State.parseToString(endState), Client.State.parseToString(self.state)))
            return False
        finally:
            self.house.house_lock.release()

    def adviseNatPunchthrough(self, sourceClient):
        if self.state != Client.State.MATCHED:
            return

        packet = ByteBuffer()
        packet.addUnsignedInteger8(Client.TcpOperationCodes.OP_NAT_PUNCHTHROUGH_ADDRESS)
        packet.addUnsignedInteger(inet_addr(sourceClient.udp.remote_address[0]))
        packet.addUnsignedInteger(htons(sourceClient.udp.remote_address[1]))
        self.transitionState(Client.State.ACCEPTING_MATCH, Client.State.MATCHED)

        if self.tcp is not None:
            self.tcp.sendByteBuffer(packet)
        else:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Not advising NAT punchthrough details to offline client: %s" % self)

    def startExpectingMatchExpiry(self):
        self.cancelAcceptingMatchExpiry()
        if self.tcp is None:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Offline client [%s], not scheduling accepting match expiry" % self)
                return

        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("Scheduled new accepting match expiry for client [%s] in [%s] seconds" % (self, Client.ACCEPTING_MATCH_EXPIRY))
        self.accepting_match_expiry_action = self.reactor.callLater(Client.ACCEPTING_MATCH_EXPIRY, self.doSkipTimedOut)

    def adviseMatchDetails(self, sourceClient, distance, reconnectingClient = False):
        packet = ByteBuffer()
        packet.addUnsignedInteger8(Client.TcpOperationCodes.OP_ADVISE_MATCH_INFORMATION)
        packet.addString(sourceClient.login_details.short_name)
        packet.addUnsignedInteger(sourceClient.login_details.age)
        packet.addUnsignedInteger(distance)
        packet.addUnsignedInteger(Client.WAITING_FOR_RATING_TIMEOUT)
        packet.addUnsignedInteger(KarmaLeveled.KARMA_MAXIMUM)
        packet.addUnsignedInteger(Client.ACCEPTING_MATCH_EXPIRY)
        packet.addUnsignedInteger(self.karma_rating)
        packet.addString(sourceClient.login_details.card_text)
        packet.addByteBuffer(sourceClient.login_details.profile_picture)
        packet.addUnsignedInteger(sourceClient.login_details.profile_picture_orientation)
        packet.addUnsignedInteger8(1 if reconnectingClient else 0)
        packet.addUnsignedInteger8(1 if sourceClient.connection_status == Client.ConnectionStatus.CONNECTED else 0) # Informs whether the match is online or offline.

        self.transitionState(Client.State.MATCHING, Client.State.ACCEPTING_MATCH)
        self.startExpectingMatchExpiry()


        if self.tcp is not None:
            self.tcp.sendByteBuffer(packet)
        else:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Not advising match details to offline client: %s" % self)

            self.udp_connection_linker.clients_by_udp_hash[self.udp_hash] = self

    def cancelAcceptingMatchExpiry(self):
        try:
            if self.accepting_match_expiry_action is not None:
                self.accepting_match_expiry_action.cancel()
        except AlreadyCancelled:
            self.clearInactivityCounter()
        except AlreadyCalled:
            pass

    def clearInactivityCounter(self):
        self.skipped_timed_out = 0

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

        self.on_close_func(self, self.cleanup_immediate)


    def setUdp(self, clientUdp):
        assert isinstance(clientUdp, ClientUdp)

        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("UDP socket has connected: [%s]" % unicode(clientUdp))
        self.udp = clientUdp;
        self.client_matcher.start(0.5)

        # don't need this anymore.
        self.udp_connection_linker = None

        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("Client UDP stream activated, client is fully connected")

    def onConnectionMade(self):
        pass

    # Closes the TCP socket, triggering indirectly onDisconnect to be called.
    def closeConnection(self):
        if self.connection_status != Client.ConnectionStatus.NOT_CONNECTED:
            if self.login_details is not None:
                logger.info("Client %s has disconnected", self.login_details)

        self.cancelAcceptingMatchExpiry()
        self.connection_status = Client.ConnectionStatus.NOT_CONNECTED

        if self.tcp is not None:
            self.tcp.transport.loseConnection()

    def getRejectBannedArguments(self, banMagnitude, expiryTime):
        return Client.RejectCodes.REJECT_BANNED, "You have run out of karma, please wait to regenerate\nMaximum wait time is: %.1f minutes" % (float(expiryTime) / 60.0), banMagnitude, expiryTime

    def handleLogon(self, packet):
        assert isinstance(packet, ByteBuffer)

        isSessionHash = packet.getUnsignedInteger8() > 0
        if isSessionHash:
            # Reconnection attempt, UDP hash included in logon.
            self.udp_hash = packet.getString()
            if self.udp_hash not in self.udp_connection_linker.clients_by_udp_hash:
                return Client.RejectCodes.REJECT_HASH_TIMEOUT, "Hash timed out, please reconnect fresh", None, None

            # This indicates that a logon ACK should be sent via TCP.
            self.udp_hash = self.udp_connection_linker.registerInterestGenerated(self, self.udp_hash)
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Reconnect accepted, hash: %s", self.udp_hash)
        else:
            self.udp_hash = self.udp_connection_linker.registerInterestGenerated(self)

        # Versioning.
        version = packet.getUnsignedInteger()
        if version < Client.MINIMUM_VERSION:
            rejectText = "Invalid version %d vs required %d" % (version, Client.MINIMUM_VERSION)
            return Client.RejectCodes.REJECT_VERSION, rejectText, None, None

        # See hologram login on app side.
        isNewId = packet.getUnsignedInteger8()
        persistedUniqueId = packet.getString()

        if persistedUniqueId is None or (isNewId and not self.persisted_ids_verifier.validateId(persistedUniqueId)):
            return Client.RejectCodes.PERSISTED_ID_CLASH, "ID already in use", None, None

        fullName = packet.getString()
        shortName = packet.getString()
        shortName = shortName[:50] # Restrict to 50 characters.
        age = packet.getUnsignedInteger()
        gender = packet.getUnsignedInteger()
        interestedIn = packet.getUnsignedInteger()

        latitude = packet.getFloat()
        longitude = packet.getFloat()

        karmaRegenerationReceipt = packet.getByteBuffer()
        assert isinstance(karmaRegenerationReceipt, ByteBuffer)

        if karmaRegenerationReceipt.used_size == 0:
            karmaRegenerationReceipt = None

        cardText = packet.getString()
        profilePicture = packet.getByteBuffer()
        profilePictureOrientation = packet.getUnsignedInteger()

        self.login_details = Client.LoginDetails(self.udp_hash, persistedUniqueId, fullName, shortName, age, gender, interestedIn, longitude, latitude, cardText, profilePicture, profilePictureOrientation)

        banMagnitude, banTime = self.karma_database.getBanMagnitudeAndExpirationTime(self)
        if banTime is not None and karmaRegenerationReceipt is None:
            return self.getRejectBannedArguments(banMagnitude, banTime)

        self.karma_rating = self.karma_database.getKarma(self)

        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("(Full details) Login processed with details, udp hash: [%s], full name: [%s], short name: [%s], age: [%d], gender [%d], interested in [%d], GPS: [(%d,%d)], Karma [%d]" % (self.udp_hash, fullName, shortName, age, gender, interestedIn, longitude, latitude, self.karma_rating))
        logger.info("Client %s login accepted with udp hash: [%s]" % (self.login_details, self.udp_hash))

        return Client.RejectCodes.SUCCESS, self.udp_hash, karmaRegenerationReceipt, None

    def buildRejectPacket(self, rejectCode, dataString, magnitude=None, expiryTime=None, response=None):
        if response is None:
            response = ByteBuffer()

        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("Logon rejected, closing connection, reject code [%d], reject reason [%s]" % (rejectCode, dataString))

        response.addUnsignedInteger8(Client.TcpOperationCodes.OP_REJECT_LOGON)
        response.addUnsignedInteger8(rejectCode)
        response.addString(dataString)
        if magnitude is not None:
            response.addUnsignedInteger8(magnitude)

        if expiryTime is not None:
            response.addUnsignedInteger(expiryTime)

        return response

    def onLoginSuccess(self, dataString):
        if self.connection_status != Client.ConnectionStatus.WAITING_LOGON:
            return

        self.connection_status = Client.ConnectionStatus.WAITING_UDP

        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("Logon accepted, waiting for UDP connection")
            logger.debug("Sending acceptance response to TCP client: %s", self.tcp)

        response = ByteBuffer()
        response.addUnsignedInteger8(Client.TcpOperationCodes.OP_ACCEPT_LOGON)
        response.addString(dataString)  # the UDP hash code.
        self.tcp.sendByteBuffer(response)

    def onLoginFailure(self, rejectCode, dataString, magnitude = None, expiryTime = None):
        if self.connection_status != Client.ConnectionStatus.WAITING_LOGON:
            return

        response = self.buildRejectPacket(rejectCode, dataString, magnitude, expiryTime)

        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("Sending reject response to TCP client: %s", self.tcp)

        self.tcp.sendByteBuffer(response)
        self.closeConnection()

    def handleTcpPacket(self, packet):
        assert isinstance(packet, ByteBuffer)
        if self.connection_status == Client.ConnectionStatus.WAITING_LOGON:
            rejectCode, dataString, magnitude, expiryTime = self.handleLogon(packet)
            rejected = rejectCode != Client.RejectCodes.SUCCESS
            if not rejected:
                if magnitude is None:
                    self.onLoginSuccess(dataString)
                else:
                    # magnitude is the karma regeneration transaction which needs to be verified.
                    # It is a ByteBuffer object.
                    self.payment_verifier.pushEvent(magnitude, self, dataString)
            else:
                self.onLoginFailure(rejectCode, dataString, magnitude, expiryTime)

        elif self.connection_status == Client.ConnectionStatus.WAITING_UDP:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("TCP packet received while waiting for UDP connection to be established, dropping packet")
        elif self.connection_status == Client.ConnectionStatus.CONNECTED:
            self.onFriendlyPacketTcp(packet)
        elif self.connection_status == Client.ConnectionStatus.NOT_CONNECTED:
            pass
        else:
            logger.error("Client in unsupported connection state: %d" % self.connection_status)
            self.closeConnection()

    def handleUdpPacket(self, packet):
        if self.connection_status != Client.ConnectionStatus.CONNECTED:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Client is not connected, discarding UDP packet")
            return

        self.onFriendlyPacketUdp(packet)

    def doSkip(self):
        self.house.house_lock.acquire()
        try:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Client [%s] asked to skip person, honouring request" % self)

            otherClient = self.house.getCurrentMatchOfClient(self)
            if otherClient is not None:
                self.house.pushSkip(self, otherClient)

            if otherClient is not None:
                logger.info("Client %s has skipped %s" % (self.login_details, otherClient.login_details))

            otherClient = self.house.releaseRoom(self, self.house.disconnected_skip)
            self.cancelAcceptingMatchExpiry()

            # Record that we skipped this client, so that we don't rematch immediately.
            if otherClient is not None:
                assert isinstance(otherClient, Client)
                self.setToWaitForRatingOfPreviousConversation(otherClient)

            # The timeout on accepting a match will clear out the other client.
            # We don't want their screen updating in response to our transition.
            self.transitionState(Client.State.MATCHED, Client.State.MATCHING)
            self.transitionState(Client.State.ACCEPTING_MATCH, Client.State.MATCHING)
        finally:
            self.house.house_lock.release()


    def doSkipTimedOut(self):
        self.skipped_timed_out += 1
        if self.skipped_timed_out > Client.SKIPPED_TIMED_OUT_LIMIT:
            rejectPacket = self.buildRejectPacket(Client.RejectCodes.INACTIVE_TIMEOUT, "You were inactive for too long")
            self.tcp.sendByteBuffer(rejectPacket)

            self.closeConnection()

        self.doSkip()

    def onFriendlyPacketTcp(self, packet):
        assert isinstance(packet, ByteBuffer)

        opCode = packet.getUnsignedInteger8()
        if opCode == Client.TcpOperationCodes.OP_PING:
            self.last_received_data = getEpoch()
        elif opCode == Client.TcpOperationCodes.OP_SKIP_PERSON:
            self.doSkip()
        elif opCode == Client.TcpOperationCodes.OP_RATING:
            if self.client_most_recently_matched_with is None:
                if logger.isEnabledFor(logging.DEBUG):
                    logger.debug("No previous conversation to rate")
                return

            rating = packet.getUnsignedInteger8()

            # Only needed in accepting match because need to close the room in the house.
            # The other case where rating is received, is after a conversation has finished,
            # and after the room has already been released.
            self.house.house_lock.acquire()
            try:
                if self.state == Client.State.ACCEPTING_MATCH:
                    if logger.isEnabledFor(logging.DEBUG):
                        logger.debug("Retrieved match during ACCEPTING_MATCH stage, [%s] has blocked [%s]" % (self, self.client_most_recently_matched_with))
                    self.client_most_recently_matched_with.handleRating(rating)
                    self.doSkip()
                    return
            finally:
                self.house.house_lock.release()

            self.setRatingOfOtherClient(rating)

        elif opCode == Client.TcpOperationCodes.OP_PERM_DISCONNECT:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Client [%s] has permanently disconnected with immediate impact" % self)

            # This closes the UDP session, without giving the client a chance to reconnect. It's important so that
            # rooms dont get released later if an offline profile is loaded.
            if self.should_notify_on_match_accept:
                self.cleanup_immediate = True

            self.house.releaseRoom(self, self.house.disconnected_permanent)
            self.closeConnection()
        elif opCode == Client.TcpOperationCodes.OP_ACCEPTED_CONVERSATION:
            logger.info("Client %s accepted the card" % self.login_details)
            self.clearInactivityCounter()
            if not self.house.onAcceptConversation(self):
                self.doSkip()
        elif opCode == Client.TcpOperationCodes.OP_REQUEST_NOTIFICATION:
            self.remote_notification_payload = packet.getHexString()

            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Received remote notification request from client [%s], payload: %s" % (self, self.remote_notification_payload))
            logger.info("Client %s requested that it be notified" % self.login_details)
            self.house.enableRemoteNotification(self)
        else:
            # Must be debug in case rogue client sends us garbage data
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Unknown TCP packet received from client [%s]" % self)
            self.closeConnection()

    # If forced, we will transition state even if we are not waiting to receive a rating from the client.
    def setRatingOfOtherClient(self, rating, forced=False):
        self.house.house_lock.acquire()
        try:
            try:
                if self.waiting_for_rating_task is None:
                    # It's tempting to do a state change from RATING_MATCH to MATCHING here,
                    # but remember that we only want to add them back to house when BOTH sides
                    # have set a rating.
                    if not forced or self.client_most_recently_matched_with is None:
                        return
                else:
                    self.waiting_for_rating_task.cancel()
            except (AlreadyCalled, AlreadyCancelled):
                if forced:
                    self.waiting_for_rating_task = None
                    self.setRatingOfOtherClient(rating, forced=True)
            else:
                self.client_most_recently_matched_with.handleRating(rating)
                if self.client_most_recently_matched_with.waiting_for_rating_task is None:
                    if logger.isEnabledFor(logging.DEBUG):
                        logger.debug("Both clients have received ratings, putting them back into house [%s, %s]" % (self, self.client_most_recently_matched_with))

                    # At this point, both sides will have set their rating so let's put them back in the queue.
                    # Important to do both at the same time so that karma is updated prior to next conversation.
                    self.transitionState(Client.State.RATING_MATCH, Client.State.MATCHING)
                    self.client_most_recently_matched_with.transitionState(Client.State.RATING_MATCH, Client.State.MATCHING)

            self.waiting_for_rating_task = None
        finally:
            self.house.house_lock.release()

    def sendBanMessage(self, magnitude, expiryTime):
        packet = self.buildRejectPacket(*self.getRejectBannedArguments(magnitude, expiryTime))
        if self.tcp is not None:
            self.tcp.sendByteBuffer(packet)
        else:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Not sending ban message to offline client: %s" % self)

        self.closeConnection()
        logger.info("Client %s is banned, force terminated" % self.login_details)

    # This is somebody rating us.
    def handleRating(self, rating):
        self.house.house_lock.acquire()
        try:
            currentKarma = [self.karma_rating]

            def sendBannedMessage():
                banMagnitude, banTime = self.karma_database.getBanMagnitudeAndExpirationTime(self)
                if banTime is None:
                    return

                self.sendBanMessage(banMagnitude, banTime)

            def deductKarma():
                deductSize = 2
                currentKarma[0] -= deductSize
                if currentKarma[0] < 0:
                    deductSize += currentKarma[0]
                    currentKarma[0] = 0

                for n in range(0,deductSize):
                    isBanned = self.karma_database.deductKarma(self, currentKarma[0])
                    if isBanned:
                        sendBannedMessage()
                        return

            def incrementKarma():
                incrementSize = 1
                for n in range(0,incrementSize):
                    currentKarma[0] += incrementSize
                    if currentKarma[0] > KarmaLeveled.KARMA_MAXIMUM:
                        currentKarma[0] = KarmaLeveled.KARMA_MAXIMUM
                    else:
                        self.karma_database.incrementKarma(self)

            if rating == Client.ConversationRating.BLOCK:
                if logger.isEnabledFor(logging.DEBUG):
                    logger.debug("Block for client [%s] received from [%s]" % (self, self.client_most_recently_matched_with))
                deductKarma()
                self.house.pushBlock(self.client_most_recently_matched_with, self)

                if self.client_most_recently_matched_with is not None:
                    logger.info("Client %s blocked by %s" % (self.login_details, self.client_most_recently_matched_with.login_details))
            elif rating == Client.ConversationRating.GOOD:
                if logger.isEnabledFor(logging.DEBUG):
                    logger.debug("Good rating for client [%s] received" % self)
                incrementKarma()

                if self.client_most_recently_matched_with is not None:
                    logger.info("Client %s received good rating from %s" % (self.login_details, self.client_most_recently_matched_with.login_details))
            elif rating == Client.ConversationRating.AUDIT:
                if logger.isEnabledFor(logging.DEBUG):
                    logger.debug("Audited client [%s] for bans" % self)
                sendBannedMessage()
            else:
                if logger.isEnabledFor(logging.DEBUG):
                    logger.debug("Invalid rating received, dropping client: %d" % rating)
                self.closeConnection()

            self.karma_rating = currentKarma[0]
        finally:
            self.house.house_lock.release()

    def auditBans(self):
        self.handleRating(Client.ConversationRating.AUDIT)

    # We need to wait for the client to send a rating, indicating how they felt about their previous conversation.
    def setToWaitForRatingOfPreviousConversation(self, clientFromPreviousConversation):
        self.house.house_lock.acquire()
        try:
            if self.approved_match:
                self.transitionState(Client.State.ACCEPTING_MATCH, Client.State.MATCHING)

            if not self.transitionState(Client.State.MATCHED, Client.State.RATING_MATCH):
                return

            self.waiting_for_rating_task = self.reactor.callLater(Client.WAITING_FOR_RATING_ABSOLUTE_TIMEOUT, self._onWaitingForRatingTimeout)
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Client [%s] is waiting for rating from previous conversation with client [%s]" % (self, clientFromPreviousConversation))
        finally:
            self.house.house_lock.release()

    def _onWaitingForRatingTimeout(self):
        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("Client [%s] timed out waiting for rating from previous client [%s], defaulting value" % (self, self.client_most_recently_matched_with))

        self.setRatingOfOtherClient(Client.ConversationRating.GOOD, forced=True)

    # Must be protected by house lock.
    def shouldMatch(self, client, recurse=True):
        assert isinstance(client, Client)

        # It is a two way relationship.
        if recurse and not client.shouldMatch(self, False):
            return False

        if client.state != Client.State.MATCHING:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Client [%s], match successful: [false], client not in matching state, instead is in [%d]" % (
                    self, client.state))
            return False

        isConnected = client.connection_status == Client.ConnectionStatus.CONNECTED
        if not isConnected and not client.should_notify_on_match_accept:
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug("Client [%s], match successful: [false], client not connected, connected status is [%s] and not enabled for notify, notify enable status is [%s]" % (self, isConnected, client.should_notify_on_match_accept))
            return False

        isPriorMatch = self.house.didRecentlySkip(self, client)
        result = not isPriorMatch
        if result:
            # No need to check both sides in this call, since we already have logic in shouldMatch to
            # check both sides.
            #
            # This checks to see if users blocked each other.
            if self.house.didBlock(self, client, checkBothSides=False):
                if logger.isEnabledFor(logging.DEBUG):
                    logger.debug("Client [%s] has blocked client [%s], not matching them" % (self, client))
                result = False

            # Clients with no karma cannot match.
            if result and self.karma_rating == 0:
                self.auditBans()
                result = False

        if logger.isEnabledFor(logging.DEBUG):
            logger.debug("Client [%s], match successful: [%s], is prior match [%s], online [(True)]" % (self, result, isPriorMatch))

        return result

    # After reconnecting, a client will have a fresh client object, which may be missing some
    # state information e.g. history of recent matches, we copy this over before disposing of the old object.
    def consumeMetaState(self, client):
        assert isinstance(client, Client)
        self.karma_rating = client.karma_rating
        self.has_shared_social_information = client.has_shared_social_information
        self.social_share_information_packet = client.social_share_information_packet
        self.state = client.state

        self.skipped_timed_out = client.skipped_timed_out
        self.approved_match = client.approved_match
        self.has_been_notified = client.has_been_notified

        self.house.house_lock.acquire()
        try:
            # Point at each other; this is important to make sure rating works, because each side
            # waits for the other side to have finished rating before transitioning out of rating state.
            self.client_most_recently_matched_with = client.client_most_recently_matched_with
            if self.client_most_recently_matched_with is not None:
                if self.client_most_recently_matched_with.client_most_recently_matched_with == client:
                    self.client_most_recently_matched_with.client_most_recently_matched_with = self

            # Upon reconnecting, need to go back to matching state. During the connecting stages to come,
            # If we are indeed still in ACCEPTING_MATCH, we will be rematched with house correctly and timeouts
            # will be setup, to ensure that we move out of MATCHING state.
            if client not in self.house.room_participant:
                self.transitionState(Client.State.ACCEPTING_MATCH, Client.State.MATCHING)

            # This isn't setup to work properly on the client side, after they reconnect
            # they won't have the ability to give a rating. So let's make sure server
            # side state reflects this.
            #
            # Mostly this will just transition our state from RATING to MATCHING.
            if client.state == Client.State.RATING_MATCH:
                self.waiting_for_rating_task = client.waiting_for_rating_task
                self._onWaitingForRatingTimeout()
        finally:
            self.house.house_lock.release()

    def isSynthesizedOfflineClient(self):
        return self.tcp is None

    # Must be protected by house lock.
    def onSuccessfulMatch(self, otherClient):
        self.house.house_lock.acquire()
        try:
            self.client_most_recently_matched_with = otherClient
            self.has_shared_social_information = False
            self.social_share_information_packet = None

            self.approved_match = False
            self.transitionState(Client.State.MATCHING, Client.State.ACCEPTING_MATCH)

            # Offline clients must be added manually.
            if self.tcp is None:
                if logger.isEnabledFor(logging.DEBUG):
                    logger.debug("Manually adding offline client to UDP network store: [%s]" % self)
                self.udp_connection_linker.clients_by_udp_hash[self.udp_hash] = self
        finally:
            self.house.house_lock.release()

    def onRoomClosure(self, otherClient):
        self.house.house_lock.acquire()
        try:
            if self.tcp is None:
                if logger.isEnabledFor(logging.DEBUG):
                    logger.debug("Removing offline client from clients_by_udp_hash: [%s]" % self)

                try:
                    del self.udp_connection_linker.clients_by_udp_hash[self.udp_hash]
                except KeyError:
                    logger.error("Closing room involving offline client, could not find in clients_by_udp_hash [%s], hash [%s]" % (self, self.udp_hash))
        finally:
            self.house.house_lock.release()

    def clearKarma(self):
        self.karma_database.clearKarma(self)
        self.karma_rating = KarmaLeveled.KARMA_MAXIMUM

    def onFriendlyPacketUdp(self, packet):
        self.house.handleUdpPacket(self, packet)

    def trySendRemoteNotification(self, matchedWith):
        assert isinstance(matchedWith, Client)

        if not self.should_notify_on_match_accept:
            return

        # Restart the expiry timer, because we want to give time for client to join,
        # as its currently offline.
        self.startExpectingMatchExpiry()

        name = matchedWith.login_details.short_name[:20]

        logger.info("Client %s has been remote notified" % self.login_details)

        payload = {
            'alert' : (u'\U0001F525 Your card has been accepted by %s! You have %d seconds to join.' % (name, Client.ACCEPTING_MATCH_EXPIRY)),
            'badge' : 1
        }

        try:
            self.remote_notification.pushEvent(self, payload=payload)
        finally:
            # This is important, because otherwise this client will be added to the waiting list again
            # after this match finishes.
            self.should_notify_on_match_accept = False
            self.has_been_notified = True


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