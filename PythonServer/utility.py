import calendar
import time
import struct
import socket
import logging
from functools import wraps, partial

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

# Shuold be in UTC.
def getEpoch():
    return calendar.timegm(time.gmtime())

def getRemainingTimeOnAction(action):
    return action.getTime() - getEpoch()

def parseLogLevel(levelString):
    if 'ERROR' == levelString:
        return logging.ERROR
    elif 'WARN' == levelString:
        return logging.WARN
    elif 'INFO' == levelString:
        return logging.INFO
    elif 'DEBUG' == levelString:
        return logging.DEBUG
    else:
        return logging.INFO

# Equivalent to inet_addr.
def inet_addr(address):
    return struct.unpack("<L", socket.inet_aton(address))[0]

def htons(port):
    return socket.htons(port)

class ThrottleDecorator(object):
    def __init__(self,func,interval):
        self.func = func
        self.interval = interval
        self.last_run = 0

    def __get__(self,obj,objtype=None):
        if obj is None:
            return self.func
        return partial(self,obj)

    def __call__(self,*args,**kwargs):
        now = time.time()
        if now - self.last_run >= self.interval:
            self.last_run = now
            return self.func(*args,**kwargs)

def Throttle(interval):
    def applyDecorator(func):
        decorator = ThrottleDecorator(func=func,interval=interval)
        return wraps(func)(decorator)
    return applyDecorator

if __name__ == '__main__':
    print inet_addr("192.168.1.119")
    print htons(12341)