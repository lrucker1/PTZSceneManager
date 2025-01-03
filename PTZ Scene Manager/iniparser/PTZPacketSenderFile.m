//
//  PTZPacketSenderFile.m
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 1/15/23.
//

#import "PTZPacketSenderFile.h"

/*
 json["name"] = packetList[i].name;
 JSONSTR(hexString);
 JSONSTR(fromIP);
 JSONSTR(toIP);
 JSONSTR(errorString);
 JSONNUM(port);
 JSONNUM(fromPort);
 JSONSTR(tcpOrUdp);
 JSONNUM(sendResponse);
 JSONSTR(requestPath);
 JSONSTR(repeat);
 json["asciistring"] = QString(packetList[i].asciiString().toLatin1().toBase64());

 */
/*
 [CAM_AE%20Bright]
 fromIP=
 fromPort=0
 hexString=81 01 04 39 0d ff
 name=CAM_AE Bright
 port=5678
 repeat=@Variant(\0\0\0\x87\0\0\0\0)
 requestPath=
 sendResponse=0
 tcpOrUdp=TCP
 timestamp="Sun, 15 Jan 2023 11:43:44"
 toIP=192.168.100.88
 */
@implementation PTZPacketSenderFile

@end
