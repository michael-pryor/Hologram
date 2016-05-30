//
//  NetworkOperations.h
//  MyFirstApplication
//
//  Created by Michael Pryor on 25/05/2015.
//
//

#ifndef MyFirstApplication_NetworkOperations_h
#define MyFirstApplication_NetworkOperations_h

// ****** UDP ******
#define AUDIO_ID 1
#define VIDEO_ID 2

// Try to punchthrough NAT, we send this periodically while in routing mode (through server) and also
// while in punch through mode.
//
// While routing, we send periocially peer to peer to try and setup the connection.
// While punched through, we send periodically to master server.

// We need to keep the master server connection as well, so discovery is sent down this channel
// while we are punched through. If we don't do this, particularly with 3G, we risk the route changing and
// as a result our external IP address changing, if it changes then the server won't know who we are,
// so we really need to reconnect (though there is no logic to trigger a reconnect).
#define NAT_PUNCHTHROUGH_DISCOVERY 3

// ****** TCP ******
// The master server has sent a packet containing an address to connect to,
// we will periodically fire discovery messages to try and connect.
#define NAT_PUNCHTHROUGH_ADDRESS 2

// Client disconnected from master server, but may reconnect later under same
// session.
//
// For now we should stop sending to the client via NAT punch through,
// as the address may be invalid (e.g. interface change) when the client reconnects.
#define NAT_PUNCHTHROUGH_DISCONNECT 3

// No longer interested in talking to current person, give me someone new.
#define SKIP_PERSON 4

// End point has temporarily disconnect (end point = person we are talking to) due to network issue.
#define DISCONNECT_TEMP 6

// End point has permanently disconnected (server timed them out)
#define DISCONNECT_PERM 7

// End point clicked on 'skip' so asked to move to next person.
#define DISCONNECT_SKIPPED 8

#define COMMANDER_SUCCESS 1
#define COMMANDER_FAILURE 2

#endif
