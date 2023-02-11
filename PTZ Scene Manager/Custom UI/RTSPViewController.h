//
//  RTSPViewController.h
//  RtspClient
//
//  Created by Lee Ann Rucker on 1/24/23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTSPViewController : NSViewController

- (void)openRTSPURL:(NSString *)url onDone:(void (^)(BOOL))doneBlock;
- (void)pauseVideo;
- (void)resumeVideo;
- (void)toggleVideoPaused;

- (BOOL)validateTogglePaused:(NSMenuItem *)menu;

- (void)setStaticImage:(NSImage *)image;

@end

@interface RTSPView : NSView
@property (weak) IBOutlet RTSPViewController *delegate;
@end

NS_ASSUME_NONNULL_END
