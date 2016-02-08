import calendar
import time
import struct
import socket

__author__ = 'pryormic'

class DataConstants:
    # Little endian, 4 bytes.
    ULONG_FORMAT = "<L"
    ULONG_SIZE = 4

    # Big endian, 4 bytes (or network byte order)
    FLOAT_FORMAT = ">f"
    FLOAT_SIZE = 4

    UBYTE_FORMAT = "B"
    UBYTE_SIZE = 1


def getEpoch():
    return calendar.timegm(time.gmtime())

def getRemainingTimeOnAction(action):
    return action.getTime() - getEpoch()


# Equivalent to inet_addr.
def inet_addr(address):
    return struct.unpack("<L", socket.inet_aton(address))[0]

def htons(port):
    return socket.htons(port)

if __name__ == '__main__':
    print inet_addr("192.168.1.119")
    print htons(12341)