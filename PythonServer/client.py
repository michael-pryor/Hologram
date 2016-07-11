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

__author__ = 'pryormic'

logger = logging.getLogger(__name__)

# Representation of client from server's perspective.
class Client(object):
    MINIMUM_VERSION = 3

    # Clients have absolute maximum of 10 seconds to give their rating before it defaults to an okay rating.
    # App is advised to send within 5 seconds.
    WAITING_FOR_RATING_ABSOLUTE_TIMEOUT = 10
    WAITING_FOR_RATING_TIMEOUT = WAITING_FOR_RATING_ABSOLUTE_TIMEOUT / 2

    # After client does not accept/reject anyone for 3 times, disconnect them.
    SKIPPED_TIMED_OUT_LIMIT = 3

    # Client has 5 seconds to accept or reject match.
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

        OP_SHARE_SOCIAL_INFORMATION_PAYLOAD = 11

        OP_SHARE_SOCIAL_INFORMATION = 12

        # Note: the opposite of this is skipping the conversation or disconnecting.
        OP_ACCEPTED_CONVERSATION = 14

        OP_ADVISE_MATCH_INFORMATION = 15

    class RejectCodes:
        SUCCESS = 0
        REJECT_HASH_TIMEOUT = 1
        REJECT_VERSION = 2
        REJECT_BANNED = 3
        KARMA_REGENERATION_FAILED = 4
        PERSISTED_ID_CLASH = 5
        INACTIVE_TIMEOUT = 6

    class ConversationRating:
        OKAY = 0
        BAD = 1
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
            return "[Name: %s, age: %d, gender: %d, interested_in: %d, longitude: %.2f, latitude: %.2f]" % (self.name, self.age, self.gender, self.interested_in, self.longitude, self.latitude)

    # Designed to prevent immediately rematching with person that the client skipped.
    class HistoryTracking(object):
        def __init__(self, matchDecisionDatabase, parentClient, enabled = True):
            super(Client.HistoryTracking, self).__init__()

            if matchDecisionDatabase is not None:
                assert isinstance(matchDecisionDatabase, Blocking)

            assert isinstance(parentClient, Client)

            self.parent_client = parentClient
            self.match_decision_database = matchDecisionDatabase
            self.enabled = enabled

        def addMatch(self, client):
            if not self.enabled:
                return

            assert isinstance(client, Client)
            self.match_decision_database.pushBlock(self.parent_client, client)

        def isPriorMatch(self, client):
            if not self.enabled:
                return False

            assert isinstance(client, Client)
            return not self.match_decision_database.canMatch(self.parent_client, client)


    @classmethod
    def buildDummy(cls):
        item = cls(None, ClientTcp(namedtuple('Address', ['host', 'port'], verbose=False)), None, None, None, None, None, None, None, None)
        fbId = str(uuid.uuid4())
        item.login_details = Client.LoginDetails(str(uuid.uuid4()), fbId, "Mike P", "Mike", random.randint(18, 30),
                                                        random.randint(1, 2), random.randint(1, 3),
                                                        random.randint(0, 180), random.randint(0, 90), None, None, None)
        return item

    def __init__(self, reactor, tcp, onCloseFunc, udpConnectionLinker, house, blockingDatabase, matchDecisionDatabase, karmaDatabase, paymentVerifier, persistedIdsVerifier):
        super(Client, self).__init__()
        assert isinstance(tcp, ClientTcp)
        #assert isinstance(paymentVerifier, Payments)
        assert isinstance(persistedIdsVerifier, PersistedIds)

        if blockingDatabase is not None:
            assert isinstance(blockingDatabase, Blocking)

        if karmaDatabase is not None:
            assert isinstance(karmaDatabase, KarmaLeveled)

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
        self.blocking_database = blockingDatabase

        self.last_received_data = None
        self.payment_verifier = paymentVerifier
        self.persisted_ids_verifier = persistedIdsVerifier

        self.client_matcher = task.LoopingCall(self.house.aquireMatch, self)

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
        self.match_skip_history = Client.HistoryTracking(matchDecisionDatabase, self, enabled = False)

        # Client we were speaking to in last conversation, may not still be connected.
        self.client_from_previous_conversation = None
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

                logger.debug("[STATE TRANSITION] [SUCCESS] (%s) -> (%s)" % (Client.State.parseToString(startState), Client.State.parseToString(endState)))
                return True

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

        self.tcp.sendByteBuffer(packet)

    def adviseMatchDetails(self, sourceClient, distance):
        packet = ByteBuffer()
        packet.addUnsignedInteger8(Client.TcpOperationCodes.OP_ADVISE_MATCH_INFORMATION)
        packet.addString(sourceClient.login_details.short_name)
        packet.addUnsignedInteger(sourceClient.login_details.age)
        packet.addUnsignedInteger(distance)
        packet.addUnsignedInteger(Client.WAITING_FOR_RATING_TIMEOUT)
        packet.addUnsignedInteger(KarmaLeveled.KARMA_MAXIMUM)
        packet.addUnsignedInteger(Client.ACCEPTING_MATCH_EXPIRY)
        packet.addUnsignedInteger(self.karma_rating)
        packet.addUnsignedInteger(sourceClient.karma_rating)
        packet.addString(sourceClient.login_details.card_text)
        packet.addByteBuffer(sourceClient.login_details.profile_picture)
        packet.addUnsignedInteger(sourceClient.login_details.profile_picture_orientation)
        self.transitionState(Client.State.MATCHING, Client.State.ACCEPTING_MATCH)


        self.cancelAcceptingMatchExpiry()
        logger.debug("Scheduled new accepting match expiry for client [%s] in [%s] seconds" % (self, Client.ACCEPTING_MATCH_EXPIRY))
        self.accepting_match_expiry_action = self.reactor.callLater(Client.ACCEPTING_MATCH_EXPIRY, self.doSkipTimedOut)

        self.tcp.sendByteBuffer(packet)

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

    def notifySocialInformationShared(self, ackBack = False):
        packet = ByteBuffer()
        packet.addUnsignedInteger8(Client.TcpOperationCodes.OP_SHARE_SOCIAL_INFORMATION)
        if (ackBack):
            packet.addUnsignedInteger8(0)
        else:
            packet.addUnsignedInteger8(1)
        self.tcp.sendByteBuffer(packet)

    def shareSocialInformationWith(self, destinationClient):
        assert isinstance(destinationClient, Client)

        # If both shared calling cards with each other, then at end of conversation will not get a chance to rate,
        # will skip straight to the calling cards screen, but logically if they shared calling card information with each
        # other then they probably do like each other.
        #
        # Note: this will come in mid conversation, even if the conversation isn't over. Client won't see their
        # karma increase during conversation, so this is okay.
        destinationClient.handleRating(Client.ConversationRating.GOOD)

        destinationClient.tcp.sendByteBuffer(self.social_share_information_packet)


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
        self.client_matcher.start(0.5)

        # don't need this anymore.
        self.udp_connection_linker = None

        logger.debug("Client UDP stream activated, client is fully connected")

    def onConnectionMade(self):
        pass

    # Closes the TCP socket, triggering indirectly onDisconnect to be called.
    def closeConnection(self):
        self.cancelAcceptingMatchExpiry()
        self.connection_status = Client.ConnectionStatus.NOT_CONNECTED
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

        logger.debug("(Full details) Login processed with details, udp hash: [%s], full name: [%s], short name: [%s], age: [%d], gender [%d], interested in [%d], GPS: [(%d,%d)], Karma [%d]" % (self.udp_hash, fullName, shortName, age, gender, interestedIn, longitude, latitude, self.karma_rating))
        logger.info("Login processed with udp hash: [%s]; identifier: [%s/%d]; karma: [%d]" % (self.udp_hash, shortName, age, self.karma_rating))

        return Client.RejectCodes.SUCCESS, self.udp_hash, karmaRegenerationReceipt, None

    def buildRejectPacket(self, rejectCode, dataString, magnitude=None, expiryTime=None, response=None):
        if response is None:
            response = ByteBuffer()

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

    def doSkip(self):
        logger.debug("Client [%s] asked to skip person, honouring request" % self)
        otherClient = self.house.releaseRoom(self, self.house.disconnected_skip)

        self.cancelAcceptingMatchExpiry()

        # Record that we skipped this client, so that we don't rematch immediately.
        if otherClient is not None:
            assert isinstance(otherClient, Client)
            self.match_skip_history.addMatch(otherClient)
            self.setToWaitForRatingOfPreviousConversation(otherClient)

        # The timeout on accepting a match will clear out the other client.
        # We don't want their screen updating in response to our transition.
        self.transitionState(Client.State.MATCHED, Client.State.MATCHING)
        self.transitionState(Client.State.ACCEPTING_MATCH, Client.State.MATCHING)


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
            # When in accepting match mode, we may want to report/block a client, this block below facilitates this,
            # by finding our match. We check (within the house lock) that we are in 'accepting match' mode still, to
            # avoid race conditions.
            forceSkip = False
            if self.client_from_previous_conversation is None:
                self.client_from_previous_conversation = self.house.getCurrentMatchOfClient(self, requiredState=Client.State.ACCEPTING_MATCH)
                if self.client_from_previous_conversation is not None:
                    self.client_from_previous_conversation.client_from_previous_conversation = self
                    forceSkip = True
                    logger.debug("Retrieved match during ACCEPTING_MATCH stage, [%s] has blocked [%s]" % (self, self.client_from_previous_conversation))
                else:
                    logger.debug("Failed to retrieve match during ACCEPTING_MATCH stage, client block request failed [%s]" % self)

            if self.client_from_previous_conversation is None:
                logger.debug("No previous conversation to rate")
                return

            rating = packet.getUnsignedInteger8()
            self.setRatingOfOtherClient(rating)

            if forceSkip:
                self.doSkip()

        elif opCode == Client.TcpOperationCodes.OP_PERM_DISCONNECT:
            logger.debug("Client [%s] has permanently disconnected with immediate impact" % self)
            self.house.releaseRoom(self, self.house.disconnected_permanent)
            self.closeConnection()
        elif opCode == Client.TcpOperationCodes.OP_SHARE_SOCIAL_INFORMATION_PAYLOAD:
            self.social_share_information_packet = packet
            self.house.shareSocialInformation(self)
        elif opCode == Client.TcpOperationCodes.OP_ACCEPTED_CONVERSATION:
            self.clearInactivityCounter()
            if not self.house.onAcceptConversation(self):
                self.doSkip()
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
                # Important to do both at the same time so that karma is updated prior to next conversation.
                self.transitionState(Client.State.RATING_MATCH, Client.State.MATCHING)
                self.client_from_previous_conversation.transitionState(Client.State.RATING_MATCH, Client.State.MATCHING)

            self.client_from_previous_conversation = None

        self.waiting_for_rating_task = None

    def sendBanMessage(self, magnitude, expiryTime):
        packet = self.buildRejectPacket(*self.getRejectBannedArguments(magnitude, expiryTime))
        self.tcp.sendByteBuffer(packet)
        self.closeConnection()

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
                currentKarma[0] -= 1
                if currentKarma[0] < 0:
                    currentKarma[0] = 0
                    return

                isBanned = self.karma_database.deductKarma(self, currentKarma[0])
                if not isBanned:
                    return

                sendBannedMessage()

            def incrementKarma():
                currentKarma[0] += 1
                if currentKarma[0] > KarmaLeveled.KARMA_MAXIMUM:
                    currentKarma[0] = KarmaLeveled.KARMA_MAXIMUM
                else:
                    self.karma_database.incrementKarma(self)

            if rating == Client.ConversationRating.BAD:
                logger.debug("Bad rating for client [%s] received" % self)
                deductKarma()

            elif rating == Client.ConversationRating.BLOCK:
                logger.debug("Block for client [%s] received from [%s]" % (self, self.client_from_previous_conversation))
                deductKarma()
                self.blocking_database.pushBlock(self.client_from_previous_conversation, self)
            elif rating == Client.ConversationRating.GOOD:
                logger.debug("Good rating for client [%s] received" % self)
                incrementKarma()

            elif rating == Client.ConversationRating.OKAY:
                logger.debug("Okay rating for client [%s] received" % self)
            elif rating == Client.ConversationRating.AUDIT:
                logger.debug("Audited client [%s] for bans" % self)
                sendBannedMessage()
            else:
                logger.debug("Invalid rating received, dropping client: %d" % rating)
                self.closeConnection()

            self.karma_rating = currentKarma[0]
        finally:
            self.house.house_lock.release()

    def auditBans(self):
        self.handleRating(Client.ConversationRating.AUDIT)

    # We need to wait for the client to send a rating, indicating how they felt about their previous conversation.
    def setToWaitForRatingOfPreviousConversation(self, clientFromPreviousConversation):
        if self.client_from_previous_conversation is not None:
            return

        self.house.house_lock.acquire()
        try:
            if self.approved_match:
                self.transitionState(Client.State.ACCEPTING_MATCH, Client.State.MATCHING)

            if not self.transitionState(Client.State.MATCHED, Client.State.RATING_MATCH):
                return
        finally:
            self.house.house_lock.release()

        self.client_from_previous_conversation = clientFromPreviousConversation
        self.waiting_for_rating_task = self.reactor.callLater(Client.WAITING_FOR_RATING_ABSOLUTE_TIMEOUT, self._onWaitingForRatingTimeout)
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

        if not client.state == Client.State.MATCHING:
            return False

        if client.connection_status != Client.ConnectionStatus.CONNECTED:
            return False

        isPriorMatch = self.match_skip_history.isPriorMatch(client)
        result = not isPriorMatch
        if result:
            # No need to check both sides in this call, since we already have logic in shouldMatch to
            # check both sides.
            #
            # This checks to see if users blocked each other.
            if not self.blocking_database.canMatch(self, client, checkBothSides=False):
                logger.debug("Client [%s] has blocked client [%s], not matching them" % (self, client))
                result = False

            # Clients with no karma cannot match.
            if result and self.karma_rating == 0:
                self.auditBans()
                result = False

        logger.debug("Client [%s], match successful: [%s], is prior match [%s]" % (self, result, isPriorMatch))

        return result

    # After reconnecting, a client will have a fresh client object, which may be missing some
    # state information e.g. history of recent matches, we copy this over before disposing of the old object.
    def consumeMetaState(self, client):
        assert isinstance(client, Client)
        self.match_skip_history = client.match_skip_history
        self.karma_rating = client.karma_rating
        self.has_shared_social_information = client.has_shared_social_information
        self.social_share_information_packet = client.social_share_information_packet
        self.state = client.state
        self.skipped_timed_out = client.skipped_timed_out
        self.accepting_match_expiry_action = client.accepting_match_expiry_action
        self.approved_match = client.approved_match

    # Must be protected by house lock.
    def onSuccessfulMatch(self):
        self.has_shared_social_information = False
        self.social_share_information_packet = None
        self.client_from_previous_conversation = None
        self.approved_match = False
        self.transitionState(Client.State.MATCHING, Client.State.ACCEPTING_MATCH)

    def clearKarma(self):
        self.karma_database.clearKarma(self)
        self.karma_rating = KarmaLeveled.KARMA_MAXIMUM

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