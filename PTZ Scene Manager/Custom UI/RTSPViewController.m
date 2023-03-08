//
//  RTSPViewController.m
//  RtspClient
//
//  Created by Lee Ann Rucker on 1/24/23.
//
/*
 Different cameras have different streaming URL formats, some are http instead of rtsp.  https://www.ptzcontroller.com/2022/05/control-ptz-network-camera-with-ptz-controller/
     ex: http://192.168.1.17/-wvhttp-01-/video.cgi?=vjpg:640×480:3:10000
    maybe tossing it in a webkit view will work.
  Sony
     https://community.boschsecurity.com/t5/Security-Video/Which-are-the-RTSP-request-URLs-of-the-SONY-cameras-for-getting/ta-p/22057
   rtsp://IP/media/video1
 or for Stream 2: rtsp://IP/media/video2
 or in case credentials are needed: rtsp://user:password@IP/media/video1
 */

#import "RTSPViewController.h"
#import "RTSPPlayer.h"

@interface RTSPViewController ()

@property IBOutlet NSImageView *imageView;
@property RTSPPlayer *video;
@property NSTimer *timer;
@property NSString *videoURLString;
@property BOOL ended;
@property BOOL paused;
@property BOOL hidden;
@property dispatch_queue_t videoQueue;

- (void)viewDidHide;
- (void)viewDidUnhide;

@end

@implementation RTSPViewController

- (void)openRTSPURL:(NSString *)urlString onDone:(void (^)(BOOL))doneBlock {
    if (urlString == nil) {
        if (doneBlock) {
            doneBlock(NO);
        }
        return;
    }
    // DEBUG urlString = @"rtsp://wowzaec2demo.streamlock.net/vod/mp4:BigBuckBunny_115k.mp4";
    NSString *name = [NSString stringWithFormat:@"cameraQueue_0x%p", self];
    _videoQueue = dispatch_queue_create([name UTF8String], NULL);
    self.videoURLString = urlString;
    [self startVideo:doneBlock];
}

- (void)startVideo:(void (^)(BOOL))doneBlock {
    NSSize size = self.imageView.frame.size;
    dispatch_async(_videoQueue, ^{
        self.video = [[RTSPPlayer alloc] initWithVideo:self.videoURLString usesTcp:YES];
        if (self.video != nil) {
            self.ended = NO;
            self.video.outputWidth = size.width;
            self.video.outputHeight = size.height;
            [self.video seekTime:0.0];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self resumeVideo];
            });
        }
        if (doneBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                doneBlock(self.video != nil);
            });
        }
    });
}

- (BOOL)hasVideo {
    return self.video != nil;
}

- (void)timerUpdate:(NSTimer *)timer {
    NSSize size = self.imageView.frame.size;
    dispatch_async(self.videoQueue, ^{
        // async because stepFrame can be slow.
        self.video.outputWidth = size.width;
        self.video.outputHeight = size.height;
        if (![self.video stepFrame]) {
            [timer invalidate];
            self.timer = nil;
            self.ended = YES;
            return;
        }
        if (!self.paused) {
            // Generate the image now, then set it on the main thread.
            NSImage *image = self.video.currentImage;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.imageView.image = image;
            });
        };
    });
}

- (void)stopTimer {
    [self.timer invalidate];
    self.timer = nil;
}

- (void)startTimer {
    if (!self.paused && self.video != nil) {
        // We could ask the camera what its shutter speed is.
        self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0/30 target:self selector:@selector(timerUpdate:) userInfo:nil repeats:YES];
        [self.timer fire];
    }
}

- (void)pauseVideo {
    self.paused = YES;
    [self stopTimer];
}

- (void)resumeVideo {
    self.paused = NO;
    [self startTimer];
}

- (void)toggleVideoPaused {
    if (self.ended) {
        [self startVideo:nil];
    } else if (self.paused) {
        [self resumeVideo];
    } else {
        [self pauseVideo];
    }
}

// Start and stop video without changing self.paused.
- (void)viewDidHide {
    self.hidden = YES;
    [self stopTimer];
}
- (void)viewDidUnhide {
    self.hidden = NO;
    [self startTimer];
}

- (BOOL)validateTogglePaused:(NSMenuItem *)menu {
    BOOL hasVideo = (self.video != nil);
    if (self.ended) {
        menu.title = NSLocalizedString(@"Restart Video", @"Restart video menu item");
    } else if (self.paused && hasVideo) {
        menu.title = NSLocalizedString(@"Resume Video", @"Resume video menu item");
    } else {
        menu.title = NSLocalizedString(@"Pause Video", @"Pause video menu item");
    }
    return hasVideo;
}

- (void)setStaticImage:(NSImage *)image {
    if (self.video != nil && !self.paused && image != nil) {
        [self pauseVideo];
    }
    self.imageView.image = image;
}

@end

@implementation RTSPView
- (void)viewDidHide {
    [self.delegate viewDidHide];
}
- (void)viewDidUnhide {
    [self.delegate viewDidUnhide];
}

@end
