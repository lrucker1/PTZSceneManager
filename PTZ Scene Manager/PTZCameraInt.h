//
//  PTZCameraInt.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 1/16/23.
//

#ifndef PTZCameraInt_h
#define PTZCameraInt_h
#import "PTZCamera.h"

typedef void (^PTZCommandBlock)(void);

extern const NSString *PTZProgressStartKey;
extern const NSString *PTZProgressEndKey;

@interface PTZCamera ()

@property dispatch_queue_t cameraQueue;
@property BOOL isExportingHomeScene;

- (VISCAInterface_t*)pIface;
- (VISCACamera_t*)pCamera;

// The zero-based camera values, mapped from the user-friendly properties
- (NSInteger)colorTempIndex;
- (NSInteger)hueIndex;
- (NSInteger)saturationIndex;
- (NSInteger)autofocusIndex;
- (NSInteger)bwModeIndex;

- (void)loadCameraWithCompletionHandler:(PTZCommandBlock)handler;
- (void)callDoneBlock:(PTZDoneBlock)doneBlock success:(BOOL)success;

@end

#endif /* PTZCameraInt_h */
