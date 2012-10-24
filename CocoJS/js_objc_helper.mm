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

static char associate_key;

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

id jsobject_to_objc(JSContext  *cx, JSObject *obj) {
    id nsobj = (id)JS_GetPrivate(obj);
    return [[nsobj retain] autorelease];
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
        case JSTYPE_OBJECT:
        {
            JSObject *obj = JSVAL_TO_OBJECT(val);
            if (JS_IsArrayObject(cx, obj)) {
                unsigned length;
                JS_GetArrayLength(cx, obj, &length);
                NSMutableArray *array = [NSMutableArray arrayWithCapacity:length];
                for (unsigned i = 0; i < length; i++) {
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
        case JSTYPE_FUNCTION: // not supported
        default:
            return nil;
    }
}

jsval jsval_from_objc(JSContext *cx, id object) {
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

void associate_object(JSContext *cx, JSObject *jsobj, id nsobj) {
    [nsobj retain];
    
    JSObject *holder = JS_NewObject(cx, &js_objc_holder_class, NULL, NULL);
    jsval holderval = OBJECT_TO_JSVAL(holder);
    
    JS_SetProperty(cx, jsobj, "_holder", &holderval);
    
    JS_SetPrivate(jsobj, nsobj);
    JS_SetPrivate(holder, nsobj);
    
    objc_setAssociatedObject(nsobj, &associate_key, [NSValue valueWithPointer:jsobj], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void remove_associated_object(JSObject *jsobj) {
    id nsobj = (id)JS_GetPrivate(jsobj);
    objc_setAssociatedObject(nsobj, &associate_key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    [nsobj release];
}

SEL find_selector(id obj, const char *selname, int argc) {
    SEL sel;
    static char cstr[256];
    
    if (argc == 0) {
        sel = sel_getUid(selname);
        if ([obj respondsToSelector:sel]) {
            return sel;
        }
        return NULL;
    }
    
    strncpy(cstr, selname, sizeof(cstr));
    unsigned len = strlen(cstr);
    MASSERT((len + argc + 1) < sizeof(cstr), @"selector too long: %s", selname);
    
    if (argc >= 1 && cstr[len-1] != ':') {
        cstr[len++] = ':';    // must end with ':'
        cstr[len] = '\0';
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
    
    if (c > 1) {
        
        // cannot mix '_' and ':'
        
        c = std::count(cstr, cstr+len, '_') + 1;
        if (c > argc) {  // some '_' at beginning of the real selector?
            char *buff = cstr+len;
            for (int i = 0; i < (c-argc); i++, buff--) {
                if (*buff == '_') *buff = ':';
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
        cstr[len++] = ':';    // must end with ':'
        cstr[len] = '\0';
        sel = sel_getUid(cstr);
        if ([obj respondsToSelector:sel]) {
            return sel;
        }
    }
    
    return NULL;
}

JSBool set_argument(JSContext *cx, NSInvocation *invocation, int idx, jsval val) {
    idx += 2;
    const char *type = [[invocation methodSignature] getArgumentTypeAtIndex:idx];
    void *outval;
    MASSERT_SOFT(jsval_to_type(cx, val, type, &outval, NULL));
    
    [invocation setArgument:outval atIndex:idx];
    return JS_TRUE;
}

#define COPY_TO_BUFF(e) COPY_TO_BUFF2(e) break

#define COPY_TO_BUFF2(e) {__typeof__(e) _ret = (e); size = sizeof(_ret); memcpy(buff, &_ret, size); return JS_TRUE;}

JSBool jsval_to_type(JSContext *cx, jsval val, const char *encode, void **outval, unsigned *outsize) {
    unsigned size;
    static char buff[256];
    *outval = buff;
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
            if (JSVAL_IS_INT(val))
                COPY_TO_BUFF((char) JSVAL_TO_INT(val));
            
        case _C_SHT:  //      's'
        case _C_USHT:  //     'S'
            if (JSVAL_IS_INT(val))
                COPY_TO_BUFF((short) JSVAL_TO_INT(val));
            
        case _C_INT:  //      'i'
        case _C_UINT:  //     'I'
            if (JSVAL_IS_INT(val))
                COPY_TO_BUFF((int) JSVAL_TO_INT(val));
            
        case _C_LNG:  //      'l'
        case _C_ULNG:  //     'L'
            if (JSVAL_IS_INT(val))
                COPY_TO_BUFF((long) JSVAL_TO_INT(val));
            
        case _C_LNG_LNG:  //  'q'
        case _C_ULNG_LNG:  // 'Q'
            if (JSVAL_IS_INT(val))
                COPY_TO_BUFF((long long) JSVAL_TO_INT(val));
            
        case _C_FLT:  //      'f'
            if (JSVAL_IS_DOUBLE(val))
                COPY_TO_BUFF((float) JSVAL_TO_DOUBLE(val));
            
        case _C_DBL:  //      'd'
            if (JSVAL_IS_DOUBLE(val))
                COPY_TO_BUFF((double) JSVAL_TO_DOUBLE(val));
            
        case _C_UNDEF:  //    '?'
        case _C_VOID:  //     'v'
        case _C_CONST:  //    'r'
            return jsval_to_type(cx, val, encode, outval, outsize);
            
            
        case _C_ARY_B:  //    '['
        case _C_ARY_E:  //    ']'
        case _C_UNION_B:  //  '('
        case _C_UNION_E:  //  ')'
        case _C_STRUCT_B:  // '{'
        case _C_STRUCT_E:  // '}'
                           // TODO implement for structs
            
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

#define COPY_FROM_BUFF(T, e) {COPY_FROM_BUFF2(T) *outval = (e); return JS_TRUE;} break
#define COPY_FROM_BUFF2(T) T val; memcpy(&val, value, sizeof(val));

JSBool jsval_from_type(JSContext *cx, const char *encode, void *value, jsval *outval) {
    switch (encode[0]) {
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
            return jsval_from_type(cx, encode, value, outval);
            
        case _C_ARY_B:  //    '['
        case _C_ARY_E:  //    ']'
        case _C_UNION_B:  //  '('
        case _C_UNION_E:  //  ')'
        case _C_STRUCT_B:  // '{'
        case _C_STRUCT_E:  // '}'
                           // TODO implement for structs
            
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