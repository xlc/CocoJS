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
#import "js_objc_helper.h"

static JSCore *sharedInstance;

@interface JSCore ()

@property (nonatomic, retain) NSString *errorString;

- (BOOL)jsvalForName:(NSString *)name outval:(jsval *)outval;
- (BOOL)setJsvalForName:(NSString *)name val:(jsval)val;

@end

static JSClass global_class = { "Global", JSCLASS_GLOBAL_FLAGS, JS_PropertyStub, JS_PropertyStub, JS_PropertyStub, JS_StrictPropertyStub, JS_EnumerateStub, JS_ResolveStub, JS_ConvertStub, NULL, JSCLASS_NO_OPTIONAL_MEMBERS };

/* The error reporter callback. */
static void reportError(JSContext *cx, const char *message, JSErrorReport *report) {
    NSString *errorString = [NSString stringWithFormat:@"%s:%u:%s", report->filename ? report->filename : "<no filename="">", (unsigned int) report->lineno, message];
    MDLOG(@"%@", errorString);
    sharedInstance.errorString = errorString;
    
}

@implementation JSCore {
    BOOL _autoGC;
}

+ (JSCore *)sharedInstance {
    static dispatch_once_t onceToken;
    __block BOOL needinit = NO;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
        needinit = YES;
    });
    if (needinit) {
        [sharedInstance customInit];
    }
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

- (void)customInit {
    js_objc_init(_cx, _global);
    
    [self evaluateScriptFile:@"init"];
    [self gc];
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

- (BOOL)evaluateScriptFile:(NSString *)filename {
    NSString *filepath;
    BOOL found = NO;
    if (_searchDocumentDirectory) {
        NSString *documentDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
        
        filepath = [[documentDir stringByAppendingPathComponent:@"scripts"] stringByAppendingPathComponent:[filename stringByAppendingString:@".js"]];
        BOOL isDir;
        BOOL exist = [[NSFileManager defaultManager] fileExistsAtPath:filepath isDirectory:&isDir];
        if (exist && !isDir) {
            found = YES;
        }
    }
    if (!found) {
        filepath = [[NSBundle mainBundle] pathForResource:filename ofType:@"js" inDirectory:@"scripts"];
    }
    
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

- (BOOL)isStringCompleted:(NSString *)string {
    return JS_BufferIsCompilableUnit(_cx, JS_TRUE, _global, [string UTF8String], string.length);
}

- (NSString *)stringFromValue:(jsval)val {
    return jsval_to_source(_cx, val);
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

#pragma mark -

- (BOOL)jsvalForName:(NSString *)name outval:(jsval *)outval {
    BOOL ok = [self evaluateString:name outVal:outval];
    if (!ok || JSVAL_IS_NULL(*outval) || JSVAL_IS_VOID(*outval)) {
        return NO;
    }
    return YES;
}

- (BOOL)setJsvalForName:(NSString *)name val:(jsval)val {
    // set default value
    JSObject *object = _global;
    jsval objval;
    NSArray *nameComponent = [name componentsSeparatedByString:@"."];
    for (int i = 0; i < nameComponent.count - 1; i++) {
        NSString *com = nameComponent[i];
        JSBool ok = JS_GetProperty(_cx, object, [com UTF8String], &objval);
        if (!ok || JSVAL_IS_VOID(objval)) {
            objval = OBJECT_TO_JSVAL(JS_NewObject(_cx, NULL, NULL, NULL));
            JS_SetProperty(_cx, object, [com UTF8String], &objval);
        }
        if (JSVAL_IS_PRIMITIVE(objval)) {
            MILOG(@"unable to set value for %@", name);
            return NO;
        }
        object = JSVAL_TO_OBJECT(objval);
    }
    if (!JS_SetProperty(_cx, object, [[nameComponent lastObject] UTF8String], &val)) {
        MILOG(@"unable to set value for %@", name);
        return NO;
    }
    return YES;
}

- (id)valueForName:(NSString *)name {
    return [self valueForName:name defaultValue:nil];
}

- (id)valueForName:(NSString *)name defaultValue:(id)defaultValue {
    jsval outval;
    if ([self jsvalForName:name outval:&outval]) {
        return jsval_to_objc(_cx, outval);
    } else {
        [self setJsvalForName:name val:jsval_from_objc(_cx, defaultValue)];
    }
    return defaultValue;
}

- (void)valueForName:(NSString *)name encode:(const char *)encode outValue:(void *)outValue {
    [self valueForName:name encode:encode defaultValue:NULL outValue:outValue];
}

- (void)valueForName:(NSString *)name encode:(const char *)encode defaultValue:(void *)defaultValue outValue:(void *)outValue {
    jsval val;
    NSUInteger size;
    NSGetSizeAndAlignment(encode, &size, NULL);
    if ([self jsvalForName:name outval:&val]) {
        void *buffer;
        uint32_t outsize;
        if (jsval_to_type(_cx, val, encode, &buffer, &outsize)) {
            MASSERT(size == outsize, @"unmatched outsize (%u) and actural size (%u)", outsize, size);
            memcpy(outValue, buffer, size);
            return;
        }
    }
    // set default
    memcpy(outValue, defaultValue, size);
    jsval_from_type(_cx, encode, defaultValue, &val);
    [self setJsvalForName:name val:val];
}

- (id)executeFunction:(NSString *)name arguments:(id)arg, ... {
    va_list ap;
    va_start(ap, arg);
    
    NSMutableArray *array = [NSMutableArray array];
    
    id obj = arg;
    while (obj) {
        [array addObject:obj];
        obj = va_arg(ap, id);
    }
    
    va_end(ap);
    
    return [self executeFunction:name argumentArray:array];
}

- (id)executeFunction:(NSString *)name argumentArray:(NSArray *)args {
    jsval outval;
    if (![self evaluateString:name outVal:&outval]) {
        MFAIL(@"cannot find function: %@", name);
        return nil;
    }
    if (JSVAL_IS_PRIMITIVE(outval) || !JS_ObjectIsFunction(_cx, JSVAL_TO_OBJECT(outval))) {
        MFAIL(@"object is not function: %@", name);
        return nil;
    }
    
    jsval rval;
    jsval *argv = new jsval[args.count];
    int i = 0;
    
    for (id obj in args) {
        argv[i] = jsval_from_objc(_cx, obj);
        i++;
    }
    
    JSBool ok = JS_CallFunctionValue(_cx, _global, outval, args.count, argv, &rval);
    
    delete [] argv;
    
    if (!ok) {
        MELOG(@"fail to invoke js function %@ with arguments %@", name, args);
        return nil;
    }
    
    return jsval_to_objc(_cx, rval);
}

@end