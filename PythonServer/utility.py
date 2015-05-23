import calendar
import time

__author__ = 'pryormic'

class DataConstants:
    # Little endian, 4 bytes.
    ULONG_FORMAT = "<L"
    ULONG_SIZE = 4


def getEpoch():
    return calendar.timegm(time.gmtime())

def getRemainingTimeOnAction(action):
    return action.getTime() - getEpoch()