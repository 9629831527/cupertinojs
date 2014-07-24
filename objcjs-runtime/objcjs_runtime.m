//
//  objcjs_runtime.m
//  objcjs-runtime
//
//  Created by Jerry Marino on 7/15/14.
//  Copyright (c) 2014 Jerry Marino. All rights reserved.
//

#import "objcjs_runtime.h"
#import <objc/message.h>
#import <malloc/malloc.h>

#define RuntimeException(_FMT) \
    [NSException raise:@"OBJCJSRuntimeException" format:_FMT]


@implementation NSObject (ObjCJSFunction)

static char * ObjCJSEnvironmentKey;

- (NSMutableDictionary *)_objcjs_environment {
    NSMutableDictionary *environment = objc_getAssociatedObject(self, ObjCJSEnvironmentKey);
    if (!environment) {
        environment = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, ObjCJSEnvironmentKey, environment, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return environment;
}

static NSMutableDictionary *ObjCJSParents = NULL;

+ (void)_objcjs_setParent:(id)parent {
    if (!ObjCJSParents){
        ObjCJSParents = [[NSMutableDictionary alloc] init];
    }

    ObjCJSParents[NSStringFromClass(self.class)] = [parent retain];
}

+ (id)_objcjs_parent {
    return ObjCJSParents[NSStringFromClass(self.class)];
}

- (id)_objcjs_parent {
    return ObjCJSParents[NSStringFromClass(self.class)];
}

- (id)_objcjs_body:(id)args, ... {
    return @"JSFUNCTION-DEFAULT-BODY-RETURN";
}

//TODO : safely swizzle this on
- (NSNumber *)length {
    return @0;
}

- (void)objcjs_defineProperty:(const char *)propertyName {
    Class selfClass = [self class];
    
    IMP getter = imp_implementationWithBlock(^(id _self, SEL cmd){
        id value = objc_getAssociatedObject(_self, propertyName);
        return [value retain];
    });
    
    size_t nameLen = strlen(propertyName);
    char *setterName = malloc((sizeof(char) * nameLen) + 5);
  
    memcpy(setterName, "set", 4);
    setterName[3] = toupper(propertyName[0]);
   
    for (int i = 1; i < nameLen; i++) {
        setterName[i + 3] = propertyName[i];
    }
    
    setterName[nameLen + 3] = ':';
    setterName[nameLen + 4] = '\0';
    
    IMP setter = imp_implementationWithBlock(^(id _self, SEL cmd, id value){
        objc_setAssociatedObject(_self, propertyName, value, OBJC_ASSOCIATION_COPY);
    });
    
    SEL gSel = sel_getUid(propertyName);
    class_addMethod(selfClass, gSel, getter, "@@:");
    class_addMethod(selfClass, sel_getUid(setterName), setter, "v@:@");

    free(setterName);
}

- (void)_objcjs_env_setValue:(id)value forKey:(NSString *)key {
    NSMutableDictionary *environment = [self _objcjs_environment];
    if (!value) {
        if (![[environment allKeys] containsObject:key]) {
            [[self _objcjs_parent] _objcjs_env_setValue:value forKey:key];
        } else {
            [environment setNilValueForKey:[key copy]];
        }
    } else {
        if (![[environment allKeys] containsObject:key]) {
            [[self _objcjs_parent] _objcjs_env_setValue:value forKey:key];
        } else {
            environment[[key copy]] = [value copy];
        }   
    }
}

- (void)_objcjs_env_setValue:(id)value declareKey:(NSString *)key {
    NSMutableDictionary *environment = [self _objcjs_environment];
    if (!value) {
        [environment setNilValueForKey:[key copy]];
    } else {
        environment[[key copy]] = [value copy];
    }
}

- (id)_objcjs_env_valueForKey:(NSString *)key {
    NSMutableDictionary *environment = [self _objcjs_environment];
    id value = environment[key];
    return value ?: [[self _objcjs_parent] _objcjs_env_valueForKey:key];
}

@end

//an imp signature is id name(_strong id, SEL, ...);
void *objcjs_defineJSFunction(const char *name,
                       JSFunctionBodyIMP body){
    NSLog(@"%s %s %p",__PRETTY_FUNCTION__, name, body);
    Class superClass = [NSObject class];
    Class jsClass = objc_allocateClassPair(superClass, name, 16);

    SEL bodySelector = @selector(_objcjs_body:);
    Method superBody = class_getInstanceMethod(superClass, bodySelector);
    assert(superBody);
    const char *enc = method_getTypeEncoding(superBody);
    class_addMethod(jsClass, bodySelector, (IMP)body, enc);
    objc_registerClassPair(jsClass);
    return jsClass;
}

size_t __NSObjectMallocSize(){
    return 64;
}

void *objcjs_invoke(void *target, ...){
    printf("objcjs_invoke(%p, ...)\n", target);

    if (!target) {
        RuntimeException(@"nil is not a function");
    }
  
    int argCt = 0;
    va_list args1;
    va_start(args1, target);
    for (NSString *arg = target; arg != nil; arg = va_arg(args1, id)){
        argCt++;
    }
    va_end(args1);
 
    // TODO: is there a better way to do this?
    BOOL targetIsClass = malloc_size(target) == __NSObjectMallocSize();
    Class targetClass = nil;
    if (targetIsClass) {
        targetClass = target;
        target = [[targetClass new] autorelease];
        printf("new instance of %s \n", class_getName(targetClass));
    } else if ([(id)target respondsToSelector:@selector(_objcjs_body:)]) {
        targetClass = object_getClass(target);
        printf("instance of %s\n", class_getName(targetClass));
    } else {
        RuntimeException(@"objcjs_invoke requires _objcjs_body:");
    }
  
    assert(targetClass && "objcjs_invoke on missing class:" && target);
    
    SEL bodySel = @selector(_objcjs_body:);
    va_list args;
    va_start(args, target);
    
    Method m = class_getInstanceMethod(targetClass, bodySel);
    IMP imp = method_getImplementation(m);
    
    id result;
    switch (argCt) {
        case 1: {
            result = imp(target, bodySel, nil);
            break;
        }
        case 2: {
            id arg1 = va_arg(args, id);
            result = imp(target, bodySel, arg1, nil);
            break;
        }
        case 3: {
            id arg1 = va_arg(args, id);
            id arg2 = va_arg(args, id);
            result = imp(target, bodySel, arg1, arg2, nil);
            break;
        }
        case 4: {
            id arg1 = va_arg(args, id);
            id arg2 = va_arg(args, id);
            id arg3 = va_arg(args, id);
            result = imp(target, bodySel, arg1, arg2, arg3, nil);
            break;
        }
        case 5: {
            id arg1 = va_arg(args, id);
            id arg2 = va_arg(args, id);
            id arg3 = va_arg(args, id);
            id arg4 = va_arg(args, id);
            result = imp(target, bodySel, arg1, arg2, arg3, arg4, nil);
            break;
        }
    }
    va_end(args);
    return result;
}

@interface ObjCJSNaN : NSObject @end
@implementation ObjCJSNaN @end

@interface ObjCJSUndefined : NSObject @end
@implementation ObjCJSUndefined @end

id objcjs_NaN;
id objcjs_Undefined;

__attribute__((constructor))
static void ObjCJSRuntimeInit(){
    objcjs_NaN = [ObjCJSNaN class];
    objcjs_Undefined = [ObjCJSUndefined class];
}

@implementation NSObject (ObjCJSOperators)

#define DEF_OBJCJS_OPERATOR_RETURN_CLASS_OR_ZERO(SEL)\
- SEL (id) value { \
    BOOL sameClass = [self isKindOfClass:[value class]] ||  [value isKindOfClass:[self class]]; \
    return sameClass ? [self SEL value] : @0; \
}

DEF_OBJCJS_OPERATOR_RETURN_CLASS_OR_ZERO(objcjs_add:)
DEF_OBJCJS_OPERATOR_RETURN_CLASS_OR_ZERO(objcjs_subtract:);
DEF_OBJCJS_OPERATOR_RETURN_CLASS_OR_ZERO(objcjs_multiply:);
DEF_OBJCJS_OPERATOR_RETURN_CLASS_OR_ZERO(objcjs_divide:);
DEF_OBJCJS_OPERATOR_RETURN_CLASS_OR_ZERO(objcjs_mod:);
DEF_OBJCJS_OPERATOR_RETURN_CLASS_OR_ZERO(objcjs_bitor:);
DEF_OBJCJS_OPERATOR_RETURN_CLASS_OR_ZERO(objcjs_bitxor:);
DEF_OBJCJS_OPERATOR_RETURN_CLASS_OR_ZERO(objcjs_bitand:);
// "<<"
DEF_OBJCJS_OPERATOR_RETURN_CLASS_OR_ZERO(objcjs_shiftleft:);
// ">>"
DEF_OBJCJS_OPERATOR_RETURN_CLASS_OR_ZERO(objcjs_shiftright:);
// ">>>"
DEF_OBJCJS_OPERATOR_RETURN_CLASS_OR_ZERO(objcjs_shiftrightright:);

- objcjs_increment {
    return objcjs_NaN;
}

- objcjs_decrement {
    return objcjs_NaN;
}

- (bool)objcjs_boolValue {
    return true;
}

@end

@implementation NSNumber (ObjCJSOperators)

- objcjs_add:(id)value {
    return @([self doubleValue] + [value doubleValue]);
}

- objcjs_subtract:(id)value {
    return @([self doubleValue] - [value doubleValue]);
}

- objcjs_multiply:(id)value {
    return @([self doubleValue] * [value doubleValue]);
}

- objcjs_divide:(id)value {
    return @([self doubleValue] / [value doubleValue]);
}

- objcjs_mod:(id)value {
    return @([self intValue] % [value intValue]);
}

- objcjs_bitor:(id)value {
    return @([self intValue] | [value intValue]);
}

- objcjs_bitxor:(id)value {
    return @([self intValue] ^ [value intValue]);
}

- objcjs_bitand:(id)value {
    return @([self intValue] & [value intValue]);
}

// "<<"
- objcjs_shiftleft:(id)value {
    return @([self intValue] << [value intValue]);
}

// ">>"
- objcjs_shiftright:(id)value {
    return @([self intValue] >> [value intValue]);
}

// ">>>"
- objcjs_shiftrightright:(id)value {
    return @(([self intValue] >> [value intValue]) | 0);
}

- objcjs_increment {
    if ([self objCType] == (const char *)'d') {
        return [NSNumber numberWithDouble:[self doubleValue] + 1.0];
    }
    
    return [NSNumber numberWithInt:[self doubleValue] + 1];
}

- objcjs_decrement {
    if ([self objCType] == (const char *)'d') {
        return [NSNumber numberWithDouble:[self doubleValue] - 1.0];
    }
   
    return [NSNumber numberWithInt:[self doubleValue] - 1];
}

- (bool)objcjs_boolValue {
    return !![self intValue];
}

@end

@implementation NSString (ObjCJSOperators)

- (bool)objcjs_boolValue {
    return !![self length];
}

@end
