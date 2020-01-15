// Copyright 2020 Lionell Yip. All rights reserved.

#import "TusPlugin.h"

static NSString *const CHANNEL_NAME = @"io.tus.flutter_service";
static NSString *const InvalidParameters = @"Invalid parameters";
static NSString* const FILE_NAME = @"tuskit_example";

@interface TusPlugin()

@property (strong, nonatomic) NSURL *applicationSupportUrl;
@property (strong, atomic) NSDictionary *tusSessions;
@property (strong, nonatomic) TUSUploadStore *tusUploadStore;
@property (strong, nonatomic) NSURLSessionConfiguration *sessionConfiguration;
@property(nonatomic, retain) FlutterMethodChannel *channel;

@end

@implementation TusPlugin
-(instancetype) init {
    self = [super init];
    if(self) {
        self.applicationSupportUrl = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
        self.tusUploadStore = [[TUSFileUploadStore alloc] initWithURL:[self.applicationSupportUrl URLByAppendingPathComponent:FILE_NAME]];
        self.sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
        self.sessionConfiguration.allowsCellularAccess = YES;
        self.tusSessions = [[NSMutableDictionary alloc]init];
    }

    return self;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:CHANNEL_NAME
            binaryMessenger:[registrar messenger]];
  TusPlugin* instance = [[TusPlugin alloc] init];
    instance.channel = channel;
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSDictionary *arguments = [call arguments];
    NSDictionary *options = [arguments[@"options"] isKindOfClass:[NSDictionary class]] ? arguments[@"options"] : nil;

    if ([@"getPlatformVersion" isEqualToString:call.method]) {
        result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
    }
    else if([@"initWithEndpoint" isEqualToString:call.method]) {
        NSString *endpointUrl = arguments[@"endpointUrl"];
        NSURLSessionConfiguration *localSessionConfiguration = [self.sessionConfiguration copy];
        localSessionConfiguration.allowsCellularAccess = [options[@"allowsCellularAccess"] isEqualToString:@"true"];

        [self.tusSessions setValue:[[TUSSession alloc] initWithEndpoint:[[NSURL alloc] initWithString:endpointUrl] dataStore:self.tusUploadStore sessionConfiguration:localSessionConfiguration] forKey:endpointUrl];
        for (TUSResumableUpload *upload in [[self.tusSessions valueForKey:endpointUrl] restoreAllUploads]) {
            upload.progressBlock = ^(int64_t bytesWritten, int64_t bytesTotal) {
                NSMutableDictionary *a = [[NSMutableDictionary alloc] init];
                [a setValue:[NSString stringWithFormat:@"%lld", bytesWritten] forKey:@"bytesWritten"];
                [a setValue:[NSString stringWithFormat:@"%lld", bytesTotal] forKey:@"bytesTotal"];
                [a setValue: endpointUrl forKey:@"endpointUrl"];
                [self.channel invokeMethod:@"progressBlock" arguments:a];
            };
            upload.resultBlock = ^(NSURL *fileUrl) {
                NSMutableDictionary *a = [[NSMutableDictionary alloc]init];
                [a setValue:endpointUrl forKey:@"endpointUrl"];
                [a setValue:[NSString stringWithFormat:@"%@", fileUrl.absoluteURL.path] forKey:@"resultUrl"];
                [self.channel invokeMethod:@"resultBlock" arguments:a];
            };
            upload.failureBlock = ^(NSError * _Nonnull error) {
                NSMutableDictionary *a = [[NSMutableDictionary alloc]init];
                [a setValue:[NSString stringWithFormat:@"%@", error] forKey:@"error"];
                [a setValue:endpointUrl forKey:@"endpointUrl"];
                [self.channel invokeMethod:@"failureBlock" arguments:a];
            };
        }

        [[self.tusSessions valueForKey:endpointUrl] resumeAll];

        NSMutableDictionary *inResult = [[NSMutableDictionary alloc]init];
        [inResult setValue:endpointUrl forKey:@"endpointUrl"];
        result(inResult);
    } else if ([@"createUploadFromFile" isEqualToString:call.method]) {
        NSString *endpointUrl = arguments[@"endpointUrl"];
        TUSSession *localTusSession = [self.tusSessions objectForKey:endpointUrl];
        if (localTusSession == nil ) {
            NSMutableDictionary *inResult = [[NSMutableDictionary alloc]init];
            [inResult setValue:@"invalid endpointUrl provided" forKey:@"error"];
            result(inResult);
            return;
        }

        NSString *fileUploadUrl = arguments[@"fileUploadUrl"];
        if(fileUploadUrl == nil) {
            NSMutableDictionary *inResult = [[NSMutableDictionary alloc]init];
            [inResult setValue:@"invalid fileUploadUrl provided" forKey:@"error"];
            result(inResult);
            return;
        }

        NSDictionary *headers = [arguments[@"headers"] isKindOfClass:[NSDictionary class]] ? arguments[@"headers"] : @{};
        NSDictionary *metadata = [arguments[@"metadata"] isKindOfClass:[NSDictionary class]] ? arguments[@"metadata"]  : @{};
        NSURL *uploadUrl = [arguments[@"uploadUrl"] isKindOfClass:[NSString class]] ? [[NSURL alloc]initWithString:arguments[@"uploadUrl"]] : nil;

        int retryCount = arguments[@"retry"] == nil ? -1 : [arguments[@"retry"] intValue];

        @try {
            NSURL *uploadFromFile = [NSURL fileURLWithPath:fileUploadUrl];
            TUSResumableUpload *upload = [localTusSession createUploadFromFile:uploadFromFile retry:retryCount headers:headers metadata:metadata ];

            upload.progressBlock = ^(int64_t bytesWritten, int64_t bytesTotal) {
                NSMutableDictionary *a = [[NSMutableDictionary alloc] init];
                [a setValue:[NSString stringWithFormat:@"%lld", bytesWritten] forKey:@"bytesWritten"];
                [a setValue:[NSString stringWithFormat:@"%lld", bytesTotal] forKey:@"bytesTotal"];
                [a setValue: endpointUrl forKey:@"endpointUrl"];
                [self.channel invokeMethod:@"progressBlock" arguments:a];
            };
            upload.resultBlock = ^(NSURL *fileUrl) {
                NSMutableDictionary *a = [[NSMutableDictionary alloc]init];
                [a setValue:endpointUrl forKey:@"endpointUrl"];
                [a setValue:[NSString stringWithFormat:@"%@", fileUrl.absoluteURL.path] forKey:@"resultUrl"];
                [self.channel invokeMethod:@"resultBlock" arguments:a];
            };
            upload.failureBlock = ^(NSError * _Nonnull error) {
                NSMutableDictionary *a = [[NSMutableDictionary alloc]init];
                [a setValue:[NSString stringWithFormat:@"%@", error] forKey:@"error"];
                [a setValue:endpointUrl forKey:@"endpointUrl"];
                [self.channel invokeMethod:@"failureBlock" arguments:a];
            };

            [upload resume];

            NSMutableDictionary *inResult = [[NSMutableDictionary alloc]init];
            [inResult setValue:@"true" forKey:@"inProgress"];
            result(inResult);
        }
        @catch (NSException *exception){
            NSMutableDictionary *inResult = [[NSMutableDictionary alloc]init];
            [inResult setValue:exception.name forKey:@"error"];
            [inResult setValue:exception.reason forKey:@"reason"];
            [inResult setValue:exception.callStackSymbols forKey:@"stack"];
            result(inResult);
        }


    }else {
      result(FlutterMethodNotImplemented);
    }
}


@end
