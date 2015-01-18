# Echo server program
import socket
import sys

HOST = None    # Symbolic name meaning all available interfaces
PORT = 12340              # Arbitrary non-privileged port
s = None
for res in socket.getaddrinfo(HOST, PORT, socket.AF_UNSPEC,
                              socket.SOCK_STREAM, 0, socket.AI_PASSIVE):
    af, socktype, proto, canonname, sa = res
    try:
        s = socket.socket(af, socktype, proto)
    except socket.error as msg:
        s = None
        continue
    try:
        s.bind(sa)
        s.listen(1)
    except socket.error as msg:
        s.close()
        s = None
        continue
    break
if s is None:
    print 'could not open socket'
    sys.exit(1)
conn, addr = s.accept()
print 'Connected by', addr
while True:
    data = conn.recv(1024*128)
    if not data:
        print "done!"
        break
    print "data received, len: %s" % len(data)
    conn.send(data)
conn.close()