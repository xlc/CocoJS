//
//  js_objc_binding.mm
//  CocoJS
//
//  Created by Xiliang Chen on 12-10-23.
//  Copyright (c) 2012年 Xiliang Chen. All rights reserved.
//

#import "js_objc_binding.h"

#import "js_objc_helper.h"

static int internalOperation = 0;

static JSFunction *createSelectorFunc;

static JSBool objc_property_op(JSContext *cx, JSHandleObject obj, JSHandleId jid, jsval *vp) {
    if (internalOperation) return JS_TRUE;
    MDLOG(@"property change blocked: %s", JS_EncodeString(cx, JSID_TO_STRING(jid)));
    *vp = JSVAL_VOID;
    return JS_FALSE;
}

static JSBool objc_property_setter(JSContext *cx, JSHandleObject obj, JSHandleId jid, JSBool strict, jsval *vp) {
    return objc_property_op(cx, obj, jid, vp);
}

static JSBool resolve_objc_selector(JSContext *cx, JSHandleObject obj, JSHandleId jid) {
    if (internalOperation) return JS_TRUE;
    
    JSString *jsname = JSID_TO_STRING(jid);
    const char *selname = JS_EncodeString(cx, jsname);
    
    static JSObject *proto;
    if (!proto) {
        proto = JS_GetGlobalObject(cx);
        jsval objectval;
        JS_GetProperty(cx, proto, "Object", &objectval);
        jsval objprotoval;
        JS_GetProperty(cx, JSVAL_TO_OBJECT(objectval), "prototype", &objprotoval);
        proto = JSVAL_TO_OBJECT(objprotoval);
    }
    JSBool found;
    MASSERT_SOFT(JS_HasPropertyById(cx, proto, jid, &found));
    if (found) {
        return JS_TRUE;
    }
    
    jsval rval;
    jsval arg = STRING_TO_JSVAL(jsname);
    JS_CallFunction(cx, obj, createSelectorFunc, 1, &arg, &rval);
    
    internalOperation++;
    JS_SetProperty(cx, obj, selname, &rval);
    internalOperation--;
    
    return JS_TRUE;
}

static JSClass js_objc_prototype_class = { "ObjCInstancePrototype", 0, objc_property_op, objc_property_op, JS_PropertyStub, objc_property_setter, JS_EnumerateStub, resolve_objc_selector, JS_ConvertStub, NULL, JSCLASS_NO_OPTIONAL_MEMBERS };

static JSBool js_objc_lookup_static_method(JSContext *cx, uint32_t argc, jsval *vp) {
    
    jsval *argvp = JS_ARGV(cx, vp);
    
    JSObject *thisobj = JS_THIS_OBJECT(cx, vp);
    jsval nameval;
    MASSERT_SOFT(JS_GetProperty(cx, thisobj, "name", &nameval));
    Class cls = NSClassFromString(@(jsval_to_string(cx, nameval)));
    
    if (!JSVAL_IS_STRING(argvp[0])) return JS_FALSE;
    const char *selname = jsval_to_string(cx, argvp[0]);
    
    unsigned len;
    JSObject *argv = JSVAL_TO_OBJECT(argvp[1]);
    MASSERT_SOFT(JS_GetArrayLength(cx, argv, &len));
    
    SEL sel = find_selector(cls, selname, len);
    if (!sel) {
        MILOG(@"cannot find selector '%s' for class %@", selname, cls);
        return JS_FALSE;
    }
    
    JSBool ok = JS_TRUE;
    NSMethodSignature *signature = [cls methodSignatureForSelector:sel];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:cls];
    [invocation setSelector:sel];
    for (int i = 0; i < len; i++) {
        jsval arg;
        MASSERT_SOFT(JS_GetElement(cx, argv, i, &arg));
        ok &= set_argument(cx, invocation, i, arg);
    }
    if (!ok) return JS_FALSE;
    [invocation invoke];
    
    jsval rval;
    void *retval = malloc([signature methodReturnLength]);
    [invocation getReturnValue:retval];
    
    ok &= jsval_from_type(cx, [signature methodReturnType], retval, &rval);
    free(retval);
    
    JS_SET_RVAL(cx, vp, rval);
    return JS_TRUE;
}

static jsval create_objc_instance_class(JSContext *cx, NSString *clsname) {
    jsval val;
    const char *script = [[NSString stringWithFormat:@"(function(){function %@ () {objc._alloc(this)};%@.toString = function(){return '%@'}; return %@;})()", clsname, clsname, clsname, clsname] UTF8String];
    MASSERT_SOFT(JS_EvaluateScript(cx, JS_GetGlobalObject(cx), script, strlen(script), NULL, 0, &val));
    
    JSObject *obj = JSVAL_TO_OBJECT(val);
    
    JSObject *proto = JS_NewObject(cx, &js_objc_prototype_class, NULL, NULL);
    jsval protoval = OBJECT_TO_JSVAL(proto);
    JS_SetProperty(cx, obj, "prototype", &protoval);   // class.prototype = proto
    JS_SetProperty(cx, proto, "constructor", &val);     // class.prototype.constructor = class
    
    int op = internalOperation;
    internalOperation = 0;
    jsval descval;
    JS_GetProperty(cx, proto, "description", &descval);
    internalOperation = op;
    internalOperation++;
    JS_SetProperty(cx, proto, "toString", &descval);  // proto.toString = proto.description
    
    associate_object(cx, obj, NSClassFromString(clsname));
    internalOperation--;
    
    JS_DefineFunction(cx, obj, "__noSuchMethod__", js_objc_lookup_static_method, 2, JSPROP_READONLY | JSPROP_PERMANENT );       // for static method lookup
    
    return val;
}

static JSBool resolve_objc_class(JSContext *cx, JSHandleObject obj, JSHandleId jid) {
    internalOperation++;
    
    JSString *jsname = JSID_TO_STRING(jid);
    NSString *clsname = @(JS_EncodeString(cx, jsname));
    Class cls = NSClassFromString(clsname);
    if (cls) {
        jsval val = create_objc_instance_class(cx, clsname);
        JS_SetProperty(cx, obj, [clsname UTF8String], &val);
    }
    
    internalOperation--;
    return JS_TRUE;
}

static JSClass js_objc_class = { "ObjC", 0, objc_property_op, objc_property_op, JS_PropertyStub, objc_property_setter, JS_EnumerateStub, resolve_objc_class, JS_ConvertStub, NULL, JSCLASS_NO_OPTIONAL_MEMBERS };

static JSBool perform_selector(JSContext *cx, uint32_t argc, jsval *vp) {
    if (argc < 2) return JS_FALSE;
    
    jsval *argvp = JS_ARGV(cx, vp);
    if (JSVAL_IS_PRIMITIVE(argvp[0])) return JS_FALSE;
    
    id nsobj = jsobject_to_objc(cx, JSVAL_TO_OBJECT(argvp[0]));
    if (!nsobj) return JS_FALSE;
    
    if (!JSVAL_IS_STRING(argvp[1])) return JS_FALSE;
    const char *selname = jsval_to_string(cx, argvp[1]);
    
    argc -= 2;
    argvp += 2;
    
    SEL sel = find_selector(nsobj, selname, argc);
    if (!sel) {
        MILOG(@"cannot find selector '%s' for object %@", selname, nsobj);
        return JS_FALSE;
    }
    
    JSBool ok = JS_TRUE;
    NSMethodSignature *signature = [nsobj methodSignatureForSelector:sel];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:nsobj];
    [invocation setSelector:sel];
    for (int i = 0; i < argc; i++) {
        ok &= set_argument(cx, invocation, i, argvp[i]);
    }
    if (!ok) return JS_FALSE;
    [invocation invoke];
    
    jsval rval;
    void *retval = malloc([signature methodReturnLength]);
    [invocation getReturnValue:retval];
    
    ok &= jsval_from_type(cx, [signature methodReturnType], retval, &rval);
    free(retval);
    
    JS_SET_RVAL(cx, vp, rval);
    
    return ok;
}

static JSBool js_objc_alloc(JSContext *cx, uint32_t argc, jsval *vp) {
    if (argc < 1) return JS_FALSE;
    jsval *argvp = JS_ARGV(cx, vp);
    JSObject *obj = JSVAL_TO_OBJECT(argvp[0]);
    jsval cstrval, nameval;
    MASSERT_SOFT(JS_GetProperty(cx, obj, "constructor", &cstrval));
    MASSERT_SOFT(JS_GetProperty(cx, JSVAL_TO_OBJECT(cstrval), "name", &nameval));
    Class cls = NSClassFromString(@(jsval_to_string(cx, nameval)));
    id nsobj = [[cls alloc] autorelease];
    
    internalOperation++;
    
    associate_object(cx, obj, nsobj);   // this will retain the object
    
    internalOperation--;
    
    JS_SET_RVAL(cx, vp, JSVAL_VOID);
    return JS_TRUE;
}

static JSBool js_objc_gc(JSContext *cx, uint32_t argc, jsval *vp) {
    JS_GC(JS_GetRuntime(cx));
    JS_SET_RVAL(cx, vp, JSVAL_VOID);
    return JS_TRUE;
}

static JSBool js_log(JSContext *cx, uint32_t argc, jsval *vp) {
    jsval *argvp = JS_ARGV(cx, vp);
    
    if (argc == 0) {
        printf("\n");
    } else {
        NSMutableString *str = [NSMutableString string];
        for (int i = 0; i < argc; i++) {
            NSString *value = jsval_to_NSString(cx, argvp[i]);
            [str appendString:value];
            if (i != argc-1) {
                [str appendString:@", "];
            }
        }
        NSLog(@"%@", str);
    }
    
    JS_SET_RVAL(cx, vp, JSVAL_VOID);
    return JS_TRUE;
}

void js_objc_init(JSContext *cx, JSObject *global) {
    JSObject *obj = JS_NewObject(cx, &js_objc_class, NULL, NULL);
    jsval objval = OBJECT_TO_JSVAL(obj);
    JS_SetProperty(cx, global, "objc", &objval);
    
    internalOperation++;
    
    JS_DefineFunction(cx, global, "log", js_log, 1, JSPROP_READONLY | JSPROP_PERMANENT | JSPROP_ENUMERATE );
    
    JS_DefineFunction(cx, obj, "_perform", perform_selector, 2, JSPROP_READONLY | JSPROP_PERMANENT );
    JS_DefineFunction(cx, obj, "_alloc", js_objc_alloc, 1, JSPROP_READONLY | JSPROP_PERMANENT );
    JS_DefineFunction(cx, obj, "gc", js_objc_gc, 0, JSPROP_READONLY | JSPROP_PERMANENT | JSPROP_ENUMERATE );
    
    const char *argname = "sel";
    const char *funcbody = "return function() {[].splice.call(arguments, 0, 0, this, sel);return objc._perform.apply(null, arguments);}";
    createSelectorFunc = JS_CompileFunction(cx, obj, "_selector", 1, &argname, funcbody, strlen(funcbody), NULL, 0);
    
    internalOperation--;
}