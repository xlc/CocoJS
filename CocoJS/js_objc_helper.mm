//
//  js_objc_helper.mm
//  CocoJS
//
//  Created by Xiliang Chen on 12-10-22.
//  Copyright (c) 2012年 Xiliang Chen. All rights reserved.
//

#import "js_objc_helper.h"

#import <objc/runtime.h>
#include <algorithm>

#import "js_objc_binding.h"
#import "js_objc_struct.h"
#import "JSCore.h"

static char associate_key;
static char buff[256];

NSString *jsval_to_NSString(JSContext *cx, jsval val) {
    JSType type = JS_TypeOfValue(cx, val);
    switch (type) {
        case JSTYPE_NULL:
            return @"null";
        case JSTYPE_VOID:
            return @"undefined";
        case JSTYPE_BOOLEAN:
            return JSVAL_TO_BOOLEAN(val) ? @"true" : @"false";
        case JSTYPE_NUMBER:
            if (JSVAL_IS_INT(val)) {
                return [NSString stringWithFormat:@"%d", JSVAL_TO_INT(val)];
            }
            return [NSString stringWithFormat:@"%lf", JSVAL_TO_DOUBLE(val)];
        case JSTYPE_FUNCTION:
        case JSTYPE_OBJECT:
        {
            jsval ret;
            JSObject *obj = JSVAL_TO_OBJECT(val);
            if (obj == NULL) {
                return @"null";
            }
            if (JS_CallFunctionName(cx, obj, "toString", 0, NULL, &ret)) {
                JSString *jsstr = JSVAL_TO_STRING(ret);
                return @(JS_EncodeString(cx, jsstr));
            } else {
                return @"object";
            }
        }
        case JSTYPE_STRING:
            return @(JS_EncodeString(cx, JSVAL_TO_STRING(val)));
        default:
            return @(JS_GetTypeName(cx, type));
    }
}

const char *jsval_to_string(JSContext *cx, jsval val) {
    return JS_EncodeString(cx, JSVAL_TO_STRING(val));
}

double jsval_to_number(jsval val) {
    if (JSVAL_IS_INT(val)) {
        return JSVAL_TO_INT(val);
    } else if (JSVAL_IS_DOUBLE(val)) {
        return JSVAL_TO_DOUBLE(val);
    }
    return NAN;
}

int jsval_to_int_number(jsval val) {
    if (JSVAL_IS_INT(val)) {
        return JSVAL_TO_INT(val);
    } else if (JSVAL_IS_DOUBLE(val)) {
        return JSVAL_TO_DOUBLE(val);
    }
    return NAN;
}

id jsval_to_objc(JSContext *cx, jsval val) {
    JSType type = JS_TypeOfValue(cx, val);
    switch (type) {
        case JSTYPE_BOOLEAN:
            return JSVAL_TO_BOOLEAN(val) ? @YES : @NO;
        case JSTYPE_NUMBER:
            if (JSVAL_IS_INT(val)) {
                return @(JSVAL_TO_INT(val));
            }
            return @(JSVAL_TO_DOUBLE(val));
            
        case JSTYPE_FUNCTION:
        case JSTYPE_OBJECT:
        {
            JSObject *obj = JSVAL_TO_OBJECT(val);
            if (JS_IsArrayObject(cx, obj)) {
                uint32_t length;
                JS_GetArrayLength(cx, obj, &length);
                NSMutableArray *array = [NSMutableArray arrayWithCapacity:length];
                for (uint32_t i = 0; i < length; i++) {
                    jsval e;
                    MASSERT_SOFT(JS_GetElement(cx, obj, i, &e));
                    [array addObject:jsval_to_objc(cx, e)];
                }
                return array;
            }
            // TODO handle dictionary?
            return jsobject_to_objc(cx, obj);
        }
        case JSTYPE_STRING:
            return @(JS_EncodeString(cx, JSVAL_TO_STRING(val)));
            
        case JSTYPE_NULL:
        case JSTYPE_VOID:
            
        default:
            return nil;
    }
}

jsval jsval_from_objc(JSContext *cx, id object) {
    if (!object) {
        return JSVAL_NULL;
    }
    NSValue *jsobjptr = objc_getAssociatedObject(object, &associate_key);
    if (jsobjptr) {
        JSObject *jsobj = (JSObject *)[jsobjptr pointerValue];
        return OBJECT_TO_JSVAL(jsobj);
    }
    if ([object isKindOfClass:[NSString class]]) {
        return STRING_TO_JSVAL(JS_NewStringCopyZ(cx, [object UTF8String]));
    } else if ([object isKindOfClass:[NSArray class]]) {    // TODO this will failed for placeholder array that created by [NSArray alloc]
        NSArray *array = object;
        JSObject *jsobj = JS_NewArrayObject(cx, 0, NULL);
        uint32_t index = 0;
        for( id obj in array ) {
            jsval val = jsval_from_objc(cx, obj);
            JS_SetElement(cx, jsobj, index++, &val);
        }
        return OBJECT_TO_JSVAL(jsobj);
    } else if ([object isKindOfClass:[NSNumber class]]) {
        NSNumber *num = object;
        return DOUBLE_TO_JSVAL([num doubleValue]);  // TODO handle other types
    } else {    // TODO handle NSDictionary NSSet
        const char *script = [[NSString stringWithFormat:@"new objc.%@", [object class]] UTF8String];
        jsval val;
        MASSERT_SOFT(JS_EvaluateScript(cx, JS_GetGlobalObject(cx), script, strlen(script), NULL, 0, &val));
        associate_object(cx, JSVAL_TO_OBJECT(val), object);
        return val;
    }
}


static void release_obj(JSFreeOp *op, JSObject *obj) {
    remove_associated_object(obj);
}

JSClass js_objc_holder_class = { "ObjCObjectHolder", JSCLASS_HAS_PRIVATE, JS_PropertyStub, JS_PropertyStub, JS_PropertyStub, JS_StrictPropertyStub, JS_EnumerateStub, JS_ResolveStub, JS_ConvertStub, release_obj, JSCLASS_NO_OPTIONAL_MEMBERS };

id jsobject_to_objc(JSContext  *cx, JSObject *obj) {
    jsval val;
    JS_GetProperty(cx, obj, "__holder__", &val);
    JSObject *holder = JSVAL_TO_OBJECT(val);
    id nsobj = (id)JS_GetInstancePrivate(cx, holder, &js_objc_holder_class, NULL);
    return [[nsobj retain] autorelease];
}

void associate_object(JSContext *cx, JSObject *jsobj, id nsobj) {
    [nsobj retain];
    
    JSObject *holder = JS_NewObject(cx, &js_objc_holder_class, NULL, NULL);
    jsval holderval = OBJECT_TO_JSVAL(holder);
    
    JS_SetProperty(cx, jsobj, "__holder__", &holderval);
    
    JS_SetPrivate(holder, nsobj);
    
    objc_setAssociatedObject(nsobj, &associate_key, [NSValue valueWithPointer:jsobj], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void remove_associated_object(JSObject *jsobj) {
    id nsobj = (id)JS_GetPrivate(jsobj);
    objc_setAssociatedObject(nsobj, &associate_key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    [nsobj release];
}

SEL find_selector(id obj, const char *selname, int argc) {
    char *cstr = buff;
    SEL sel;
    
    if (argc == 0) {
        sel = sel_getUid(selname);
        if ([obj respondsToSelector:sel]) {
            return sel;
        }
        return NULL;
    }
    
    strncpy(cstr, selname, sizeof(buff));
    uint32_t len = strlen(cstr);
    MASSERT((len + argc + 1) < sizeof(buff), @"selector too long: %s", selname);
    
    if (argc >= 1) {    // must end with ':'
        if (cstr[len-1] == '_') {
            cstr[len-1] = ':';
        } else if (cstr[len-1] != ':') {
            cstr[len] = ':';
            cstr[++len] = '\0';
        }
    }
    
    int c = std::count(cstr, cstr+len, ':');
    
    if (c > argc) {
        return NULL;    // not enough arguments
    }
    
    if (c == argc) {
        sel = sel_getUid(cstr);
        if ([obj respondsToSelector:sel]) {
            return sel;
        }
    }
    
    if (c == 1) {
        
        // cannot mix '_' and ':'
        
        c = std::count(cstr, cstr+len, '_') + 1;
        if (c > argc) {  // some '_' at beginning of the real selector?
            char *buff = cstr+len;
            for (int i = 0; i < (c-argc);buff--) {
                if (*buff == '_') {
                    *buff = ':';
                    i++;
                }
            }
            sel = sel_getUid(cstr);
            if ([obj respondsToSelector:sel]) {
                return sel;
            }
            return NULL;
        }
        
        for (int i = 0; cstr[i]; i++) {
            if (cstr[i] == '_') cstr[i] = ':';
        }
        
        if (c == argc) {
            sel = sel_getUid(cstr);
            if ([obj respondsToSelector:sel]) {
                return sel;
            }
        }
        
    }
    
    // try append ':' at end of selector to match numebr of arugments
    for (int i = 0; i < argc - c; i++) {
        cstr[len++] = ':';
    }
    cstr[len] = '\0';
    sel = sel_getUid(cstr);
    if ([obj respondsToSelector:sel]) {
        return sel;
    }
    
    return NULL;
}

static SEL process_selector(Class cls, const char *selname, int argc) {
    char *cstr = buff;
    
    if (argc == 0) {
        return sel_getUid(selname);
    }
    
    strncpy(cstr, selname, sizeof(buff));
    uint32_t len = strlen(cstr);
    MASSERT((len + argc + 1) < sizeof(buff), @"selector too long: %s", selname);
    
    int c = 0;
    if (argc >= 1) {    // must end with ':'
        if (cstr[len-1] != ':') {
            cstr[len] = ':';
            cstr[++len] = '\0';
            c = 1;
        }
    }
    
    c += std::count(cstr, cstr+len, '_');
    if (c > argc) {  // some '_' at beginning of the real selector?
        char *buff = cstr+len;
        for (int i = 0; i < (c-argc);buff--) {
            if (*buff == '_') {
                *buff = ':';
                i++;
            }
        }
        return sel_getUid(selname);
    }
    
    for (int i = 0; cstr[i]; i++) {
        if (cstr[i] == '_') cstr[i] = ':';
    }
    
    if (c == argc) {
        return sel_getUid(selname);
    }
    
    
    // try append ':' at end of selector to match numebr of arugments
    for (int i = 0; i < argc - c; i++) {
        cstr[len++] = ':';
    }
    cstr[len] = '\0';
    return sel_getUid(selname);
}

SEL find_selector_class(Class cls, const char *selname, int argc, char **typedesc, char **rettype) {
    SEL sel = process_selector(cls, selname, argc);
    
    // override method?
    
    Method method = class_getInstanceMethod(cls, sel);
    if (method) { // Is method defined in the superclass?
        *typedesc = (char *)method_getTypeEncoding(method);
        *rettype = method_copyReturnType(method);
        return sel;
    }
    
    // implement protocol?
    
    while (cls) { // Walk up the object heirarchy
        uint count;
        Protocol **protocols = class_copyProtocolList(cls, &count);
        
        for (int i = 0; i < count; i++) {
            Protocol *protocol = protocols[i];
            struct objc_method_description methoddesc;
            methoddesc = protocol_getMethodDescription(protocol, sel, YES, YES); // required method
            if (!methoddesc.name)
                methoddesc = protocol_getMethodDescription(protocol, sel, NO, YES); // optional method
            if (methoddesc.name) {
                *typedesc = methoddesc.types;
                *rettype = method_copyReturnType((Method)&method);
                
                free(protocols);
                return sel;
            }
        }
        free(protocols);
        
        cls = [cls superclass];
    }
    
    return NULL;
}

JSBool set_argument(JSContext *cx, NSInvocation *invocation, int idx, jsval val) {
    idx += 2;
    const char *type = [[invocation methodSignature] getArgumentTypeAtIndex:idx];
    void *outval;
    if (!jsval_to_type(cx, val, type, &outval, NULL)) {
        MWLOG(@"fail to convert jsval to type: %s", type);
        return JS_FALSE;
    }
    
    [invocation setArgument:outval atIndex:idx];
    return JS_TRUE;
}

#define COPY_TO_BUFF(e) COPY_TO_BUFF2(e) break
#define COPY_TO_BUFF2(e) {__typeof__(e) _ret = (e); *outsize = sizeof(_ret); memcpy(buff, &_ret, *outsize); return JS_TRUE;}

JSBool jsval_to_type(JSContext *cx, jsval val, const char *encode, void **outval, uint32_t *outsize) {
    *outval = buff;
    uint32_t size;
    if (!outsize) {
        outsize = &size;
    }
    switch (encode[0]) {
        case _C_CLASS:  //    '#'
        case _C_ID:  //       '@'
            COPY_TO_BUFF(jsval_to_objc(cx, val));
            
        case _C_SEL:  //      ':'
            if (JSVAL_IS_STRING(val))
                COPY_TO_BUFF(sel_getUid(jsval_to_string(cx, val)));
            
        case _C_CHARPTR:  //  '*'
            if (JSVAL_IS_STRING(val))
                COPY_TO_BUFF(jsval_to_string(cx, val));
            
        case _C_BOOL:  //     'B'
        case _C_CHR:  //      'c'
            if (JSVAL_IS_BOOLEAN(val))
                COPY_TO_BUFF2((char) JSVAL_TO_BOOLEAN(val));    // no break
            
        case _C_UCHR:  //     'C'
            if (JSVAL_IS_NUMBER(val))
                COPY_TO_BUFF((char) jsval_to_int_number(val));
            
        case _C_SHT:  //      's'
        case _C_USHT:  //     'S'
            if (JSVAL_IS_NUMBER(val))
                COPY_TO_BUFF((short) jsval_to_int_number(val));
            
        case _C_INT:  //      'i'
        case _C_UINT:  //     'I'
            if (JSVAL_IS_NUMBER(val))
                COPY_TO_BUFF((int) jsval_to_int_number(val));
            
        case _C_LNG:  //      'l'
        case _C_ULNG:  //     'L'
            if (JSVAL_IS_NUMBER(val))
                COPY_TO_BUFF((long) jsval_to_int_number(val));
            
        case _C_LNG_LNG:  //  'q'
        case _C_ULNG_LNG:  // 'Q'
            if (JSVAL_IS_NUMBER(val))
                COPY_TO_BUFF((long long) jsval_to_int_number(val));
            
        case _C_FLT:  //      'f'
            if (JSVAL_IS_NUMBER(val))
                COPY_TO_BUFF((float) jsval_to_number(val));
            
        case _C_DBL:  //      'd'
            if (JSVAL_IS_NUMBER(val))
                COPY_TO_BUFF((double) jsval_to_number(val));
            
        case _C_UNDEF:  //    '?'
        case _C_VOID:  //     'v'
        case _C_CONST:  //    'r'
            return jsval_to_type(cx, val, encode+1, outval, outsize);
            
            
        case _C_ARY_B:  //    '['
        case _C_ARY_E:  //    ']'
        case _C_UNION_B:  //  '('
        case _C_UNION_E:  //  ')'
        case _C_STRUCT_B:  // '{'
        case _C_STRUCT_E:  // '}'
            return jsval_to_struct(cx, val, encode, outval, outsize);
            
            // unsuportted type
        case _C_BFLD:  //     'b'
        case _C_VECTOR:  //   '!'
        case _C_PTR:  //      '^'
        case _C_ATOM:  //     '%'
        default:
            MWLOG(@"unsouportted type %s", encode);
            return JS_FALSE;
    }
    
    // unmatched type
    return JS_FALSE;
}

#define COPY_FROM_BUFF(T, e) {COPY_FROM_BUFF2(T); *outval = (e); return JS_TRUE;} break
#define COPY_FROM_BUFF2(T) T val; memcpy(&val, value, sizeof(val))

JSBool jsval_from_type(JSContext *cx, const char *encode, void *value, jsval *outval) {
    *outval = JSVAL_VOID;
    
    switch (encode[0]) {
        case 0:
            *outval = JSVAL_VOID;
            return JS_TRUE;
            
        case _C_CLASS:  //    '#'
        case _C_ID:  //       '@'
            COPY_FROM_BUFF(id, jsval_from_objc(cx, val));
            break;
            
        case _C_SEL:  //      ':'
        case _C_CHARPTR:  //  '*'
            COPY_FROM_BUFF(const char *, STRING_TO_JSVAL(JS_NewStringCopyZ(cx, val)));
            
        case _C_BOOL:  //     'B'
        case _C_CHR:  //      'c'
        {
            COPY_FROM_BUFF2(char);
            if (val == 1)
                *outval = JSVAL_TRUE;
            else if (val == 0)
                *outval = JSVAL_FALSE;
        }
            
        case _C_UCHR:  //     'C'
            COPY_FROM_BUFF(char, INT_TO_JSVAL(val));
            
        case _C_SHT:  //      's'
        case _C_USHT:  //     'S'
            COPY_FROM_BUFF(short, INT_TO_JSVAL(val));
            
        case _C_INT:  //      'i'
        case _C_UINT:  //     'I'
            COPY_FROM_BUFF(int, INT_TO_JSVAL(val));
            
        case _C_LNG:  //      'l'
        case _C_ULNG:  //     'L'
            COPY_FROM_BUFF(long, INT_TO_JSVAL(val));
            
        case _C_LNG_LNG:  //  'q'
        case _C_ULNG_LNG:  // 'Q'
            COPY_FROM_BUFF(long long, INT_TO_JSVAL(val));
            
        case _C_FLT:  //      'f'
            COPY_FROM_BUFF(float, DOUBLE_TO_JSVAL(val));
            
        case _C_DBL:  //      'd'
            COPY_FROM_BUFF(double, DOUBLE_TO_JSVAL(val));
            
        case _C_UNDEF:  //    '?'
        case _C_VOID:  //     'v'
        case _C_CONST:  //    'r'
            return jsval_from_type(cx, encode+1, value, outval);
            
        case _C_ARY_B:  //    '['
        case _C_ARY_E:  //    ']'
        case _C_UNION_B:  //  '('
        case _C_UNION_E:  //  ')'
        case _C_STRUCT_B:  // '{'
        case _C_STRUCT_E:  // '}'
            return jsval_from_struct(cx, encode, value, outval);
            
            // unsuportted type
        case _C_BFLD:  //     'b'
        case _C_VECTOR:  //   '!'
        case _C_PTR:  //      '^'
        case _C_ATOM:  //     '%'
        default:
            MWLOG(@"unsouportted type %s", encode);
            *outval = JSVAL_VOID;
            return JS_FALSE;
    }
}

static JSBool invoke_method(id self, SEL _cmd, va_list ap, void *retvalue) {
    JSContext *cx = [JSCore sharedInstance].cx;
    
    jsval val = jsval_from_objc(cx, self);
    JSObject *obj = JSVAL_TO_OBJECT(val);
    jsval selmap;
    JS_GetProperty(cx, obj, "_selectorMap", &selmap);
    JSObject *selmapobj = JSVAL_TO_OBJECT(selmap);
    
    jsval selval;
    JS_GetProperty(cx, selmapobj, sel_getName(_cmd), &selval);
    const char *propertyname;
    if (JSVAL_IS_STRING(selval)) {
        propertyname = jsval_to_string(cx, selval);
    } else {
        char *cstr = buff;
        strncpy(cstr, sel_getName(_cmd), sizeof(buff));
        int len = strlen(cstr);
        char *curr = cstr;
        while (*curr) {
            if (*curr == ':') {
                *curr = '_';
            }
            curr++;
        }
        JSBool found = JS_FALSE;
        while (cstr[len-1] == '_') {
            JS_HasProperty(cx, obj, cstr, &found);
            if (found) {
                propertyname = cstr;
                break;
            }
            cstr[--len] = '\0'; // remove last '_'
        }
        if (!found) {
            MELOG(@"cannot find implementation of selector %s in object %@", sel_getName(_cmd), self);
            return JS_FALSE;
        }
    }
    
    jsval method;
    JS_GetProperty(cx, obj, propertyname, &method);
    
    NSMethodSignature *signature = [self methodSignatureForSelector:_cmd];
    int argc = [signature numberOfArguments] - 2;
    jsval rval;
    jsval *argv = new jsval[argc];
    
    for (int i = 0; i < argc; i++) {
        const char *type = [signature getArgumentTypeAtIndex:i];
        MASSERT_SOFT(jsval_from_type(cx, type, ap, argv+i));
        NSUInteger size;
        NSGetSizeAndAlignment(type, &size, NULL);
        ap += size;
    }
    
    MASSERT_SOFT(JS_CallFunctionValue(cx, obj, method, argc, argv, &rval));
    delete [] argv;
    
    void *outval;
    uint32_t size;
    if (jsval_to_type(cx, rval, [signature methodReturnType], &outval, &size)) {
        memcmp(retvalue, outval, size);
        return JS_TRUE;
    }
    
    return JS_FALSE;
}

// template for method imp
template <class T>
T js_objc_method_imp(id self, SEL _cmd, ...) {
    va_list ap;
    va_start(ap, _cmd);
    va_list ap2;
    va_copy(ap2, ap);
    
    T retval;
    if (!invoke_method(self, _cmd, ap2, &retval)) {
        MELOG(@"fail to invoke method %s for object %@", sel_getName(_cmd), self);
        bzero(&retval, sizeof(retval));
    }
    
    va_end(ap2);
    va_end(ap);
    
    return retval;
}

// for void return type
template <>
void js_objc_method_imp<void>(id self, SEL _cmd, ...) {
    va_list ap;
    va_start(ap, _cmd);
    va_list ap2;
    va_copy(ap2, ap);
    
    if (!invoke_method(self, _cmd, ap2, NULL)) {
        MELOG(@"fail to invoke method %s for object %@", sel_getName(_cmd), self);
    }
    
    va_end(ap2);
    va_end(ap);
}

#define METHOD_IMP_DECL(type) template type js_objc_method_imp<type>(id self, SEL _cmd, ...);
METHOD_IMP_DECL(Class)
METHOD_IMP_DECL(id)
METHOD_IMP_DECL(SEL)
METHOD_IMP_DECL(int)
METHOD_IMP_DECL(char *)
METHOD_IMP_DECL(BOOL)
METHOD_IMP_DECL(char)
METHOD_IMP_DECL(short)
METHOD_IMP_DECL(long)
METHOD_IMP_DECL(long long)
METHOD_IMP_DECL(float)
METHOD_IMP_DECL(double)

METHOD_IMP_DECL(CGPoint)
METHOD_IMP_DECL(CGSize)
METHOD_IMP_DECL(CGRect)
METHOD_IMP_DECL(CGAffineTransform)
METHOD_IMP_DECL(NSRange)
METHOD_IMP_DECL(UIEdgeInsets);

#define METHOD_IMP(type) if (strcmp(rettype, @encode(type)) == 0) return (IMP)js_objc_method_imp<type>

IMP get_imp(char *rettype) {
    switch (rettype[0]) {
        case _C_UNDEF:  //    '?'
        case _C_CONST:  //    'r'
            return get_imp(rettype+1);
            
        case _C_ARY_B:  //    '['
        case _C_ARY_E:  //    ']'
        case _C_UNION_B:  //  '('
        case _C_UNION_E:  //  ')'
        case _C_STRUCT_B:  // '{'
        case _C_STRUCT_E:  // '}'
            METHOD_IMP(CGPoint);
            METHOD_IMP(CGSize);
            METHOD_IMP(CGRect);
            METHOD_IMP(CGAffineTransform);
            METHOD_IMP(NSRange);
            METHOD_IMP(UIEdgeInsets);
            
            // unsuportted type
        case _C_BFLD:  //     'b'
        case _C_VECTOR:  //   '!'
        case _C_PTR:  //      '^'
        case _C_ATOM:  //     '%'
            
        default:
            MELOG(@"method return type cannot be handled: %s", rettype);
            // use void
        case _C_VOID:  //     'v'
            return (IMP)js_objc_method_imp<void>;
            
        case _C_CLASS:  //    '#'
            return (IMP)js_objc_method_imp<Class>;
            
        case _C_ID:  //       '@'
            return (IMP)js_objc_method_imp<id>;
            
        case _C_SEL:  //      ':'
            return (IMP)js_objc_method_imp<SEL>;
            
        case _C_CHARPTR:  //  '*'
            return (IMP)js_objc_method_imp<char *>;
            
        case _C_BOOL:  //     'B'
            return (IMP)js_objc_method_imp<BOOL>;
            
        case _C_CHR:  //      'c'
        case _C_UCHR:  //     'C'
            return (IMP)js_objc_method_imp<char>;
            
        case _C_SHT:  //      's'
        case _C_USHT:  //     'S'
            return (IMP)js_objc_method_imp<short>;
            
        case _C_INT:  //      'i'
        case _C_UINT:  //     'I'
            return (IMP)js_objc_method_imp<int>;
            
        case _C_LNG:  //      'l'
        case _C_ULNG:  //     'L'
            return (IMP)js_objc_method_imp<long>;
            
        case _C_LNG_LNG:  //  'q'
        case _C_ULNG_LNG:  // 'Q'
            return (IMP)js_objc_method_imp<long long>;
            
        case _C_FLT:  //      'f'
            return (IMP)js_objc_method_imp<float>;
            
        case _C_DBL:  //      'd'
            return (IMP)js_objc_method_imp<double>;
    }
}