//
//  PSMOBSWebSocketController.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/26/23.
//
// Credit: https://github.com/dhbaird/easywsclient
// Credit: https://stackoverflow.com/questions/69051106/c-or-c-websocket-client-working-example

#import "PSMOBSWebSocketController.h"
#import "PTZPrefCamera.h"
#include "easywsclient.hpp"
#include <iostream>
#include <string>
#include <memory>
#include <mutex>
#include <deque>
#include <thread>
#include <chrono>
#include <atomic>
#import <PTZ_Scene_Manager-Swift.h>

#import "pixman.h"

#define EPSILON (1.0f)
#define isCloseEnough(x,y)     (fabs((x) - (y)) <= EPSILON)

NSString *PSMOBSCurrentSourceDidChangeNotification = @"PSMOBSCurrentSourceDidChangeNotification";
NSString *PSMOBSSessionIsReady = @"PSMOBSSessionDidBegin";
NSString *PSMOBSSessionDidEnd = @"PSMOBSSessionDidEnd";
NSString *PSMOBSSessionAuthorizationFailedKey = @"PSMOBSSessionAuthorizationFailedKey";
NSString *PSMOBSAutoConnect = @"OBSAutoConnect";
NSString *PSMOBSURLString = @"OBSURLString";
NSString *PSMOBSAccountName = @"OBSAccountName";
NSString *PSMOBSGetSourceSnapshotNotification = @"PSMOBSGetSourceSnapshotNotification";
NSString *PSMOBSImageDataKey = @"PSMOBSImageDataKey";
NSString *PSMOBSSourceNameKey = @"PSMOBSSourceNameKey";
NSString *PSMOBSSnapshotIndexKey = @"PSMOBSSnapshotIndexKey";
NSString *PSMOBSGetVideoSourceNamesNotification = @"PSMOBSGetVideoSourceNamesNotification";
NSString *PSMOBSVideoSourcesKey = @"PSMOBSVideoSourcesKey";

static NSString *PSMOBSBundleID = @"com.obsproject.obs-studio";

// a simple, thread-safe queue with (mostly) non-blocking reads and writes
// Yes, this could probably be replaced by dispatch_queue code.
namespace non_blocking {
template <class T>
class Queue {
    mutable std::mutex m;
    std::deque<T> data;
public:
    void push(T const &input) {
        std::lock_guard<std::mutex> L(m);
        data.push_back(input);
    }

    bool pop(T &output) {
        std::lock_guard<std::mutex> L(m);
        if (data.empty())
            return false;
        output = data.front();
        data.pop_front();
        return true;
    }
};
}

/* Don't use GetSourceActive. The Multiview counts as a "dialog" in "When an input is showing, [videoShowing] means it's being shown by the preview or a dialog.", making it pretty much useless.
 */

/*
 Hello (OpCode 0)
 Identify (OpCode 1)
 Identified (OpCode 2)
 Reidentify (OpCode 3)
 Event (OpCode 5)
 Request (OpCode 6)
 RequestResponse (OpCode 7)
 RequestBatch (OpCode 8)
 RequestBatchResponse (OpCode 9)
 */
typedef enum  {
    Op_Hello = 0,
    Op_Identify = 1,
    Op_Identified = 2,
    Op_Reidentify = 3,
    Op_Event = 5,
    Op_Request = 6,
    Op_RequestResponse = 7,
    Op_RequestBatch = 8,
    Op_RequestBatchResponse = 9
} OpCode;

/*
 
 EventSubscription::None
 EventSubscription::General
 EventSubscription::Config
 EventSubscription::Scenes
 EventSubscription::Inputs
 EventSubscription::Transitions
 EventSubscription::Filters
 EventSubscription::Outputs
 EventSubscription::SceneItems
 EventSubscription::MediaInputs
 EventSubscription::Vendors
 EventSubscription::Ui
 EventSubscription::All
 EventSubscription::InputVolumeMeters
 EventSubscription::InputActiveStateChanged
 EventSubscription::InputShowStateChanged
 EventSubscription::SceneItemTransformChanged
 */
typedef enum {
    ES_None = 0,
    ES_General = (1 << 0),
    ES_Config = (1 << 1),
    ES_Scenes = (1 << 2),
    ES_Inputs = (1 << 3),
    ES_Transition = (1 << 4),
    ES_Filters = (1 << 5),
    ES_Outputs = (1 << 6),
    ES_SceneItems = (1 << 7),
    ES_MediaInputs = (1 << 8),
    ES_Vendors = (1 << 9),
 // All non-high-volume events. (General | Config | Scenes | Inputs | Transitions | Filters | Outputs | SceneItems | MediaInputs | Vendors | Ui)
    
} EventSubscription;

typedef enum {
    OBSStateWaitingToConnect = 0,
    OBSStateWaitingForAuthorization,
    OBSStateIdentified,
    OBSStateDisconnected,
} OBSState;

@interface PSMOBSWebSocketController () {
    non_blocking::Queue<std::string> outgoing;
    non_blocking::Queue<std::string> incoming;
    dispatch_queue_t socketQueue;
}
@property (readwrite) BOOL connected;
@property (readwrite) BOOL isReady;
@property (readwrite) NSString *currentProgramScene, *currentPreviewScene;
@property (readwrite) NSString *currentProgramSource, *currentPreviewSource;
@property (readwrite) NSArray *currentProgramSourceNames, *currentPreviewSourceNames;
@property (readwrite) CGFloat baseWidth, baseHeight;

@property NSString *command;
@property BOOL running;
@property BOOL isObservingAppLaunch;
// We don't get an error code, we just get disconnected.
@property OBSAuthType authType;
@property OBSState obsState;
// Let the delegate know which kind of attempt failed
@property BOOL authorizingWithKeychain;
@property NSString *requestId;
@property NSString *obsURLString;
@property NSURL *obsURL;
@property NSString *obsAccount;
@property NSData *obsPasswordData;
@property NSArray *videoSourceNames;

@end

@implementation PSMOBSWebSocketController

+ (instancetype)defaultController {
    static dispatch_once_t once;
    static id defaultController;
    dispatch_once(&once, ^{
        defaultController = [[self alloc] init];
    });
    return defaultController;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // A unique ID for requests when we don't care about matching request with reply.
        _requestId = [[NSUUID new] UUIDString];
        _obsAccount = @"OBSWebSocket";
        socketQueue = dispatch_queue_create("socketQueue", NULL);
        _videoSourceNames = [[NSUserDefaults standardUserDefaults] objectForKey:@"OBSVideoSourceNames"];

    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)obsIsRunning {
    NSArray *apps = [[NSWorkspace sharedWorkspace] runningApplications];
    for (NSRunningApplication *app in apps) {
        if ([app.bundleIdentifier isEqualToString:PSMOBSBundleID]) {
            return YES;
        }
    }
    return NO;
}

- (void)updateAccountInfo {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSString *urlString = [defs stringForKey:PSMOBSURLString];
    self.obsURLString = urlString;
    self.obsURL = [NSURL URLWithString:urlString];
    self.obsAccount = [defs stringForKey:PSMOBSAccountName];
    if ([self.obsAccount length] == 0) {
        self.obsAccount = @"WebSockets";
    }
}

- (void)deleteKeychainPasswords {
    [self updateAccountInfo];
    dispatch_queue_t temp = dispatch_queue_create("temp", NULL);
    dispatch_async(temp, ^() {
        [OBSAuth.shared deletePassword:self.obsURL account:self.obsAccount];
    });
}

- (void)startObservingRunningApps {
    if (!self.isObservingAppLaunch && ![self obsIsRunning]) {
        [[[NSWorkspace sharedWorkspace] notificationCenter]
         addObserver:self
         selector:@selector(onSomeApplicationDidLaunch:)
         name:NSWorkspaceDidLaunchApplicationNotification
         object:nil];
        self.isObservingAppLaunch = YES;
    }
}

- (void)stopObservingRunningApps {
    if (self.isObservingAppLaunch) {
        [[[NSWorkspace sharedWorkspace] notificationCenter]
         removeObserver:self
         name:NSWorkspaceDidLaunchApplicationNotification
         object:nil];
        self.isObservingAppLaunch = NO;
    }
}

// Called by AppDelegate. Clears the state machine, fetches latest account info.
- (void)connectToServer {
    [self updateAccountInfo];
    self.authType = OBSAuthTypeUnknown;
    self.obsState = OBSStateWaitingToConnect;
    if (self.connected) {
        return;
    }
    if ([self obsIsRunning]) {
        [self runSocketFromURL:self.obsURLString];
    } else {
        [self startObservingRunningApps];
    }
}

- (NSString *)convertToJSON:(id)dictionaryOrArrayToOutput {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionaryOrArrayToOutput
                                                       options:NSJSONWritingPrettyPrinted // Pass 0 if you don't care about the readability of the generated string
                                                         error:&error];

    if (! jsonData) {
        return nil;
    } else {
        return[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
}

- (NSNumber *)eventSubscriptions {
    return @(ES_General | ES_Scenes | ES_SceneItems);
}

- (NSString *)jsonGetRequestType:(NSString *)requestType {
    NSDictionary *dict = @{@"op":@(6),
                           @"d": @{@"requestType": requestType,
                                   @"requestId": self.requestId,
                                   @"requestData": @{}}};
    return [self convertToJSON:dict];
}

#define JSON_GET_REQUEST_TYPE(_request) \
- (NSString *)json##_request {  \
    return [self jsonGetRequestType:@#_request]; \
}

JSON_GET_REQUEST_TYPE(GetInputList)
JSON_GET_REQUEST_TYPE(GetCurrentProgramScene)
JSON_GET_REQUEST_TYPE(GetCurrentPreviewScene)
JSON_GET_REQUEST_TYPE(GetVideoSettings)

- (NSString *)jsonHelloReply {
    NSDictionary *dict = @{@"op":@(1),
                           @"d":@{@"rpcVersion":@(1),
                                  @"eventSubscriptions":self.eventSubscriptions}};
    return [self convertToJSON:dict];
}

- (NSString *)jsonHelloReplyWithAuth:(NSString *)auth {
    NSDictionary *dict = @{@"op":@(1),
                           @"d":@{@"rpcVersion":@(1),
                                  @"authentication":auth,
                                  @"eventSubscriptions":self.eventSubscriptions}};
    return [self convertToJSON:dict];
}

- (void)handleHello:(NSDictionary *)dict {
    NSDictionary *data = dict[@"d"];
    NSDictionary *auth = data[@"authentication"];
    if (auth == nil) {
        [self sendString:self.jsonHelloReply];
        return;
    }
    NSString *authResponse = nil;
    if (self.obsState != OBSStateWaitingForAuthorization) {
        self.authType = OBSAuthTypePromptAttempt;
        authResponse = [OBSAuth.shared obsSecretFromKeychain:auth url:self.obsURL account:self.obsAccount];
    };
    
    self.obsState = OBSStateWaitingForAuthorization;
    self.obsPasswordData = nil;
    if (authResponse) {
        self.authType = OBSAuthTypeKeychainAttempt;
        [self sendString:[self jsonHelloReplyWithAuth:authResponse]];
    } else {
        if (self.authType == OBSAuthTypeKeychainAttempt || self.authType == OBSAuthTypePromptFailed) {
            self.authType = OBSAuthTypePromptAttempt;
        }
        [self.delegate requestOBSWebSocketPasswordWithPrompt:self.authType onDone:^(NSString *password) {
            if ([password length] == 0) {
                return;
            }
            NSString *authResponse = [OBSAuth.shared obsSecret:auth password:password];

            if (authResponse != nil) {
                self.obsPasswordData = [password dataUsingEncoding:NSUTF8StringEncoding];
                [self sendString:[self jsonHelloReplyWithAuth:authResponse]];
            }
        }];
    }
}

- (void)handleIdentified:(NSDictionary *)dict {
    self.obsState = OBSStateIdentified;
    [self sendString:[self jsonGetInputList]];
    [self sendString:[self jsonGetCurrentProgramScene]];
    [self sendString:[self jsonGetCurrentPreviewScene]];
    [self sendString:[self jsonGetVideoSettings]];
    if (self.obsPasswordData != nil) {
        [self.delegate requestOBSWebSocketKeychainPermission:^(BOOL allowed) {
            if (!allowed) {
                self.obsPasswordData = nil;
                return;
            }
            dispatch_queue_t temp = dispatch_queue_create("temp", NULL);
            dispatch_async(temp, ^() {
                [OBSAuth.shared setPassword:self.obsPasswordData url:self.obsURL account:self.obsAccount];
                self.obsPasswordData = nil;
            });
        }];
    }
}

- (void)handleGetVideoSettings:(NSDictionary *)dict {
    self.baseHeight = [dict[@"baseHeight"] floatValue];
    self.baseWidth = [dict[@"baseWidth"] floatValue];
}

- (void)handleSourceScreenshot:(NSDictionary *)dict {
    NSString *requestID = dict[@"requestId"];
    NSDictionary *responseData = dict[@"responseData"];
    NSString *imageJsonData = responseData[@"imageData"];
    if (imageJsonData) {
        // Strip the prefix, it's not base64
        NSArray *parts = [imageJsonData componentsSeparatedByString:@","];
        NSData *data = [[NSData alloc] initWithBase64EncodedString:[parts lastObject] options:NSDataBase64DecodingIgnoreUnknownCharacters];
        if (data) {
            parts = [requestID componentsSeparatedByString:@","];
            NSString *sourceName = requestID;
            NSInteger index = -1;
            if ([parts count] == 2) {
                sourceName = [parts lastObject];
                index = [[parts firstObject] integerValue];
            }
            [[NSNotificationCenter defaultCenter]
             postNotificationName:PSMOBSGetSourceSnapshotNotification
             object:nil
             userInfo:@{PSMOBSImageDataKey : data, PSMOBSSourceNameKey : sourceName, PSMOBSSnapshotIndexKey : @(index)}];
        }
    }
}

- (NSString *)jsonGetSourceScreenshot:(NSString *)sourceName requestID:(NSString *)requestID imageWidth:(NSInteger)imageWidth {
    // options: 1920x1080 (1.777) 960x600 (1.6) 480x300 (1.6)
    // imageWidth: ">= 8, <= 4096"
    imageWidth = MAX(8, MIN(imageWidth, 4096));
    NSDictionary *dict = @{@"op":@(6),
                           @"d": @{@"requestType": @"GetSourceScreenshot",
                                   @"requestId": requestID,
                                   @"requestData": @{
                                       @"sourceName": sourceName,
                                       @"imageFormat": @"jpg",
                                       @"imageWidth":@(imageWidth)}}};
    return [self convertToJSON:dict];
}

- (NSString *)jsonGetSceneItemList:(NSString *)sceneName {
    NSDictionary *dict = @{@"op":@(6),
                           @"d": @{@"requestType": @"GetSceneItemList",
                                   @"requestId": sceneName,
                                   @"requestData": @{
                                       @"sceneName": sceneName}}};
    return [self convertToJSON:dict];
}

- (BOOL)requestSnapshotForCameraSource:(NSString *)obsSourceName index:(NSInteger)index preferredWidth:(NSInteger)width {
    if (!self.isReady) {
        return NO;
    }
    NSString *requestID = [NSString stringWithFormat:@"%ld,%@", index, obsSourceName];
    NSString *json = [self jsonGetSourceScreenshot:obsSourceName requestID:requestID imageWidth:width];
    [self sendString:json];
    return YES;
}

- (void)handleInputList:(NSDictionary *)responseData {
    NSMutableArray *array = [NSMutableArray array];
    NSArray *inputs = responseData[@"inputs"];
    for (NSDictionary *input in inputs) {
        NSString *name = input[@"inputName"];
        NSString *kind = input[@"inputKind"];
        if (name && [kind hasPrefix:@"av_capture_input"]) {
            [array addObject:name];
        }
    }
    [array sortUsingSelector:@selector(caseInsensitiveCompare:)];
    self.videoSourceNames = [NSArray arrayWithArray:array];
    [[NSUserDefaults standardUserDefaults] setObject:self.videoSourceNames forKey:@"OBSVideoSourceNames"];
    [[NSNotificationCenter defaultCenter]
     postNotificationName:PSMOBSGetVideoSourceNamesNotification
     object:nil
     userInfo:@{PSMOBSVideoSourcesKey : self.videoSourceNames}];
}

- (void)handleProgramSceneChanged:(NSDictionary *)dict {
    // GetSceneItemList
    self.currentProgramScene = dict[@"sceneName"];
    [self sendString:[self jsonGetSceneItemList:self.currentProgramScene]];
}

- (void)handlePreviewSceneChanged:(NSDictionary *)dict {
    // GetSceneItemList
    self.currentPreviewScene = dict[@"sceneName"];
    [self sendString:[self jsonGetSceneItemList:self.currentPreviewScene]];
}

- (void)handleGetCurrentProgramScene:(NSDictionary *)dict {
    // GetSceneItemList
    self.currentProgramScene = dict[@"currentProgramSceneName"];
    [self sendString:[self jsonGetSceneItemList:self.currentProgramScene]];
}

- (void)handleGetCurrentPreviewScene:(NSDictionary *)dict {
    // GetSceneItemList
    self.currentPreviewScene = dict[@"currentPreviewSceneName"];
    [self sendString:[self jsonGetSceneItemList:self.currentPreviewScene]];
}

- (void)handleGetSceneItemList:(NSDictionary *)dict {
    NSDictionary *responseData = dict[@"responseData"];
    NSString *sceneName = dict[@"requestId"];
    [self scene:sceneName didChangeItems:responseData[@"sceneItems"]];
}

- (void)handleRequestResponse:(NSDictionary *)dict {
    NSDictionary *data = dict[@"d"];
    NSString *type = data[@"requestType"];
    if ([type isEqualToString:@"GetInputList"]) {
        [self handleInputList:data[@"responseData"]];
    } else if ([type isEqualToString:@"GetVersion"]) {
        // supportedImageFormats. We use jpg, it's not going anywhere.
    } else if ([type isEqualToString:@"GetSourceScreenshot"]) {
        [self handleSourceScreenshot:data];
    } else if ([type isEqualToString:@"GetSceneItemList"]) {
        [self handleGetSceneItemList:data];
    } else if ([type isEqualToString:@"GetCurrentProgramScene"]) {
        [self handleGetCurrentProgramScene:data[@"responseData"]];
    } else if ([type isEqualToString:@"GetCurrentPreviewScene"]) {
        [self handleGetCurrentPreviewScene:data[@"responseData"]];
    } else if ([type isEqualToString:@"GetVideoSettings"]) {
        [self handleGetVideoSettings:data[@"responseData"]];
    }
}

- (void)handleEventResponse:(NSDictionary *)dict {
    NSDictionary *data = dict[@"d"];
    NSNumber *intentObj = data[@"eventIntent"];
    if (intentObj == nil) {
        return;
    }
    NSInteger intent = [intentObj integerValue];
    NSString *eventType = data[@"eventType"];
    if (intent == ES_Scenes) {
        // Ignore SceneCreated, SceneRemoved, and SceneListChanged
        if ([eventType isEqualToString:@"CurrentProgramSceneChanged"]) {
            [self handleProgramSceneChanged:data[@"eventData"]];
        } else if ([eventType isEqualToString:@"CurrentPreviewSceneChanged"]) {
            [self handlePreviewSceneChanged:data[@"eventData"]];
        }
    } else if (intent == ES_General) {
        // Ignore Vendor and Custom events.
        if ([eventType isEqualToString:@"ExitStarted"]) {
            self.running = NO;
        }
    } else if (intent == ES_SceneItems) {
        // SceneItemListReindexed does not contain an array of full SceneItems, it's just the sceneID and index. Not what we need.
        NSDictionary *eventData = data[@"eventData"];
        NSString *sceneName = eventData[@"sceneName"];
        [self sendString:[self jsonGetSceneItemList:sceneName]];
    }
}

- (void)handleJSON:(id)jsonObj {
    if (![jsonObj isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *dict = (NSDictionary *)jsonObj;
    NSNumber *opObj = dict[@"op"];
    if (opObj == nil) {
        return;
    }
    switch ([opObj integerValue]) {
        case Op_Hello:
            self.connected = YES;
            [self handleHello:dict];
            break;
        case Op_Identified:
            self.isReady = YES;
            [self handleIdentified:dict];
            [self connectionIsReady];
            break;
        case Op_Event:
            [self handleEventResponse:dict];
            break;
        case Op_RequestResponse:
            [self handleRequestResponse:dict];
            break;
        default:
            break;
    }
}

#pragma mark data parsing

- (NSArray *)visibleSourceItemNames:(NSArray *)sceneItems {
    NSMutableArray *array = [NSMutableArray array];
    pixman_region32_t region, screenRegion, diffRegion;

    pixman_region32_init(&region);
    pixman_region32_init(&diffRegion);
    pixman_region32_init_rect(&screenRegion, 0, 0, self.baseWidth, self.baseHeight);

    // Item 0 is at the bottom of the visiblity stack.
    for (NSDictionary *dict in [sceneItems reverseObjectEnumerator]) {
        if (![dict[@"inputKind"] hasPrefix:@"av_capture_input"]) {
            continue;
        }
        if ([dict[@"sceneItemEnabled"] boolValue] == NO) {
            continue;
        }
        BOOL doesFill = YES;
        NSDictionary *xform = dict[@"sceneItemTransform"];

        CGFloat height = [xform[@"height"] floatValue];
        CGFloat width = [xform[@"width"] floatValue];
        // If we can't test it, assume it fills.
        if (height > 0 && width > 0 && self.baseWidth > 0 && self.baseHeight > 0) {
            CGRect testRect = CGRectZero;
            CGFloat sourceWidth = [xform[@"sourceWidth"] floatValue];
            CGFloat sourceHeight = [xform[@"sourceHeight"] floatValue];
            CGFloat positionX = [xform[@"positionX"] floatValue];
            CGFloat positionY = [xform[@"positionY"] floatValue];
            if ([xform[@"boundsType"] isEqualToString:@"OBS_BOUNDS_NONE"]) {
                testRect = CGRectMake(positionX, positionY, width, height);
            } else {
                // TODO: This only works with topLeft origin.
                CGFloat boundsWidth = [xform[@"boundsWidth"] floatValue];
                CGFloat boundsHeight = [xform[@"boundsHeight"] floatValue];
                testRect = CGRectMake(positionX, positionY, boundsWidth, boundsHeight);
            }
            testRect = NSIntegralRect(testRect);
            CGFloat testHeight = MIN(sourceHeight, testRect.size.height);
            CGFloat testWidth = MIN(sourceWidth, testRect.size.width);
            // Do a simple fill check. If it's wider, it fills
            doesFill = (testRect.origin.x == 0) && (testRect.origin.x == 0) && isCloseEnough(sourceHeight, testHeight) && isCloseEnough(sourceWidth, testWidth);
            pixman_region32_union_rect(&region, &region, testRect.origin.x, testRect.origin.y, testRect.size.width, testRect.size.height);
            pixman_region32_subtract(&diffRegion, &screenRegion, &region);
            int rects = pixman_region32_n_rects(&diffRegion);
            if (rects == 0) {
                // Nothing left after subtracting region from screen.
                doesFill = YES;
            }
        }
        [array addObject:dict[@"sourceName"]];
        if (doesFill) {
            // Anything below a source collection that covers the screen is not visible.
            return array;
        }
    }
    return array;
}


- (void)scene:(NSString *)sceneName didChangeItems:(NSArray *)sceneItems {
    if ([sceneName isEqualToString:self.currentProgramScene]) {
        self.currentProgramSourceNames = [self visibleSourceItemNames:sceneItems];
    } else if ([sceneName isEqualToString:self.currentPreviewScene]) {
        self.currentPreviewSourceNames = [self visibleSourceItemNames:sceneItems];
    }
    [[NSNotificationCenter defaultCenter]
     postNotificationName:PSMOBSCurrentSourceDidChangeNotification
     object:nil
     userInfo:nil];
}

#pragma mark WebSocket thread

- (void)onSomeApplicationDidLaunch:(NSNotification *)note {
    //  The userInfo dictionary contains the NSWorkspaceApplicationKey key with a corresponding instance of NSRunningApplication that represents the affected app.
    if (self.connected) {
        return;
    }
    NSDictionary *dict = note.userInfo;
    NSRunningApplication *app = dict[NSWorkspaceApplicationKey];
    if ([app.bundleIdentifier isEqualToString:PSMOBSBundleID]) {
        [self runSocketFromURL:self.obsURLString];
    }
}

// WARNING! If you send anything before the identification is complete, OBS will drop you. Any user-facing methods (like the requests) need to be careful
- (void)sendString:(NSString *)str {
    outgoing.push([str UTF8String]);
}

- (void)recvString {
    dispatch_async(dispatch_get_main_queue(), ^{
        std::string s;
        if (self->incoming.pop(s)) {
            const char *msg = s.c_str();
            NSData *data = [NSData dataWithBytes:msg length:strlen(msg)];
            NSError *error;
            id msgObj = [NSJSONSerialization JSONObjectWithData:data
                             options:0
                               error:&error];
            [self handleJSON:msgObj];
        }
    });
}

- (void)connectionIsReady {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
         postNotificationName:PSMOBSSessionIsReady
         object:nil
         userInfo:nil];
    });
}

- (void)connectionDidEnd {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.connected = NO;
        self.isReady = NO;
        if (self.obsState == OBSStateWaitingForAuthorization) {
            NSLog(@"Connection ended while waiting for auth; retrying with prompt");
            if (self.authType == OBSAuthTypeKeychainAttempt) {
                self.authType = OBSAuthTypeKeychainFailed;
            } else {
                self.authType = OBSAuthTypePromptFailed;
            }
            // Try to reconnect without clearing state machine, which tells us why we are retrying.
            [self runSocketFromURL:self.obsURLString];
        } else {
            // We weren't waiting for auth, so assume a disconnect.
            self.obsState = OBSStateDisconnected;
            // Give it time to quit
            [self performSelector:@selector(startObservingRunningApps) withObject:nil afterDelay:1];
        }
        [[NSNotificationCenter defaultCenter]
             postNotificationName:PSMOBSSessionDidEnd
             object:nil
             userInfo:@{PSMOBSSessionAuthorizationFailedKey : @(self.obsState)}];
    });
}

- (void)runSocketFromURL:(NSString *)url {
    
    dispatch_async(socketQueue, ^() {
        using easywsclient::WebSocket;
        std::unique_ptr<WebSocket> ws(WebSocket::from_url([url UTF8String]));
        if (ws == NULL) {
            NSLog(@"Unable to connect to %@", url);
            if (![self obsIsRunning]) {
                [self startObservingRunningApps];
            }
            return;
        }
        self.running = YES;
        [self stopObservingRunningApps];
        while (self.running) {
            if (ws->getReadyState() == WebSocket::CLOSED)
                break;
            std::string data;
            if (self->outgoing.pop(data))
                ws->send(data);
            ws->poll();
            ws->dispatch([&](const std::string & message) {
                self->incoming.push(message);
                [self recvString];
            });
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        ws->close();
        ws->poll();
        [self connectionDidEnd];
    });
}

@end
