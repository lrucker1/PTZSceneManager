#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioQueue.h>
#import <AudioToolbox/AudioToolbox.h>

@interface RTSPPlayer : NSObject

/* Last decoded picture as NSImage */
@property (nonatomic, readonly) NSImage *currentImage;

/* Size of video frame */
@property (nonatomic, readonly) int sourceWidth, sourceHeight;

/* Output image size. Set to the source size by default. */
@property (nonatomic) int outputWidth, outputHeight;

/* Length of video in seconds */
@property (nonatomic, readonly) double duration;

/* Current time of video in seconds */
@property (nonatomic, readonly) double currentTime;

@property (nonatomic, retain) NSMutableArray *audioPacketQueue;
@property (nonatomic, assign) AudioQueueBufferRef emptyAudioBuffer;
@property (nonatomic, assign) int audioPacketQueueSize;

/* Initialize with movie at moviePath. Output dimensions are set to source dimensions. */
-(id)initWithVideo:(NSString *)moviePath usesTcp:(BOOL)usesTcp;

/* Read the next frame from the video stream. Returns false if no frame read (video over). */
-(BOOL)stepFrame;

/* Seek to closest keyframe near specified time */
-(void)seekTime:(double)seconds;

-(void)closeAudio;

@end
