//
//  CocoJSTerminal.m
//  CocoJS
//
//  Created by Xiliang Chen on 12-10-29.
//  Copyright (c) 2012年 Xiliang Chen. All rights reserved.
//

#import "CocoJSTerminal.h"

#import <readline/readline.h>

#import "ThoMoClientStub.h"

@interface CocoJSTerminal () <ThoMoClientDelegateProtocol>

@property BOOL firstline;

- (void)prompt:(BOOL)firstline;
- (void)threadMain;

- (void)handleInput:(NSString *)input;
- (void)uploadDirectory:(NSString *)path;
- (void)uploadFile:(NSString *)path;

@end

@implementation CocoJSTerminal {
    ThoMoClientStub *_client;
    NSCondition *_condition;
    
    NSRegularExpression *_pwdRegex;
    NSRegularExpression *_cdRegex;
    NSRegularExpression *_syncRegex;
}

+ (void)run {
    CocoJSTerminal *app = [[self alloc] init];
    
    [app run];
    
    [app release];
}

#pragma mark -

- (id)init
{
    self = [super init];
    if (self) {
        _client = [[ThoMoClientStub alloc] initWithProtocolIdentifier:@"CocoJSDebug"];
        _client.delegate = self;
        _condition = [[NSCondition alloc] init];
        
        NSError *error = nil;
        _pwdRegex = [[NSRegularExpression alloc] initWithPattern:@"^#pwd\\s*$" options:NSRegularExpressionCaseInsensitive error:&error];
        _cdRegex = [[NSRegularExpression alloc] initWithPattern:@"^#cd\\s+(\\S+)\\s*$" options:NSRegularExpressionCaseInsensitive error:&error];
        _syncRegex = [[NSRegularExpression alloc] initWithPattern:@"^#sync\\s*(\\S*)\\s*$" options:NSRegularExpressionCaseInsensitive error:&error];
        
        NSString *cwd = [[NSUserDefaults standardUserDefaults] objectForKey:@"WorkingDirectory"];
        if (cwd) {
            [[NSFileManager defaultManager] changeCurrentDirectoryPath:cwd];
        }
    }
    return self;
}

- (void)dealloc
{
    [_client stop];
    [_client release];
    
    [_condition release];
    
    [_pwdRegex release];
    [_cdRegex release];
    [_syncRegex release];
    
    [super dealloc];
}

#pragma mark -

- (void)run {
    [_client start];
    [self performSelectorInBackground:@selector(threadMain) withObject:nil];
    [[NSRunLoop mainRunLoop] run];
}

- (void)prompt:(BOOL)firstline {
    [_condition lock];
    [_condition broadcast];
    self.firstline = firstline;
    [_condition unlock];
}

- (void)threadMain {
    @autoreleasepool {
        char *line = NULL;

        for (;;) {
            [_condition lock];
            [_condition wait];
            [_condition unlock];
            BOOL firstline = self.firstline;
            const char *str = firstline ? "\r> " : "\r>> ";
            do {
                if (line) {
                    free(line);
                }
                line = readline(str);
            } while (line && line[0] == '\0');
            if (line) {
                add_history(line);
                [self handleInput:@(line)];
            } else {
                exit(EXIT_SUCCESS);
            }
        }
    }
}

- (void)handleInput:(NSString *)input {
    if ([input characterAtIndex:0] == '#') {
        BOOL found = YES;
        NSRange strRange = NSMakeRange(0, input.length);
        NSTextCheckingResult *result;
        if ((result = [_pwdRegex firstMatchInString:input options:0 range:strRange])) {
            printf("%s\n", [[[NSFileManager defaultManager] currentDirectoryPath] UTF8String]);
        } else if ((result = [_cdRegex firstMatchInString:input options:0 range:strRange])) {
            NSString *cwd = [[input substringWithRange:[result rangeAtIndex:1]] stringByExpandingTildeInPath];
            NSURL *cwdurl = [NSURL URLWithString:cwd];
            if ([[NSFileManager defaultManager] changeCurrentDirectoryPath:[cwdurl absoluteString]]) {
                printf("%s\n", [[[NSFileManager defaultManager] currentDirectoryPath] UTF8String]);
                [[NSUserDefaults standardUserDefaults] setObject:[cwdurl absoluteString] forKey:@"WorkingDirectory"];
                [[NSUserDefaults standardUserDefaults] synchronize];
            } else {
                printf("Invalid path: %s\n", [cwd UTF8String]);
            }
        } else if ((result = [_syncRegex firstMatchInString:input options:0 range:strRange])) {
            NSRange range = [result rangeAtIndex:1];
            NSString *path = (range.length == 0) ? @"." : [input substringWithRange:range];
            [self uploadDirectory:path];
        } else {
            found = NO;
        }
        
        if (found) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self prompt:self.firstline];
            });
            return;
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [_client sendToAllServers:input];
    });
}

- (void)uploadDirectory:(NSString *)path; {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    BOOL isDir;
    if (![fileManager fileExistsAtPath:path isDirectory:&isDir]) {
        printf("File not exists: %s\n", [path UTF8String]);
        return;
    }
    
    if (isDir) {
        NSDirectoryEnumerator *dirEnum = [fileManager enumeratorAtPath:path];
        
        NSString *file;
        while (file = [dirEnum nextObject]) {
            if ([[file pathExtension] isEqualToString: @"js"]) {
                [self uploadFile:file];
            }
        }
    } else {
        [self uploadFile:path];
    }
}

- (void)uploadFile:(NSString *)path {
    printf("Upload %s\n", [path UTF8String]);
    
    
    NSDictionary *dict = @{
    @"filename" : path,
    @"content" : [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]
    };
    
    [_client sendToAllServers:dict];
}

#pragma mark - ThoMoClientDelegateProtocol

- (void)client:(ThoMoClientStub *)theClient didConnectToServer:(NSString *)aServerIdString {
    printf("connect to server '%s'\n", [aServerIdString UTF8String]);
    [self prompt:YES];
}

- (void)client:(ThoMoClientStub *)theClient didDisconnectFromServer:(NSString *)aServerIdString errorMessage:(NSString *)errorMessage {
    printf("disconnect from server '%s'. %s\n", [aServerIdString UTF8String], [errorMessage UTF8String]);
}

- (void)client:(ThoMoClientStub *)theClient didReceiveData:(id)theData fromServer:(NSString *)aServerIdString {
    if ([theData isKindOfClass:[NSString class]]) {
        printf("\r%s\n%s", [theData UTF8String], rl_prompt);
        fflush(stdout);
    } else {
        [self prompt:[theData boolValue]];
    }
}

@end
