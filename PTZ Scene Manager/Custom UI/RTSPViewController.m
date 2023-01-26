//
//  RTSPViewController.m
//  RtspClient
//
//  Created by Lee Ann Rucker on 1/24/23.
//

#import "RTSPViewController.h"
#import "RTSPPlayer.h"

@interface RTSPViewController ()

@property IBOutlet NSImageView *imageView;
@property RTSPPlayer *video;
@property NSTimer *timer;
@property BOOL paused;
@property dispatch_queue_t videoQueue;

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
    NSSize size = self.imageView.frame.size;
    dispatch_async(_videoQueue, ^{
        self.video = [[RTSPPlayer alloc] initWithVideo:urlString usesTcp:YES];
        if (self.video != nil) {
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

- (void)timerUpdate:(NSTimer *)timer {
    dispatch_async(self.videoQueue, ^{
        // async because stepFrame can be slow.
        if (![self.video stepFrame]) {
            [timer invalidate];
            self.timer = nil;
            self.paused = YES;
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

- (void)pauseVideo {
    self.paused = YES;
    [self.timer invalidate];
    self.timer = nil;
}

- (void)resumeVideo {
    self.paused = NO;
    if (self.video != nil) {
        // We could ask the camera what its shutter speed is.
        self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0/30 target:self selector:@selector(timerUpdate:) userInfo:nil repeats:YES];
        [self.timer fire];
    }
}

- (void)toggleVideoPaused {
    if (self.paused) {
        [self resumeVideo];
    } else {
        [self pauseVideo];
    }
}

- (BOOL)validateTogglePaused:(NSMenuItem *)menu {
    BOOL hasVideo = (self.video != nil);
    if (self.paused && hasVideo) {
        menu.title = NSLocalizedString(@"Resume Video", @"Resume video menu item");
    } else {
        menu.title = NSLocalizedString(@"Pause Video", @"Resume video menu item");
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
