//
//  PTZPacketSenderCamera.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 1/16/23.
//

#import "PTZCamera.h"

NS_ASSUME_NONNULL_BEGIN

// Wraps a PTZCamera and writes its state to a PacketSender ini file.
@interface PTZPacketSenderCamera : PTZCamera

- (instancetype)initWithPrefCamera:(PTZPrefCamera *)prefCamera fileURL:(NSURL *)url;

- (void)doBackupWithParent:(PTZProgressGroup *)parent onDone:(PTZDoneBlock _Nullable)doneBlock;

@end

NS_ASSUME_NONNULL_END
