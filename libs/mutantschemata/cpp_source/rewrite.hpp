///------------------------------------------------------------------------------
// Mutant schemata using Clang rewriter and RecursiveASTVisitor
//
// Sten Vercammem (sten.vercammen@uantwerpen.be)
//------------------------------------------------------------------------------

#include <set>
#include <sstream>
#include <vector>
#include <fstream>
#include <functional>
#include <map>

#include "clang/AST/AST.h"
#include "clang/AST/ASTContext.h"
#include "clang/AST/ASTConsumer.h"
#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/Frontend/ASTConsumers.h"
#include "clang/Frontend/FrontendActions.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Lex/Lexer.h"
#include "clang/Sema/Sema.h"
#include "clang/Sema/SemaConsumer.h"
#include "clang/Tooling/CommonOptionsParser.h"
#include "clang/Tooling/Tooling.h"
#include "clang/Rewrite/Core/Rewriter.h"

#ifndef MS_CLANG_REWRITE
#define MS_CLANG_REWRITE


#ifndef STANDALONE
static SchemataApiCpp *sac;
#endif

std::string restrictedPath;

// defines to control what happens \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\|
bool multiAnalysePerFile = false;   // multi-analyse can create multiple AST's for the same file, use in case a file is compiled mulitple times with different flags
// config mutant schemata
bool ROR = true;    // Relational Operator Replacement  <,<=,>,>=,==,!=,true,false
bool AOR = true;    // Arithmetic Operator Replacement
bool LCR = true;    // Logical Connector Replacement
//bool UOI = true;    // Unary Operator Insertion
//bool ABS = true;    // Absolute Value Insertion
///////////////////////////////////////////////////////////////////////////////|


// global clang vars \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\|
clang::Rewriter rewriter;
clang::SourceManager *SourceManager;
///////////////////////////////////////////////////////////////////////////////|


// global vars for mutant schemata housekeeping \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\|
std::vector<std::string> SourcePaths;
std::set<std::string> VisitedSourcePaths;
unsigned mutant_count = 0;
unsigned insertedMutants_count = 0;
///////////////////////////////////////////////////////////////////////////////|

// look for the restricted path withing the filename (filename is absolutepath ex. /path/to/src/file1.cpp and restrictedPath is /path/to/src/)
bool isWithinRestricted(std::string filename){
  return filename.find(restrictedPath) != std::string::npos;
}


// variables need to uniquely insert meta-mutants \\\\\\\\\\\\\\\\\\\\\\\\\\\\\|
struct MutantInsert {
    const clang::FileEntry *fE; // needed to calc FID
    unsigned exprOffs;
    unsigned bracketsOffs;
    
    unsigned lineStart, columnStart;
    unsigned changeOffsStart, changeOffsEnd;
    std::string change;
    
    std::string expr;
    std::size_t exprHash;
    std::string brackets;
    
    bool valid;
    bool consty;
    bool templaty;
    
    MutantInsert(const clang::FileEntry *f, unsigned int eO, unsigned int bO, std::string e, std::string b, bool v): fE(f), exprOffs(eO), bracketsOffs(bO), expr(e), exprHash(std::hash<std::string>{}(e)), brackets(b), valid(v) {}
};

std::vector<MutantInsert*> mutantInserts;
// custom comperator for mutants based on their FileID (FileEntry) and location (offsets)
struct mutantLocComp {
    bool operator() (const MutantInsert *lhs, const MutantInsert *rhs) const {
        if (lhs->fE == rhs->fE) {
            if (lhs->exprOffs == rhs->exprOffs) {
                if (lhs->bracketsOffs == rhs->bracketsOffs) {
                    return lhs->exprHash < rhs->exprHash;
                }
                return lhs->bracketsOffs < rhs->bracketsOffs;
            }
            return lhs->exprOffs < rhs->exprOffs;
        }
        return lhs->fE < rhs->fE;
    }
};
// keep an ordered set of the created mutants to prevent duplicates
// TODO optimise: 1 per file, only overwrite when new mutants were added
std::set<MutantInsert*, mutantLocComp> insertedMutants;
///////////////////////////////////////////////////////////////////////////////|

// variables need to identify const/conexpr constructs \\\\\\\\\\\\\\\\\\\\\\\\|
struct ConstLoc {
    unsigned start;
    unsigned end;
    
    // sort based on first, then on second
    bool operator()(const ConstLoc &lhs, const ConstLoc &rhs) {
        if (lhs.start == rhs.start) {
            return lhs.end < rhs.end;
        }
        return lhs.start < rhs.start;
    }
};
// ordered set of all const/constexpr locations
std::map<const clang::FileEntry*, std::set<ConstLoc, ConstLoc>*> constLocs;
std::map<const clang::FileEntry*, std::set<ConstLoc, ConstLoc>*> templateLocs;
///////////////////////////////////////////////////////////////////////////////|


// needed functionality not (publically) available in clang \\\\\\\\\\\\\\\\\\\|
/**
 * Return true if this character is non-new-line whitespace:
 * ' ', '\\t', '\\f', '\\v', '\\r'.
 */
static inline bool isWhitespaceExceptNL(unsigned char c) {
    switch (c) {
        case ' ':
        case '\t':
        case '\f':
        case '\v':
        case '\r':
            return true;
        default:
            return false;
    }
}

class MutantRewriter: public clang::Rewriter {
public:
    bool InsertText(const clang::FileEntry *fE, unsigned StartOffs, StringRef Str, bool InsertAfter = true, bool indentNewLines = false) {
        clang::FileID FID = this->getSourceMgr().translateFile(fE);
        if (!FID.getHashValue()) {
            FID = this->getSourceMgr().createFileID(fE, clang::SourceLocation(), clang::SrcMgr::CharacteristicKind::C_User);
        }
        
        llvm::SmallString<128> indentedStr;
        if (indentNewLines && Str.find('\n') != StringRef::npos) {
            StringRef MB = this->getSourceMgr().getBufferData(FID);
            
            unsigned lineNo = this->getSourceMgr().getLineNumber(FID, StartOffs) - 1;
            const clang::SrcMgr::ContentCache *Content = this->getSourceMgr().getSLocEntry(FID).getFile().getContentCache();
            unsigned lineOffs = Content->SourceLineCache[lineNo];
            
            // Find the whitespace at the start of the line.
            StringRef indentSpace;
            {
                unsigned i = lineOffs;
                while (isWhitespaceExceptNL(MB[i]))
                    ++i;
                indentSpace = MB.substr(lineOffs, i-lineOffs);
            }
            
            llvm::SmallVector<StringRef, 4> lines;
            Str.split(lines, "\n");
            
            for (unsigned i = 0, e = lines.size(); i != e; ++i) {
                indentedStr += lines[i];
                if (i < e-1) {
                    indentedStr += '\n';
                    indentedStr += indentSpace;
                }
            }
            Str = indentedStr.str();
        }
        
        getEditBuffer(FID).InsertText(StartOffs, Str, InsertAfter);
        return false;
    }
};

// fix backWards compatibility
clang::SourceLocation getSR(clang::CharSourceRange SR, bool afterToken = false) {
    return afterToken? SR.getEnd(): SR.getBegin();
}
// fix backWards compatibility
clang::SourceLocation getSR(std::pair<clang::SourceLocation, clang::SourceLocation> SR, bool afterToken = false) {
    return afterToken? SR.second: SR.first;
}

clang::SourceLocation getFileLocSlowCase(clang::SourceLocation Loc, bool afterToken = false) {
    do {
        if (SourceManager->isMacroArgExpansion(Loc)) {
            Loc = SourceManager->getImmediateSpellingLoc(Loc);
        } else {
            Loc = getSR(SourceManager->getImmediateExpansionRange(Loc), afterToken);
        }
    } while (!Loc.isFileID());
    return Loc;
}

clang::SourceLocation getFileLoc(clang::SourceLocation Loc, bool afterToken = false) {
    if (Loc.isFileID()) return Loc;
    return getFileLocSlowCase(Loc, afterToken);
}


/**
 * Calculates offset of location, optionally increased with the range of the last token
 * Returns true on failure
 */
bool calculateOffsetLoc(clang::SourceLocation Loc, const clang::FileEntry *&fE, unsigned &offset, unsigned &lineNr, unsigned &columnNr, bool afterToken = false) {
    // make sure we use the correct Loc, MACRO's needs to be tracked back to their spelling location
    Loc = getFileLoc(Loc, afterToken);
    if (!clang::Rewriter::isRewritable(Loc)) {
        llvm::errs() << "not rewritable !!!!!\n";
        return true;
    }
    assert(Loc.isValid() && "Invalid location");
    /*
     * Get FileID and offset from the Location.
     * Offset is the offset in the file, so this is a "constant".
     * FileID's can change depending on the order of opening, so we can't trust this.
     * We'll store the FileEntry and infer the FileID from it when we need it.
     */
    std::pair<clang::FileID, unsigned> V = SourceManager->getDecomposedLoc(Loc);
    clang::FileID FID = V.first;
    fE = SourceManager->getFileEntryForID(FID);
    offset = V.second;
    
    //TODO note that this is expensive!!!
    lineNr = SourceManager->getLineNumber(V.first, V.second);
    columnNr = SourceManager->getColumnNumber(V.first, V.second);
    
    
    if (afterToken) {
        // we want the offset after the last token, so we need to calculate the range of the last token
        clang::Rewriter::RewriteOptions rangeOpts;
        rangeOpts.IncludeInsertsAtBeginOfRange = false;
        unsigned tokenLength = rewriter.getRangeSize(clang::SourceRange(Loc, Loc), rangeOpts);
        offset += tokenLength;
        columnNr += tokenLength;
    }
    return false;
}
///////////////////////////////////////////////////////////////////////////////|

// functionality to write changed files to disk \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\|
/**
 * Write the modified AST to files.
 * Either in place, or with suffix _mutated
 *
 * Note: use false, as inPlace causes a sementation fault in clang's sourcemaneger calling the ComputeLineNumbers function, when used in the EndSourceFileAction.
 * Caling rewriter.overwriteChangedFiles() after Tool.run causes a segmentation fault as some rewrite buffers are already deconstructed.
 * This is why we need to use temp files.
 */
void writeChangedFiles(bool inPlace) {
    if (inPlace) {
        rewriter.overwriteChangedFiles();
    } else {
        /*
         * iterate through rewrite buffer
         *
         * Note: when a (system) file is visited without being mutated,
         * then it will currently also turn up here (as an editBuffer was created for it)
         */
        for (std::map<clang::FileID, clang::RewriteBuffer>::iterator I = rewriter.buffer_begin(), E = rewriter.buffer_end(); I != E; ++I) {
            const clang::FileEntry *file = rewriter.getSourceMgr().getFileEntryForID(I->first);
            if (file) {
	      if (file->isValid()) {
                    // Mark changed file as visited, so we know it was changed.
                    VisitedSourcePaths.insert(file->tryGetRealPathName());
                    
                    // include MUTANT_NR definition in each TU
                    std::string include;
                    include = "#ifndef schemataFunctions_h\n";
                    include += "#define schemataFunctions_h\n";
                    include += "#include <cstdlib>\n";
                    include += "static const int MUTANT_NR = std::atoi(getenv(\"MUTANT_NR\"));\n";
//                    include += "static void __schemataENVSetter(void) __attribute__((constructor));\n";
//                    include += "static void __schemataENVSetter(void) {MUTANT_NR = std::atoi(getenv(\"MUTANT_NR\"));}\n";
                    include += "#endif /* schemataFunctions_h */\n";
                    include += "\n";
                    
                    I->second.InsertTextAfter(0, include);
                    
                    // write what's in the buffer to a temporary file
                    // placed here to prevent writing the mutated file multiple times
                    std::error_code error_code;
                    //                        std::string fileName = file->getName().str() + "_mutated_" + std::to_string(mutant_count);
                    std::string fileName = file->getName().str() + "_mutated";
                    llvm::raw_fd_ostream outFile(fileName, error_code, llvm::sys::fs::F_None);
                    outFile << std::string(I->second.begin(), I->second.end());
                    outFile.close();
                    
                    // debug output
                    //llvm::errs() << "Mutated file: " << file->getName().str() << "\n";
                }
            } else {
                // not an actual file
            }
        }
    }
}


/**
 * write the temporary files over the original ones
 */
void overWriteChangedFile() {
    for (std::string fileName: VisitedSourcePaths) {
        // deletes the old file
        std::string oldFileName = fileName + "_mutated";
        if (std::rename(oldFileName.c_str(), fileName.c_str()) != 0) {
            std::string err = "Error renaming file, " + oldFileName + " not found";
            std::perror(err.c_str());
        }
    }
}
///////////////////////////////////////////////////////////////////////////////|


enum Singleton {
    LHS,
    RHS,
    False,
    True,
    NotASingleTon
};

// actual clang functions to traverse AST \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\|
class MutatingVisitor: public clang::RecursiveASTVisitor<MutatingVisitor> {
private:
    clang::ASTContext *astContext;
    clang::PrintingPolicy pp;
    
    bool makesSense(clang::BinaryOperator *binOp, clang::BinaryOperatorKind Opc) {
        assert(sema && "no Sema");
        sema->getDiagnostics().setErrorLimit(0);
        
        bool rem_ok = true;
        // TODO dirty hack to ensure that the rem operator does not cause compilation faults.
        // for some reason, when getting templated stored values are not getting verified:
        // _Tp val[m]; -> val[i]%val[j] for BuildBinOp this is perfectly fine even if _Tp is float/double
        if (Opc == clang::BO_Rem) {
            if (!binOp->getLHS()->getType()->hasIntegerRepresentation() || !binOp->getRHS()->getType()->hasIntegerRepresentation()) {
                rem_ok = false;
            }
        }
        
        clang::ExprResult expr = sema->BuildBinOp(sema->getCurScope(), binOp->getExprLoc(), Opc, binOp->getLHS(), binOp->getRHS());
        //TODO sema doesn't (yet) take into account -Werror -> -Werror=type-limit
        return !expr.isInvalid() && expr.isUsable() && rem_ok;
    }

    std::string convertExpressionToString(clang::Expr *E) {
        clang::SourceManager &SM = astContext->getSourceManager();
        clang::SourceLocation b = getFileLoc(E->getLocStart(), false);
        clang::SourceLocation _e = getFileLoc(E->getLocEnd(), true);
        clang::SourceLocation e = clang::Lexer::getLocForEndOfToken(_e, 0, SM, astContext->getLangOpts());
        return std::string(SM.getCharacterData(b), SM.getCharacterData(e) - SM.getCharacterData(b));
    }

    /**
     * Craete meta-mutants for the operation at binOp with the provided operators in the lists
     *
     * Note: This funciton does not (yet) use the Lexer to retrieve the sourceText.
     * Macro's etc. can thus be expanded, the operands might thus look slightly different than the original code
     */
    void insertMutantSchemata(clang::BinaryOperator *binOp, std::initializer_list<clang::BinaryOperatorKind> list, std::initializer_list<Singleton> singletons) {
        // get lhs of expression
        std::string lhs = convertExpressionToString(binOp->getLHS());
        
        // get rhs of expression
        std::string rhs = convertExpressionToString(binOp->getRHS());
        
        // get expression with mutant schemata
        std::string newExpr;
        std::string endBracket = ")";
        for (const auto &elem: list) {
            if (binOp->getOpcode() != elem) {
                bool validMutant = makesSense(binOp, elem);
                newExpr = lhs;
                newExpr += " ";
                newExpr += clang::BinaryOperator::getOpcodeStr(elem).str();
                newExpr += " ";
                newExpr += rhs;
                createAndStoreActualMutant(binOp, newExpr, endBracket, validMutant, Singleton::NotASingleTon, clang::BinaryOperator::getOpcodeStr(elem).str());
                
                if (!validMutant) {
                    llvm::errs() << "compiler found invalid mutant, can't change this to: " << clang::BinaryOperator::getOpcodeStr(elem).str() << "\n";
                }
            }
        }
        
        // check if we need to insert some singletons
        for (const auto &elem: singletons) {
            //TODO return type must be the same when using ? operator
            // This can be an issue with char* + 2 -> NR == 2? 2 : char* + 2
            // In googletest this happens when char* is LHS and we want a bool
            // For now we just add a hardcoded cast whene we dedect that it should be a bool
            
            bool compileOk = true;
            switch (elem) {
                case Singleton::LHS:
                    compileOk = binOp->getType() == binOp->getLHS()->getType();
                    if (binOp->getType().getTypePtr()->isBooleanType()) {
                        newExpr = "bool("+lhs+")";
                    } else {
                        newExpr = lhs;
                    }
                    break;
                case Singleton::RHS:
                    compileOk = binOp->getType() == binOp->getRHS()->getType();
                    if (binOp->getType().getTypePtr()->isBooleanType()) {
                        newExpr = "bool("+rhs+")";
                    } else {
                        newExpr = rhs;
                    }
                    break;
                case Singleton::True:
                    compileOk = binOp->getType().getTypePtr()->isBooleanType();
                    newExpr = "true";
                    break;
                case Singleton::False:
                    compileOk = binOp->getType().getTypePtr()->isBooleanType();
                    newExpr = "false";
                    break;
                default:
                    // continue for loop
                    continue;
            }
            // insert the singleton
            createAndStoreActualMutant(binOp, newExpr, endBracket, compileOk, elem, newExpr);
        }
    }
    
    void createAndStoreActualMutant(const clang::BinaryOperator *binOp, const std::string &newExpr, const std::string &endBracket, bool valid, Singleton singleton, std::string changedExpr) {
        // calculate offset and FileEntry (we don't use FileID as this can change depending on the order of opening files etc.)
        const clang::FileEntry *fE;
        unsigned lineStart, columnStart;
        unsigned exprOffs, bracketsOffs;
        // calculate offset for start of expression
        calculateOffsetLoc(binOp->getLocStart(), fE, exprOffs, lineStart, columnStart);
        // calculate offset for end of exbracketpression
        calculateOffsetLoc(binOp->getLocEnd(), fE, bracketsOffs, lineStart, columnStart, true);
        
        unsigned changeOffsStart, changeOffsEnd;
        
        switch (singleton) {
                // e.g. expression: int r = a + b;
                // calculate the offsets for what we want to replace as in traditional mutation testing
            case Singleton::NotASingleTon:
                // replace only the operator "+"
                calculateOffsetLoc(binOp->getExprLoc(), fE, changeOffsStart, lineStart, columnStart);
                calculateOffsetLoc(binOp->getExprLoc(), fE, changeOffsEnd, lineStart, columnStart, true);
                break;
            case Singleton::LHS:
                // keep the LHS, replace "+ b"
                calculateOffsetLoc(binOp->getExprLoc(), fE, changeOffsStart, lineStart, columnStart);
                calculateOffsetLoc(binOp->getLocEnd(), fE, changeOffsEnd, lineStart, columnStart, true);
                break;
            case Singleton::RHS:
                // keep the RHS, replace "a +"
                calculateOffsetLoc(binOp->getExprLoc(), fE, changeOffsStart, lineStart, columnStart);
                calculateOffsetLoc(binOp->getExprLoc(), fE, changeOffsEnd, lineStart, columnStart, true);
                break;
            case Singleton::True:
                // fall true to false below
            case Singleton::False:
                // keep nothing, replace "a + b"
                changeOffsStart = exprOffs;
                changeOffsEnd = bracketsOffs;
                break;
            default:
                break;
        }
        
        // create and store the created (meta-) mutant
        MutantInsert *mi = new MutantInsert(fE, exprOffs, bracketsOffs, newExpr, endBracket, valid);
        mi->lineStart = lineStart;
        mi->columnStart = columnStart;
        mi->changeOffsStart = changeOffsStart;
        mi->changeOffsEnd = changeOffsEnd;
        mi->change = changedExpr;
        
        insertedMutants.value_comp() = insertedMutants.key_comp();
        std::set<MutantInsert*, mutantLocComp>::iterator it = insertedMutants.find(mi);
        if (it == insertedMutants.end()) {
            mutantInserts.push_back(mi);
            insertedMutants.insert(mi);
            //            llvm::errs() << "inserted mutant in FE: " << std::to_string((long)(mi->fE)) << " @offset: [" << mi->exprOffs << ", " << mi->bracketsOffs << "] | " << mi->expr << "\n";
            mutant_count++; //increase count as we are sure it isn't a duplicated vallid mutant
        } else {
            //            llvm::errs() << "duplicate mutant in FE: " << std::to_string((long)(mi->fE)) << " @offset: [" << mi->exprOffs << ", " << mi->bracketsOffs << "] | " << mi->expr << "\n";
        }
    }
    
    /**
     * Check if we want to mutate this file.
     * (if it isn't a system file)
     */
    bool isfileToMutate(clang::FullSourceLoc FullLocation) {
        const clang::FileEntry *fE = SourceManager->getFileEntryForID(SourceManager->getFileID(FullLocation));
        if (fE) {
	  return !SourceManager->isInSystemHeader(FullLocation) &&
	    !SourceManager->isInExternCSystemHeader(FullLocation) &&
	    isWithinRestricted(fE->tryGetRealPathName().str());
        }
        return false;
    }

    template <class T>
    void insertExcludedLoc(T *declOrSmtm, std::map<const clang::FileEntry*, std::set<ConstLoc, ConstLoc>*> &excludedLocs) {
        const clang::FileEntry *fE;
        unsigned startOffs, endOffs;
        unsigned lineStart, columnStart;
        unsigned lineEnd, columnEnd;
        calculateOffsetLoc(declOrSmtm->getLocStart(), fE, startOffs, lineStart, columnStart);
        calculateOffsetLoc(declOrSmtm->getLocEnd(), fE, endOffs, lineEnd, columnEnd, true);
        
        std::map<const clang::FileEntry*, std::set<ConstLoc, ConstLoc>*>::iterator it = excludedLocs.find(fE);
        if (it == excludedLocs.end()) {
            it = excludedLocs.insert({fE, new std::set<ConstLoc, ConstLoc>()}).first;
        }
        it->second->insert({startOffs, endOffs});
    }
    
public:
    clang::Sema *sema;
    
    explicit MutatingVisitor(clang::CompilerInstance *CI): astContext(&(CI->getASTContext())), pp(astContext->getLangOpts()) {
        SourceManager = &astContext->getSourceManager();
    }
    
    virtual bool VisitDecl(clang::Decl *d) {
        bool consty = false;
        bool constyexpr = false;
        bool templaty = false;
        if (clang::isa<clang::VarDecl>(d)) {
            clang::ValueDecl *valD = clang::cast<clang::ValueDecl>(d);
            clang::QualType qt = valD->getType();
            consty = qt.isConstQualified();
            
            clang::VarDecl *varD = clang::cast<clang::VarDecl>(d);
            constyexpr = varD->isConstexpr();
            
            const clang::Type *t = qt.getTypePtr();
            if (varD->isStaticLocal()) {
                // variable length array declaration cannot have 'static' storage duration
                // static array's lenght must dus be declared by const
                // this is a hack to detect this, TODO find correct clang function for detection
                if (t->isVariableArrayType() || t->isArrayType() || t->isConstantArrayType() || t->isIncompleteArrayType() || t->isDependentSizedArrayType()) {
                    consty = true;
                }
            }
        }
        if (clang::isa<clang::TypeDecl>(d)) {
            // TODO support typedefs (usings etc.)
            consty = true;
        }
        if (clang::isa<clang::TemplateDecl>(d)) {
            // TODO support templates
            templaty = true;
        }

        if (clang::isa<clang::FunctionDecl>(d)) {
            clang::FunctionDecl *funD = clang::cast<clang::FunctionDecl>(d);
            if (funD->getTemplatedKind() != clang::FunctionDecl::TemplatedKind::TK_NonTemplate) {
                templaty = true;
            }
        }

        if (consty || constyexpr) {
            insertExcludedLoc(d, constLocs);
        } else if (templaty) {
            insertExcludedLoc(d, templateLocs);
        }
        return true;
    }
    
    virtual bool VisitStmt(clang::Stmt *s) {
        clang::FullSourceLoc FullLocation = astContext->getFullLoc(s->getLocStart());
        if (!isfileToMutate(FullLocation)) {
            return true;
        }
        
        bool templaty = false;
        
        // mutate all expressions
        if (clang::isa<clang::Expr>(s)) {
            if (clang::isa<clang::BinaryOperator>(s)) {
                clang::BinaryOperator *binOp = clang::cast<clang::BinaryOperator>(s);
                mutateBinaryOperator(binOp);
            } else if (clang::isa<clang::UnaryOperator>(s)) {
                clang::UnaryOperator *unOp = clang::cast<clang::UnaryOperator>(s);
                mutateUnaryOperator(unOp);
            } else if (clang::isa<clang::DeclRefExpr>(s)) {
                // prevent mutating templated expressions as they should be constexpr: e.g.
                // int a = f<1+b> -> b must be const, -> f<MN == 1? 1+b: 1-b> isn't const
                clang::DeclRefExpr *declRefExpr = clang::cast<clang::DeclRefExpr>(s);
                if (declRefExpr->getNumTemplateArgs() > 0) {
                    templaty = true;
                }
            }
        }
                  
        if (templaty) {
            insertExcludedLoc(s, templateLocs);
        }

        return true;
    }
    
private:
    void mutateBinaryOperator(clang::BinaryOperator *binOp) {
        if (ROR) {
            mutateBinaryROR(binOp);
        }
        if (AOR) {
            mutateBinaryAOR(binOp);
        }
        if (LCR) {
            mutateBinaryLCR(binOp);
        }
        //TODO UOI
        //TODO ABS
    }
    
    void mutateUnaryOperator(clang::UnaryOperator *unOp) {
        //TODO ROR
        //TODO AOR
        //TODO LCR
        //TODO UOI
        //TODO ABS
    }
    
    void mutateBinaryROR(clang::BinaryOperator *binOp) {
        const clang::Type *typeLHS = binOp->getLHS()->getType().getTypePtr();
        const clang::Type *typeRHS = binOp->getRHS()->getType().getTypePtr();
        if (typeLHS->isBooleanType() && typeRHS->isBooleanType()) {
            /* mutate booleans
             * only mutate == and !=
             * Mutations such as < for a boolean type is nonsensical in C++ or in C when the type is _Bool.
             */
            switch (binOp->getOpcode()) {
                case clang::BO_EQ:
                    insertMutantSchemata(binOp, {clang::BO_NE}, {Singleton::False});
                    break;
                case clang::BO_NE:
                    insertMutantSchemata(binOp, {clang::BO_EQ}, {Singleton::True});
                    break;
                default:
                    break;
            }
        } else if (typeLHS->isFloatingType() && typeRHS->isFloatingType()) {
            /* Mutate floats
             * Note: that == and != isn't changed compared to the original mutation schema
             * because normally they shouldn't be used for a floating point value but if they are,
             * and it is a valid use, the original schema should work.
             */
            switch (binOp->getOpcode()) {
                    // Relational operators
                case clang::BO_LT:
                    insertMutantSchemata(binOp, {clang::BO_GT}, {Singleton::False});
                    break;
                case clang::BO_GT:
                    insertMutantSchemata(binOp, {clang::BO_LT}, {Singleton::False});
                    break;
                case clang::BO_LE:
                    insertMutantSchemata(binOp, {clang::BO_GT}, {Singleton::True});
                    break;
                case clang::BO_GE:
                    insertMutantSchemata(binOp, {clang::BO_LT}, {Singleton::True});
                    break;
                    // Equality operators
                case clang::BO_EQ:
                    insertMutantSchemata(binOp, {clang::BO_LE, clang::BO_GE}, {Singleton::False});
                    break;
                case clang::BO_NE:
                    insertMutantSchemata(binOp, {clang::BO_LT, clang::BO_GT}, {Singleton::True});
                    break;
                default:
                    break;
            }
        } else if (typeLHS->isEnumeralType() && typeRHS->isEnumeralType()) {
            /* Mutate the same type of enums
             * TODO: verify that the enums are of the same type
             */
            switch (binOp->getOpcode()) {
                    // Relational operators
                case clang::BO_LT:
                    insertMutantSchemata(binOp, {clang::BO_GE, clang::BO_NE}, {Singleton::False});
                    break;
                case clang::BO_GT:
                    insertMutantSchemata(binOp, {clang::BO_GE, clang::BO_NE}, {Singleton::False});
                    break;
                case clang::BO_LE:
                    insertMutantSchemata(binOp, {clang::BO_LT, clang::BO_EQ}, {Singleton::True});
                    break;
                case clang::BO_GE:
                    insertMutantSchemata(binOp, {clang::BO_GT, clang::BO_EQ}, {Singleton::True});
                    break;
                    // Equality operators
                case clang::BO_EQ:
                    insertMutantSchemata(binOp, {}, {Singleton::False});
                    // Specific additional schema for equal: TODO this need further investigation. It seems like the generated mutant can be simplified to true/false but for now I am not doing that because I may be wrong.
                    //TODO if LHS is min enum literal: LHS <= RHS
                    //TODO if LHS is max enum literal: LHS >= RHS
                    //TODO if RHS is min enum literal: LHS >= RHS
                    //TODO if RHS is max enum literal: LHS <= RHS
                    break;
                case clang::BO_NE:
                    insertMutantSchemata(binOp, {}, {Singleton::True});
                    // Specific additional schema for not equal:
                    //TODO if LHS is min enum literal: LHS < RHS
                    //TODO if LHS is max enum literal: LHS > RHS
                    //TODO if RHS is min enum literal: LHS > RHS
                    //TODO if RHS is max enum literal: LHS < RHS
                    break;
                default:
                    break;
            }
        } else if (typeLHS->isPointerType() && typeRHS->isPointerType()) {
            /* Mutate pointers
             * This schema is only applicable when type of the expressions either sides is a pointer type.
             */
            switch (binOp->getOpcode()) {
                    // Relational operators
                case clang::BO_LT:
                    insertMutantSchemata(binOp, {clang::BO_GE, clang::BO_NE}, {Singleton::False});
                    break;
                case clang::BO_GT:
                    insertMutantSchemata(binOp, {clang::BO_GE, clang::BO_NE}, {Singleton::False});
                    break;
                case clang::BO_LE:
                    insertMutantSchemata(binOp, {clang::BO_LT, clang::BO_EQ}, {Singleton::True});
                    break;
                case clang::BO_GE:
                    insertMutantSchemata(binOp, {clang::BO_GT, clang::BO_EQ}, {Singleton::True});
                    break;
                    // Equality operators
                case clang::BO_EQ:
                    insertMutantSchemata(binOp, {clang::BO_NE}, {Singleton::False});
                    break;
                case clang::BO_NE:
                    insertMutantSchemata(binOp, {clang::BO_EQ}, {Singleton::True});
                    break;
                default:
                    break;
            }
        } else {
            //TODO verify this it's ok to use general rules and hope for the best
            switch (binOp->getOpcode()) {
                    // Relational operators
                case clang::BO_LT:
                    insertMutantSchemata(binOp, {clang::BO_LE, clang::BO_NE}, {Singleton::False});
                    break;
                case clang::BO_GT:
                    insertMutantSchemata(binOp, {clang::BO_GE, clang::BO_NE}, {Singleton::False});
                    break;
                case clang::BO_LE:
                    insertMutantSchemata(binOp, {clang::BO_LT, clang::BO_EQ}, {Singleton::True});
                    break;
                case clang::BO_GE:
                    insertMutantSchemata(binOp, {clang::BO_GT, clang::BO_EQ}, {Singleton::True});
                    break;
                    // Equality operators
                case clang::BO_EQ:
                    insertMutantSchemata(binOp, {clang::BO_LE, clang::BO_GE}, {Singleton::False});
                    break;
                case clang::BO_NE:
                    insertMutantSchemata(binOp, {clang::BO_LT, clang::BO_GT}, {Singleton::True});
                    break;
                default:
                    break;
            }
        }
    }
    
    
    void mutateBinaryAOR(clang::BinaryOperator *binOp) {
        switch (binOp->getOpcode()) {
                // Additive operators
            case clang::BO_Add:
                insertMutantSchemata(binOp, {clang::BO_Sub, clang::BO_Mul, clang::BO_Div, clang::BO_Rem}, {Singleton::LHS, Singleton::RHS});
                break;
            case clang::BO_Sub:
                insertMutantSchemata(binOp, {clang::BO_Add, clang::BO_Mul, clang::BO_Div, clang::BO_Rem}, {Singleton::LHS, Singleton::RHS});
                break;
                // Multiplicative operators
            case clang::BO_Mul:
                insertMutantSchemata(binOp, {clang::BO_Sub, clang::BO_Add, clang::BO_Div, clang::BO_Rem}, {Singleton::LHS, Singleton::RHS});
                break;
            case clang::BO_Div:
                insertMutantSchemata(binOp, {clang::BO_Sub, clang::BO_Mul, clang::BO_Add, clang::BO_Rem}, {Singleton::LHS, Singleton::RHS});
                break;
            case clang::BO_Rem:
                insertMutantSchemata(binOp, {clang::BO_Sub, clang::BO_Mul, clang::BO_Div, clang::BO_Add}, {Singleton::LHS, Singleton::RHS});
                break;
            default:
                break;
        }
    }
    
    
    void mutateBinaryLCR(clang::BinaryOperator *binOp) {
        switch (binOp->getOpcode()) {
                // Logical operators
            case clang::BO_LAnd:
                insertMutantSchemata(binOp, {clang::BO_LOr}, {Singleton::True, Singleton::False, Singleton::LHS, Singleton::RHS});
                break;
            case clang::BO_LOr:
                insertMutantSchemata(binOp, {clang::BO_LAnd}, {Singleton::True, Singleton::False, Singleton::LHS, Singleton::RHS});
                break;
                // Bitwise operator
            case clang::BO_And:
                insertMutantSchemata(binOp, {clang::BO_Or}, {Singleton::LHS, Singleton::RHS});
                break;
            case clang::BO_Xor:
                //TODO not implemented by Dextool
                break;
            case clang::BO_Or:
                insertMutantSchemata(binOp, {clang::BO_And}, {Singleton::LHS, Singleton::RHS});
                break;
            default:
                break;
        }
    }
    
    void mutateBinaryUOI(clang::BinaryOperator *binOp) {
    }
    
    void mutateBinaryABS(clang::BinaryOperator *binOp) {
    }
    
};




class MutationConsumer: public clang::SemaConsumer {
private:
    MutatingVisitor *visitor = nullptr;
    clang::Sema *sema = nullptr;
    
public:
    // override in order to pass CI to custom visitor
    explicit MutationConsumer(clang::CompilerInstance *CI): visitor(new MutatingVisitor(CI)) {
        if (sema != nullptr) {
            visitor->sema = sema;
            llvm::errs() << "Huston, we have a s sema\n";
            // limit output of errors
            //sema->getDiagnostics().setErrorLimit(0);
        }
    }
    
    virtual void InitializeSema(clang::Sema &S) {
        sema = &S;
        if (visitor != nullptr) {
            visitor->sema = sema;
        }
        //llvm::errs() << "setting the sema\n";
        
    }
    
    // override to call our custom visitor on the entire source file
    // Note we do this with TU as then the file is parsed, with TopLevelDecl, it's parsed whilst iterating
    virtual void HandleTranslationUnit(clang::ASTContext &Context) {
        // we can use ASTContext to get the TranslationUnitDecl, which is
        // a single Decl that collectively represents the entire source file
        visitor->TraverseDecl(Context.getTranslationUnitDecl());
    }
    
    
    //     // override to call our custom visitor on each top-level Decl
    //     virtual bool HandleTopLevelDecl(clang::DeclGroupRef DG) {
    //     // a DeclGroupRef may have multiple Decls, so we iterate through each one
    //     for (clang::DeclGroupRef::iterator i = DG.begin(), e = DG.end(); i != e; i++) {
    //     clang::Decl *D = *i;
    //     visitor->TraverseDecl(D); // recursively visit each AST node in Decl "D"
    //     }
    //     return true;
    //     }
    
};


unsigned const_count = 0;
unsigned templ_count = 0;
unsigned invalid_count = 0;
unsigned normal_count = 0;

class MutationFrontendAction: public clang::ASTFrontendAction {
    void insertMutantIntoDB(const MutantInsert *mi) {
        insertedMutants_count++;
#ifndef STANDALONE
        CppType::SchemataMutant sm;
        sm.mut_id = insertedMutants_count;
        sm.loc = {mi->lineStart, mi->columnStart};
        sm.offset = {mi->exprOffs, mi->bracketsOffs};
        sm.status = mi->valid? 0: 3;
        sm.inject = CppString::getStr(mi->change.c_str());
        sm.filePath = CppString::getStr(mi->fE->tryGetRealPathName().str().c_str());
        sac->apiInsertSchemataMutant(sm);
#endif
    }
    
public:
    virtual std::unique_ptr<clang::ASTConsumer> CreateASTConsumer(clang::CompilerInstance &CI, StringRef file) {
        // skip this entry if we only want to analyse each file once
        // (we might miss some mutants when doing this)
        if (!multiAnalysePerFile) {
            if (VisitedSourcePaths.find(file) != VisitedSourcePaths.cend()) {
                return nullptr;
            }
        }
        
        // the same file can be analysed multiple times as it is possible that in one project it needs to be compiled multiple times with different flags
        //llvm::errs() << "Starting to mutate the following file and all of it's includes: " << file << "\n";
        llvm::errs() << file << "\n";
        rewriter = clang::Rewriter();
        rewriter.setSourceMgr(CI.getSourceManager(), CI.getLangOpts());
        
        // Mark changed file as visited
        VisitedSourcePaths.insert(file);
        
        return std::unique_ptr<clang::ASTConsumer> (new MutationConsumer(&CI)); // pass CI pointer to ASTConsumer
    }
    
    virtual void EndSourceFileAction() {
        //llvm::errs() << "Adding mutants to database\n";
        unsigned localMutantCount = 1;
        for (std::vector<MutantInsert*>::const_iterator it = mutantInserts.cbegin(); it != mutantInserts.cend(); it++) {
            const MutantInsert *mi = *it;
            bool outsideConst = true;
            bool outsideTempl = true;
            if (mi->valid) {
                auto it = constLocs.find(mi->fE);
                if (it != constLocs.end()) {
                    // there are const expressions
                    for (auto itt = it->second->begin(); itt != it->second->end(); ++itt) {
                        if (itt->start <= mi->exprOffs && itt->end >= mi->bracketsOffs) {
                            outsideConst = false;
                            break;
                        } else if (itt->start > mi->exprOffs) {
                            break;
                        }
                    }
                }
                it = templateLocs.find(mi->fE);
                if (it != templateLocs.end()) {
                    // there are const expressions
                    for (auto itt = it->second->begin(); itt != it->second->end(); ++itt) {
                        if (itt->start <= mi->exprOffs && itt->end >= mi->bracketsOffs) {
                            outsideTempl = false;
                            break;
                        } else if (itt->start > mi->exprOffs) {
                            break;
                        }
                    }
                }

                if (outsideConst && outsideTempl) {
                    // insert mutant before orig expression
                    MutantRewriter *r = (MutantRewriter*)(&rewriter);
                    //mi->startExpr, mi->expr);
                    std::string mutant = "(MUTANT_NR == ";
                    mutant += std::to_string(localMutantCount);
                    mutant += " ? ";
                    mutant += mi->expr;
                    mutant += ": ";
                    r->InsertText(mi->fE, mi->exprOffs, mutant);
                    // insert brackets to close mutant schemata's if statement
                    r->InsertText(mi->fE, mi->bracketsOffs, mi->brackets, true);
                } else {
                    // insert mutant before orig expression
                    MutantRewriter *r = (MutantRewriter*)(&rewriter);
                    //mi->startExpr, mi->expr);
                    std::string mutant = "/*(MUTANT_NR == ";
                    mutant += std::to_string(localMutantCount);
                    mutant += " ? ";
                    mutant += mi->expr;
                    mutant += ": */";
                    r->InsertText(mi->fE, mi->exprOffs, mutant);
                    // insert brackets to close mutant schemata's if statement
                    r->InsertText(mi->fE, mi->bracketsOffs, "/*"+mi->brackets+"*/", true);
                }
            }
            // only insert mutant if we haven't inserted it before
            if (localMutantCount++ >= insertedMutants_count) {
                insertMutantIntoDB(mi);
                if (!outsideConst) {
                    ++const_count;
                }
                if (!outsideTempl) {
                    ++templ_count;
                }
                if (outsideTempl && outsideConst && mi->valid) {
                    ++normal_count;
                }
                if (!mi->valid) {
                    ++invalid_count;
                }
            }
        }
        writeChangedFiles(false);
    }
};


// Apply a custom category to all command-line options so that they are the only ones displayed.
static llvm::cl::OptionCategory MutantShemataCategory("mutation-schemata options");


/**
 * Expecting: argv: -p ../googletest/build filePathToMutate1 filePathToMutate2 ...
 */
#ifndef STANDALONE
int setupClang(int argc, const char **argv, SchemataApiCpp *s, CppString::CppStr restricted) {
    sac = s;
    sac->apiBuildMutant();
    restrictedPath = restricted.cppStr->c_str();
#else
int main(int argc, const char **argv) {
#endif
    
    // parse the command-line args passed to your code
    clang::tooling::CommonOptionsParser op(argc, argv, MutantShemataCategory);
    
    // store all paths to mutate, but fix to absolute path
    for (std::string item: op.getSourcePathList()) {
        SourcePaths.push_back(clang::tooling::getAbsolutePath(item));
    }
    
    // create a new Clang Tool instance (a LibTooling environment)
    clang::tooling::ClangTool Tool(op.getCompilations(), op.getSourcePathList());
    
    // run the Clang Tool, creating a new FrontendAction
    int result = Tool.run(clang::tooling::newFrontendActionFactory<MutationFrontendAction>().get());
    
    /*
     * move newly created files onto the old files
     * Caling rewriter.overwriteChangedFiles() here causes a segmentation fault
     * as some rewrite buffers are already deconstructed.
     * Calling it in the EndSourceFileAction causes a sementation fault
     * in clang's sourcemaneger calling the ComputeLineNumbers function.
     * This is why we need to use temp files.
     */
    overWriteChangedFile();
    
    llvm::errs() << "Mutations found: " << mutant_count << "\n";
    llvm::errs() << "Mutations inserted: " << insertedMutants_count << "\n";
    llvm::errs() << "Const count: " << const_count << "\n";
    llvm::errs() << "template count: " << templ_count << "\n";
    llvm::errs() << "invalid count: " << invalid_count << "\n";
    llvm::errs() << "normal count: " << normal_count << "\n";

    return result;
}
///////////////////////////////////////////////////////////////////////////////|
#endif // MS_CLANG_REWRITE

