//
//  DFClassParser.m
//  ObjC2yUML
//
//  Created by Sam Taylor on 11/05/2013.
//  Copyright (c) 2013 darkFunction Software. All rights reserved.
//

#import "DFClassParser.h"
#import "DFClassParserDelegate.h"

// Supported indexer callback functions
void indexDeclaration(CXClientData client_data, const CXIdxDeclInfo *declaration);
 
static IndexerCallbacks indexerCallbacks = {
    .indexDeclaration = indexDeclaration,
};

@interface DFClassParser ( /* Private */ )
@property (nonatomic) NSString* fileName;
@end

@implementation DFClassParser

- (id)initWithFileName:(NSString*)fileName {
    if(![[NSFileManager defaultManager] fileExistsAtPath:fileName]) {
        return nil;
    }
    
    self = [super init];
    if (self) {
        self.fileName = [fileName copy];
    }
    return self;
}

- (void)parseWithCompletion:(void(^)(NSError*))completion {

    CXIndex index = clang_createIndex(1, 1);
    if (!index) {
        if (completion) {
            completion([[NSError alloc] initWithDomain:@"ClangParseErrorDomain" code:DFClangParseErrorInit userInfo:nil]);
        }
        return;
    }
    
    CXTranslationUnit translationUnit = clang_parseTranslationUnit(index, [self.fileName fileSystemRepresentation], NULL, 0, NULL, 0, CXTranslationUnit_None);
    if (!translationUnit) {
        if (completion) {
            completion([[NSError alloc] initWithDomain:@"ClangParseErrorDomain" code:DFClangParseErrorCompilation userInfo:nil]);
        }
        return;
    }
    
    CXIndexAction action = clang_IndexAction_create(index);

    int indexResult = clang_indexTranslationUnit(action,
                                                 (__bridge CXClientData)self,
                                                 &indexerCallbacks,
                                                 sizeof(indexerCallbacks),
                                                 CXIndexOpt_SuppressWarnings,
                                                 translationUnit);
    if (completion) {
        completion(nil);
    }
    
    clang_IndexAction_dispose(action);
    clang_disposeTranslationUnit(translationUnit);
    clang_disposeIndex(index);
    (void) indexResult;
    
}

#pragma mark - Indexer callbacks

void indexDeclaration(CXClientData client_data, const CXIdxDeclInfo *declaration) {
    DFClassParser* parser = (__bridge DFClassParser*)client_data;
    [parser.delegate classParser:parser foundDeclaration:declaration];
}


@end
