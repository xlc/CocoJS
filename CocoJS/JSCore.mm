//
//  JSCore.m
//  CocoJS
//
//  Created by Xiliang Chen on 12-10-22.
//  Copyright (c) 2012年 Xiliang Chen. All rights reserved.
//

#import "JSCore.h"

#import "jsapi.h"
#import "js_objc_binding.h"

static JSCore *sharedInstance;

@interface JSCore ()

@property (nonatomic, retain) NSString *errorString;

@end

static JSClass global_class = { "Global", JSCLASS_GLOBAL_FLAGS, JS_PropertyStub, JS_PropertyStub, JS_PropertyStub, JS_StrictPropertyStub, JS_EnumerateStub, JS_ResolveStub, JS_ConvertStub, NULL, JSCLASS_NO_OPTIONAL_MEMBERS };

/* The error reporter callback. */
static void reportError(JSContext *cx, const char *message, JSErrorReport *report) {
    sharedInstance.errorString = [NSString stringWithFormat:@"%s:%u:%s", report->filename ? report->filename : "<no filename="">", (unsigned int) report->lineno, message];
    MDLOG(@"%@", sharedInstance.errorString);
    
}

@implementation JSCore {
    BOOL _autoGC;
}

+ (JSCore *)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
        js_objc_init(sharedInstance.cx, sharedInstance.global);
    });
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        
        /* Create a JS runtime. */
        _rt = JS_NewRuntime(8L * 1024L * 1024L);
        /* Create a context. */
        _cx = JS_NewContext(_rt, 8192);
        JS_SetOptions(_cx, JSOPTION_VAROBJFIX);
        JS_SetVersion(_cx, JSVERSION_LATEST);
        JS_SetErrorReporter(_cx, reportError);
        /* Create the global object in a new compartment. */
        _global = JS_NewGlobalObject(_cx, &global_class, NULL);
        /* Populate the global object with the standard globals, like Object and Array. */
        JS_InitStandardClasses(_cx, _global);
        
        [self startAutoGC];
    }
    return self;
}

- (void)dealloc
{
    JS_DestroyContext(_cx);
    JS_DestroyRuntime(_rt);
    
    [super dealloc];
}

#pragma mark -

- (BOOL)evaluateString:(NSString *)string outVal:(jsval *)outVal
{
    self.errorString = @"";
	const char *cstr = [string UTF8String];
	BOOL ok = JS_EvaluateScript( _cx, _global, cstr, (unsigned)strlen(cstr), "noname", 0, outVal);
	return ok;
}

- (BOOL)evaluateScript:(NSString *)filename {
    NSString *filepath = [[NSBundle mainBundle] pathForResource:filename ofType:@"js" inDirectory:@"scripts"];
    return [self evaluateFile:filepath];
}

- (BOOL)evaluateFile:(NSString *)filepath {
    
    NSError *error = nil;
	NSString *script = [NSString stringWithContentsOfFile:filepath encoding:NSUTF8StringEncoding error:&error];
    if (!script) {
        MWLOG(@"fail to read file at path: %@, with error: %@", filepath, error);
        return NO;
    }
	
    return [self evaluateString:script outVal:nil];
}

#pragma mark -

- (void)gc {
    JS_GC(_rt);
}

- (void)gcIfNeed {
    JS_MaybeGC(_cx);
}

- (void)startAutoGC {
    _autoGC = YES;
    int64_t delayInSeconds = 1;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        if (_autoGC) {
            [self gcIfNeed];
            [self startAutoGC];
        }
    });
}

- (void)stopAutoGC {
    _autoGC = NO;
}

@end