__author__ = 'pryormic'

from twisted.internet import threads
import requests
import logging
from client import Client
from byte_buffer import ByteBuffer
import base64

logger = logging.getLogger(__name__)

# Attempt to verify against production first, and then if that fails, verify against the test environment.
class PaymentsEx(object):
    def __init__(self, maxLiveCount):
        super(PaymentsEx, self).__init__()

        self.payments_uat = Payments(maxLiveCount, "https://sandbox.itunes.apple.com/verifyReceipt", None)
        self.payments_prod = Payments(maxLiveCount, "https://buy.itunes.apple.com/verifyReceipt", (21007, self.payments_uat.pushEvent))

        self.pushEvent = self.payments_prod.pushEvent


class Payments(object):
    def __init__(self, maxLiveCount, urlForVerification, errorRedirectMapping):
        super(Payments, self).__init__()
        # Requests which are waiting but not actioned yet.
        self.live_count = 0
        self.max_live_count = maxLiveCount

        self.httpSession = requests.Session()
        self.url_for_verification = urlForVerification

        if errorRedirectMapping is not None:
            code, redirectFunc = errorRedirectMapping
        else:
            code = None
            redirectFunc = None

        self.error_code_to_redirect = code
        self.error_redirect_func = redirectFunc

    def _doPushEvent(self, transactionToVerify, client):
        assert isinstance(transactionToVerify, ByteBuffer)
        assert isinstance(client, Client)

        transactionToVerify = base64.b64encode(transactionToVerify.buffer)

        return self.httpSession.post(self.url_for_verification, json={'receipt-data' : transactionToVerify})

    def onTransactionSuccess(self, client, udpHash):
        client.clearKarma()
        client.onLoginSuccess(udpHash)

    def onTransactionFailure(self, client, statusCode):
        if statusCode == 21000:
            rejectReason = "The App Store could not read the JSON we provided"
        elif statusCode == 21002:
            rejectReason = "The data in the receipt-data property was malformed or missing"
        elif statusCode == 21003:
            rejectReason = "The receipt could not be authenticated"
        elif statusCode == 21004:
            rejectReason = "The shared secret we provided does not match the shared secret on file for our account."
        elif statusCode == 21005:
            rejectReason = "The Apple receipt server is not currently available."
        elif statusCode == 21006:
            rejectReason = "This receipt is valid but the subscription has expired."
        elif statusCode == 21007:
            rejectReason = "The receipt is from the test environment, but it was sent to the production environment for verification"
        elif statusCode == 21008:
            rejectReason = "This receipt is from the production environment, but it was sent to the test environment for verification"
        elif statusCode == -1:
            rejectReason = "Hologram server is currently under high load"
        elif statusCode == -2:
            rejectReason = "Bad HTTP response from Apple payment server"
        else:
            rejectReason = "Unknown"

        client.onLoginFailure(Client.RejectCodes.KARMA_REGENERATION_FAILED, "Karma regeneration payment could not be verified; please contact customer support.\n\n(%d) %s." % (statusCode, rejectReason))

    def _onEventCompletion(self, result, transaction, client, udpHash):
        self.live_count-=1


        if result.status_code == 200:
            jsonResponse = result.json()
            verificationStatus = jsonResponse.get('status')
            if verificationStatus is None:
                self.onTransactionFailure(client, -2)
                return

            if verificationStatus != 0:
                if verificationStatus == self.error_code_to_redirect:
                    logger.debug("Redirecting status code = %d" % verificationStatus)
                    self.error_redirect_func(transaction, client, udpHash)
                    return

                self.onTransactionFailure(client, verificationStatus)
                return

            logger.debug("Successfully validated transaction: [%s] (live count = %d)" % (result.reason, self.live_count))
            self.onTransactionSuccess(client, udpHash)
        else:
            logger.error("Failed to validate transaction status code [%d]: [%s] (live count = %d)" % (result.status_code, result.reason, self.live_count))
            self.onTransactionFailure(client, -2)


    def pushEvent(self, transactionToVerify, client, udpHash):
        if self.live_count >= self.max_live_count:
            logger.error("Failed to push analytics event, too many in progress requests (%d of max %d)" % (self.live_count, self.max_live_count))
            self.onTransactionFailure(client, -1)
            return

        self.live_count+=1
        item = threads.deferToThread(lambda: self._doPushEvent(transactionToVerify, client))
        item.addCallback(lambda code: self._onEventCompletion(code, transactionToVerify, client, udpHash))
        logger.debug("Payments event pushed, live count is %d" % self.live_count)



