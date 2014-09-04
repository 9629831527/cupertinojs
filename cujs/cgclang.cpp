//
//  cgjsclang.cpp
//  cujs
//
//  Created by Jerry Marino on 8/2/14.
//  Copyright (c) 2014 Jerry Marino. All rights reserved.
//

#include <clang-c/Index.h>

#include "cujsutils.h"
#include "cgclang.h"
#include "cujsenvironment.h"

#define CGJSDEBUG 0
#define ILOG(A, ...) if (CGJSDEBUG){ printf(A,##__VA_ARGS__), printf("\n");}

using namespace cujs;

ObjCClass::ObjCClass(std::string name) {
    _name = name;
}

void printDiagnostics(CXTranslationUnit translationUnit);
void printTokenInfo(CXTranslationUnit translationUnit,CXToken currentToken);
void printCursorTokens(CXTranslationUnit translationUnit,CXCursor currentCursor);

CXChildVisitResult cursorVisitor(CXCursor cursor, CXCursor parent, CXClientData client_data);
CXChildVisitResult functionDeclVisitor(CXCursor cursor, CXCursor parent, CXClientData client_data);
CXChildVisitResult structDeclVisitor(CXCursor cursor, CXCursor parent, CXClientData client_data);

//TODO: standardized with other env vars
static std::string ENV_PROJECT_ROOT_DIR("CUJS_ENV_PROJECT_ROOT_DIR");

std::string GetSDK(){
    auto sdkEnv = get_env_var(COMPILE_ENV_SDKROOT);
    if (!sdkEnv.length()) {
        return "";
    }
    
    return string_format("-isysroot%s", sdkEnv.c_str());
}

std::string GetArch(){
    return get_env_var(COMPILE_ENV_ARCHS).c_str();
}

TranslationUnitOptions TranslationUnitOptions::OptionsWithFile(std::string name){
    TranslationUnitOptions options;
 
    std::vector<const char *>args;
    
    args.push_back("-I/usr/include");
   
    args.push_back("-I.");
    args.push_back("-c");
    args.push_back("-x");
    args.push_back("objective-c");

    args.push_back("-arch");
    auto arch = GetArch();
    if (arch.size()) {
        args.push_back(strdup(arch.data()));
    }
  
    auto sdk = GetSDK();
    if (sdk.length()) {
        args.push_back(strdup(sdk.c_str()));
    }
    
    std::string rootDir = get_env_var(ENV_PROJECT_ROOT_DIR);
    options.file = string_format("%s/%s", rootDir.c_str(), name.c_str());
    options.args = args;
    
    ILOG("Import file %s", options.file.c_str());
    return options;
}

ClangFile::ClangFile(std::string name) {
    _name = name;
    _currentClass = NULL;
    
    CXIndex index = clang_createIndex(0, 0);

    TranslationUnitOptions options = TranslationUnitOptions::OptionsWithFile(name);
    CXTranslationUnit translationUnit = clang_parseTranslationUnit(index, options.file.c_str(), &options.args[0], (int)options.args.size(), NULL, 0, CXTranslationUnit_None);
    CXCursor rootCursor = clang_getTranslationUnitCursor(translationUnit);

    clang_visitChildren(rootCursor, *cursorVisitor, this);
    clang_disposeTranslationUnit(translationUnit);
    clang_disposeIndex(index);
    
    assert(translationUnit && "bad import");
}

ClangFile::~ClangFile() {}

#pragma mark - Debug

void printDiagnostics(CXTranslationUnit translationUnit){
    int nbDiag = clang_getNumDiagnostics(translationUnit);
    ILOG("There is %i diagnostics\n",nbDiag);
    
    for (unsigned int currentDiag = 0; currentDiag < nbDiag; ++currentDiag) {
        CXDiagnostic diagnotic = clang_getDiagnostic(translationUnit, currentDiag);
        CXString errorString = clang_formatDiagnostic(diagnotic,clang_defaultDiagnosticDisplayOptions());
        ILOG("%s\n", clang_getCString(errorString));
        clang_disposeString(errorString);
    }
}

void printTokenInfo(CXTranslationUnit translationUnit,CXToken currentToken) {
    CXString tokenString = clang_getTokenSpelling(translationUnit, currentToken);
    CXTokenKind kind = clang_getTokenKind(currentToken);
    
    switch (kind) {
        case CXToken_Comment:
            ILOG("Token : %s \t| COMMENT\n", clang_getCString(tokenString));
            break;
        case CXToken_Identifier:
            ILOG("Token : %s \t| IDENTIFIER\n", clang_getCString(tokenString));
            break;
        case CXToken_Keyword:
            ILOG("Token : %s \t| KEYWORD\n", clang_getCString(tokenString));
            break;
        case CXToken_Literal:
            ILOG("Token : %s \t| LITERAL\n", clang_getCString(tokenString));
            break;
        case CXToken_Punctuation:
            ILOG("Token : %s \t| PUNCTUATION\n", clang_getCString(tokenString));
            break;
        default:
            break;
    }
}

void printCursorTokens(CXTranslationUnit translationUnit, CXCursor currentCursor) {
    CXToken *tokens;
    unsigned int nbTokens;
    CXSourceRange srcRange;
    
    srcRange = clang_getCursorExtent(currentCursor);
    
    clang_tokenize(translationUnit, srcRange, &tokens, &nbTokens);
    
    for (int i = 0; i < nbTokens; ++i) {
        CXToken currentToken = tokens[i];
        printTokenInfo(translationUnit,currentToken);
    }
    
    clang_disposeTokens(translationUnit,tokens,nbTokens);
}

//TODO : remove this cruft!
static CXType parentType;

CXChildVisitResult cursorVisitor(CXCursor cursor, CXCursor parent, CXClientData client_data){
    CXCursorKind kind = clang_getCursorKind(cursor);
    CXString nameSpelling = clang_getCursorSpelling(cursor);
    std::string name = clang_getCString(nameSpelling);

    ILOG("cursor '%s' kind %d\n", name.c_str(), kind);
    
    ClangFile *file = (ClangFile *)client_data;
    
    if (kind == CXCursor_ObjCInterfaceDecl || kind == CXCursor_ObjCCategoryDecl) {
        ILOG("\tclass '%s'\n", name.c_str());
       
        ObjCClass *currentClass = new ObjCClass(name);
        file->_classes.insert(currentClass);
        file->_currentClass = currentClass;
        return CXChildVisit_Recurse;
    }
    
    if ((kind ==  CXCursor_ObjCClassMethodDecl || kind == CXCursor_ObjCInstanceMethodDecl)
        && file->_currentClass){
        ObjCMethod *method = new ObjCMethod;
        method->name = name;

        auto retType = clang_getCursorResultType(cursor);
        method->type = (ObjCType)retType.kind;
        
        file->_currentMethod = method;
        ILOG("method '%s' type: %d \n",method->name.c_str(), retType.kind);
       
        // visit method childs
        clang_visitChildren(cursor, *functionDeclVisitor,file);
        ILOG("nb Params : %lu'\n", method->params.size());
        file->_currentClass->_methods.push_back(method);
        return CXChildVisit_Continue;
    }

    CXType type = clang_getCursorType(cursor);
    if ((ObjCType)type.kind == ObjCType_Record) {
        
        ObjCStruct *aStruct = new ObjCStruct;
        aStruct->name = name;
        aStruct->type = (ObjCType)type.kind;
      
        file->_currentStruct = aStruct;
       
        aStruct->size = clang_Type_getSizeOf(type);
        file->_curentOffset = 0;
        parentType = type;
       
        ILOG("struct '%s' ",aStruct->name.c_str());
        ILOG("encoding '%s' ", clang_getCString(clang_getDeclObjCTypeEncoding(cursor)));
        ILOG("size '%lul' \n", aStruct->size);

        clang_visitChildren(cursor, *structDeclVisitor, file);
        file->_structs.insert(file->_currentStruct);
        return CXChildVisit_Continue;
    }
    
    if (kind == CXCursor_TypedefDecl){
        ObjCTypeDef *aTypeDef = new ObjCTypeDef;
        aTypeDef->name = name;
        
        CXType typeDefType = clang_getTypedefDeclUnderlyingType(cursor);
        aTypeDef->type = (ObjCType)typeDefType.kind;

        CXCursor typedefCursor = clang_getTypeDeclaration(typeDefType);
        aTypeDef->encodingString = clang_getCString(clang_getDeclObjCTypeEncoding(typedefCursor));
        file->_typeDefs.insert(aTypeDef);
        
        return CXChildVisit_Continue;
    }

    return CXChildVisit_Recurse;
}

CXChildVisitResult functionDeclVisitor(CXCursor cursor, CXCursor parent, CXClientData client_data) {
    CXCursorKind kind = clang_getCursorKind(cursor);
    CXType type = clang_getCursorType(cursor);

    ClangFile *file = (ClangFile *)client_data;
    
    if (kind == CXCursor_ParmDecl){
        CXString name = clang_getCursorSpelling(cursor);
        auto param = (ObjCMethodParam){clang_getCString(name), (ObjCType)type.kind};
        file->_currentMethod->params.push_back(param);
        ILOG("\tparameter: '%s' of type '%i'\n", param.name.c_str(), param.type);
    }
    
    return CXChildVisit_Continue;
}

CXChildVisitResult structDeclVisitor(CXCursor cursor, CXCursor parent, CXClientData client_data) {
    CXCursorKind kind = clang_getCursorKind(cursor);
    CXType type = clang_getCursorType(cursor);
    ClangFile *file = (ClangFile *)client_data;
    
    if (kind == CXCursor_FieldDecl){
        ObjCField field = (ObjCField){};
        CXString name = clang_getCursorSpelling(cursor);
        field.name = clang_getCString(name);
        
        long long offset = file->_curentOffset;
        field.offset = offset;
        
        if (offset == CXTypeLayoutError_Incomplete || offset == CXTypeLayoutError_Dependent) {
            ILOG("warning FIELD ERROR: %s %d", field.name.c_str(), (int)offset);
        }
        
        field.type = (ObjCType)type.kind;
       
        if (field.type == ObjCType_Typedef) {
            CXCursor typeDefCursr = clang_getTypeDeclaration(type);
            auto name = clang_getCString(clang_getCursorSpelling(typeDefCursr));
            ILOG("ObjCType_Typedef field name %s\n", name);
            field.typeName = name;
        }


        file->_curentOffset += clang_Type_getSizeOf(type);
        ILOG("\tfield: '%s' of type '%i' offset %d \n", field.name.c_str(), field.type, (int)field.offset);
        file->_currentStruct->fields.push_back(field);
        return CXChildVisit_Continue;
    }
    
    return CXChildVisit_Continue;
}
