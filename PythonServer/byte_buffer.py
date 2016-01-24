import struct

__author__ = 'pryormic'

import unittest
from utility import DataConstants

class ByteBuffer(object):
    def __init__(self):
        super(ByteBuffer, self).__init__()
        self.buffer = bytearray()
        self._used_size = 0
        self._cursor_position = 0

    @classmethod
    def buildFromIterable(cls, theString):
        obj = cls()
        obj.buffer = bytearray(theString)
        obj._used_size = obj.memory_size
        obj._cursor_position = 0
        return obj

    @classmethod
    def buildFromByteBuffer(cls, theByteBuffer):
        assert isinstance(theByteBuffer, ByteBuffer)
        obj = cls()
        obj.buffer = bytearray(theByteBuffer.buffer)
        obj._used_size = obj._used_size
        obj._cursor_position = theByteBuffer.cursor_position
        return obj

    @property
    def used_size(self):
        return self._used_size

    def increaseUsedSize(self, amount):
        self.used_size = self.used_size + amount

    @used_size.setter
    def used_size(self, newUsedSize):
        self._used_size = newUsedSize
        self.enforceBounds()

    @property
    def cursor_position(self):
        return self._cursor_position

    @cursor_position.setter
    def cursor_position(self, newCursorPosition):
        self.increaseMemorySize(newCursorPosition)
        if newCursorPosition > self.used_size:
            self.used_size = newCursorPosition
        self._cursor_position = newCursorPosition


    @property
    def memory_size(self):
        return len(self.buffer)

    @memory_size.setter
    def memory_size(self, newSize):
        self.setMemorySize(newSize, True)

    def increaseMemorySize(self, size):
        if size > self.memory_size:
            self.memory_size = size


    def setMemorySize(self, newSize, retainContents):
        if newSize == self.memory_size:
            return

        if retainContents:
            amountToCopy = len(self.buffer)
            if amountToCopy > newSize:
                amountToCopy = newSize
        else:
            amountToCopy = 0

        self.old_buffer = self.buffer
        self.buffer = bytearray(newSize)
        if amountToCopy > 0:
            self.buffer[0:amountToCopy] = self.old_buffer

        self.enforceBounds()

    def getUnreadDataFromCursor(self):
        return self.used_size - self.cursor_position


    def enforceBounds(self):
        if self._used_size > self.memory_size:
            self.memory_size = self._used_size

        if self.cursor_position > self._used_size:
            self.cursor_position = self._used_size

    def moveCursorForwards(self, amount):
        self.cursor_position += amount

    def addValueAtPosition(self, value, startPosition, valueDataSize):
        endPosition = startPosition + valueDataSize
        self.increaseMemorySize(endPosition)
        self.buffer[startPosition:endPosition] = value
        return endPosition

    def addValue(self, value, valueDataSize):
        self.cursor_position = self.addValueAtPosition(value, self.cursor_position, valueDataSize)

    def addUnsignedInteger(self, data):
        self.addValue(struct.pack(DataConstants.ULONG_FORMAT, data), DataConstants.ULONG_SIZE)

    def addUnsignedInteger8(self, data):
        self.addValue(struct.pack(DataConstants.UBYTE_FORMAT, data), DataConstants.UBYTE_SIZE)

    def getValueAtPosition(self, startPosition, valueDataSize):
        endPosition = startPosition + valueDataSize
        if endPosition > self.used_size:
            return endPosition

        return endPosition, self.buffer[startPosition:endPosition]

    def getValue(self, valueDataSize):
        self.cursor_position, value = self.getValueAtPosition(self.cursor_position, valueDataSize)
        return value

    def getUnsignedIntegerFromData(self, data):
        return struct.unpack(DataConstants.ULONG_FORMAT, data)[0]

    def getUnsignedIntegerFromData8(self, data):
        return struct.unpack(DataConstants.UBYTE_FORMAT, data)[0]

    def getUnsignedInteger(self):
        rawData = self.getValue(DataConstants.ULONG_SIZE)
        return self.getUnsignedIntegerFromData(rawData)

    def getUnsignedIntegerAtPosition(self, position):
        endPosition, rawData = self.getValueAtPosition(position, DataConstants.ULONG_SIZE)
        return self.getUnsignedIntegerFromData(rawData)

    def getUnsignedInteger8(self):
        rawData = self.getValue(DataConstants.UBYTE_SIZE)
        return self.getUnsignedIntegerFromData8(rawData)

    def getUnsignedIntegerAtPosition8(self, position):
        endPosition, rawData = self.getValueAtPosition(position, DataConstants.UBYTE_SIZE)
        return self.getUnsignedIntegerFromData8(rawData)

    def addVariableLengthData(self, data, dataSize, includePrefix = True):
        newSize = self.cursor_position + dataSize
        if includePrefix:
            newSize += DataConstants.ULONG_SIZE
        self.increaseMemorySize(newSize)
        if includePrefix:
            self.addUnsignedInteger(dataSize)

        self.buffer[self.cursor_position:newSize] = data
        self.moveCursorForwards(dataSize)

    def addByteBuffer(self, sourceBuffer, includePrefix = True):
        assert isinstance(sourceBuffer, ByteBuffer)
        self.addVariableLengthData(sourceBuffer.buffer, sourceBuffer.used_size, includePrefix)

    def addString(self, theString):
        assert isinstance(theString, basestring)
        self.addVariableLengthData(theString, len(theString))

    def getVariableLengthData(self, dataHandlerFunc, dataSize):
        if dataSize == 0:
            prefixSize = DataConstants.ULONG_SIZE
            if self.getUnreadDataFromCursor() < prefixSize:
                return

            dataSize = self.getUnsignedIntegerAtPosition(self.cursor_position)
        else:
            prefixSize = 0

        if self.getUnreadDataFromCursor() < prefixSize + dataSize:
            return
        self.cursor_position += prefixSize

        result = dataHandlerFunc(self.buffer[self.cursor_position:], dataSize)
        self.cursor_position += dataSize
        return result

    def getStringWithLength(self, length):
        def handlerFunc(theBuffer, dataSize):
            return "".join(map(chr, theBuffer[:dataSize]))

        return self.getVariableLengthData(handlerFunc, length)

    def convertToString(self):
        old_cursor = self.cursor_position
        self.cursor_position = 0
        a = self.getStringWithLength(self.used_size)
        self.cursor_position = old_cursor
        return a


    def getString(self):
        return self.getStringWithLength(0)

    def getByteBufferWithLength(self, length):
        def handlerFunc(theBuffer, dataSize):
            return ByteBuffer.buildFromIterable(theBuffer[:dataSize])

        return self.getVariableLengthData(handlerFunc, length)

    def getByteBuffer(self):
        return self.getByteBufferWithLength(0)


class ByteBufferTest(unittest.TestCase):
    def testTheBasics(self):
        a = ByteBuffer()
        a.addString("Hello world")

        self.assertEquals(a.used_size, 15)
        self.assertEquals(a.memory_size, 15)
        self.assertEquals(a.cursor_position, 15)

        a.addUnsignedInteger(1234)

        self.assertEquals(a.used_size, 19)
        self.assertEquals(a.memory_size, 19)
        self.assertEquals(a.cursor_position, 19)

        a.addString("WOW Hello Universe!")

        self.assertEquals(a.used_size, 42)
        self.assertEquals(a.memory_size, 42)
        self.assertEquals(a.cursor_position, 42)

        a.cursor_position = 0
        self.assertEquals(a.used_size, 42)
        self.assertEquals(a.memory_size, 42)
        self.assertEquals(a.cursor_position, 0)

        b = a.getString()
        self.assertEquals(b, "Hello world")

        b = a.getUnsignedInteger()
        self.assertEquals(b, 1234)

        b = a.getString()
        self.assertEquals(b, "WOW Hello Universe!")

        self.assertEquals(a.used_size, 42)
        self.assertEquals(a.memory_size, 42)
        self.assertEquals(a.cursor_position, 42)


