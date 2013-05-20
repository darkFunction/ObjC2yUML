//
//  DFyUMLBuilder.m
//  ObjC2yUML
//
//  Created by Sam Taylor on 12/05/2013.
//  Copyright (c) 2013 darkFunction Software. All rights reserved.
//

#import "DFyUMLBuilder.h"
#import "DFClassParser.h"
#import "DFClassDefinition.h"
#import "DFImplementationFinder.h"
#import "DFPropertyDefinition.h"
#import "DFProtocolDefinition.h"

@interface DFyUMLBuilder ( /* Private */ )
@property (nonatomic) NSArray* fileNames;
@property (nonatomic) NSDictionary* classDefinitions;
@property (nonatomic) NSDictionary* protocolDefinitions;
@property (nonatomic) id currentDefintion;
@end

@implementation DFyUMLBuilder

- (id)initWithFilenames:(NSArray*)fileNames {
    self  = [super init];
    if (self) {
        _fileNames = fileNames;
    }
    return self;
}

- (NSString*)buildyUML {
    
    // Hmm. Think it might be possible to do this all in one go by getting translation unit associated with an
    // implementation cursor and querying it for superclass etc... TODO: investigate
    
    DFImplementationFinder* implementationFinder = [[DFImplementationFinder alloc] initWithFilenames:self.fileNames];
    self.classDefinitions = [implementationFinder createClassDefinitions];
    self.protocolDefinitions = [NSMutableDictionary dictionary];
    
    [self.fileNames enumerateObjectsUsingBlock:^(NSString* obj, NSUInteger idx, BOOL *stop) {
        @autoreleasepool {
            DFClassParser* parser = [[DFClassParser alloc] initWithFileName:obj];
            parser.delegate = self;
            [parser parseWithCompletion:^(NSError* error){
                
            }];
        }
    }];
    
    // Now we have a model of the parts we are interested in
    
    // Classes
    NSMutableString* yUML = [[NSMutableString alloc] init];
    [self.classDefinitions enumerateKeysAndObjectsUsingBlock:^(NSString* key, DFClassDefinition* classDef, BOOL *stop) {
        if (classDef.superclassDef) {
            [yUML appendFormat:@"[%@]^-[%@],\n", classDef.superclassDef.name, classDef.name];
        } else {
            [yUML appendFormat:@"[%@],\n", classDef.name];
        }
        [classDef.propertyDefs enumerateKeysAndObjectsUsingBlock:^(NSString* key, DFPropertyDefinition* propertyDef, BOOL *stop) {
            [yUML appendFormat:propertyDef.isWeak ? (@"[%@]+->[%@],\n") : (@"[%@]++->[%@],\n"), classDef.name, propertyDef.name];
        }];
    
        [classDef.protocols enumerateObjectsUsingBlock:^(DFProtocolDefinition* protoDef, NSUInteger idx, BOOL *stop) {
            [yUML appendFormat:@"[%@]^-.-[%@],\n", protoDef.name, classDef.name];
        }];
        
    }];
    
    self.classDefinitions = nil;
    self.protocolDefinitions = nil;

    return yUML;
}

- (void)classParser:(id)parser foundDeclaration:(const CXIdxDeclInfo *)declaration {
    const char * const cName = declaration->entityInfo->name;
    if (cName == NULL)
        return;

    NSString *declarationName = [NSString stringWithUTF8String:cName];
    
    switch (declaration->entityInfo->kind) {
        case CXIdxEntity_ObjCClass:
        {            
            // Is it an implementation we have previously found?
            DFClassDefinition* classDefinition = [self.classDefinitions objectForKey:declarationName];
            if (classDefinition) {
                self.currentDefintion = classDefinition;
                
                const CXIdxObjCInterfaceDeclInfo* declarationInfo = clang_index_getObjCInterfaceDeclInfo(declaration);
                if (declarationInfo) {
                    const CXIdxObjCContainerDeclInfo* containerInfo = clang_index_getObjCContainerDeclInfo(declaration);
                    if (containerInfo && containerInfo->kind == CXIdxObjCContainer_Interface) {
                        
                        // Find superclass
                        const CXIdxBaseClassInfo* superclassInfo = declarationInfo->superInfo;
                        if (superclassInfo) {
                            const char* cName = superclassInfo->base->name;
                            if (cName) {
                                NSString* name = [NSString stringWithUTF8String:cName];
                                
                                // Interested?
                                //if ([self.classDefinitions objectForKey:name])
                                {
                                    DFClassDefinition* superclassDefinition = [[DFClassDefinition alloc] initWithName:name];
                                    classDefinition.superclassDef = superclassDefinition;
                                }
                            }
                            cName = NULL;
                        }
                        
                        // Find protocols
                        for (int i=0; i<declarationInfo->protocols->numProtocols; ++i) {
                            const CXIdxObjCProtocolRefInfo* protocolRefInfo = declarationInfo->protocols->protocols[i];
                            NSString* protocolName = [NSString stringWithUTF8String:protocolRefInfo->protocol->name];
                            
                            DFProtocolDefinition* protocolDefinition = [self.protocolDefinitions objectForKey:protocolName];
                            if (![classDefinition.protocols containsObject:protocolDefinition]) {
                                [classDefinition.protocols addObject:protocolDefinition];
                            }
                        }
                    }
                }
            } else {
                self.currentDefintion = nil;
            }
            break;
        }
        case CXIdxEntity_ObjCCategory:
            self.currentDefintion = nil;
            break;
        case CXIdxEntity_ObjCProtocol:
        {
            if (![self.protocolDefinitions objectForKey:declarationName]) {
                DFProtocolDefinition* protocolDefinition = [[DFProtocolDefinition alloc] initWithName:declarationName];
                [self.protocolDefinitions setValue:protocolDefinition forKey:declarationName];
                self.currentDefintion = protocolDefinition;
            }
            break;
        }
        case CXIdxEntity_ObjCProperty:
        {
            // Properties in classes we are interested in
            if (self.currentDefintion) {
                DFClassDefinition* classDefintion = (DFClassDefinition*)self.currentDefintion;
                
                const CXIdxObjCPropertyDeclInfo *propertyDeclaration = clang_index_getObjCPropertyDeclInfo(declaration);
                if (propertyDeclaration) {
                    NSString* typeEncoding = [NSString stringWithUTF8String:clang_getCString(clang_getDeclObjCTypeEncoding(propertyDeclaration->declInfo->cursor))];
                    DFPropertyDefinition* propertyDef = [[DFPropertyDefinition alloc] initWithClangEncoding:typeEncoding];
                    
                    // Does it reference an instance of one of the classes we found an implementation for?
                    if ([self isKeyElement:propertyDef.name]) {
                        if (![classDefintion.propertyDefs objectForKey:propertyDef]) {
                            [classDefintion.propertyDefs setObject:propertyDef forKey:declarationName];
                        }
                    }
                }
            }
            break;
        }
        default:
            break;
    }
}

- (BOOL)isKeyElement:(NSString*)name {
    return ( [self.classDefinitions objectForKey:name] || [self.protocolDefinitions objectForKey:name] );
}

@end
