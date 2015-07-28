/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
module clang.Token;

import std.conv;
import std.string;
import std.typecons;
import std.experimental.logger;

import clang.c.index;
import clang.c.cxstring;
import clang.Cursor;
import clang.SourceLocation;
import clang.SourceRange;
import clang.TranslationUnit;
import clang.Util;
import clang.Visitor;

@property auto toString(Token tok) {
    import std.conv;

    if (tok.isValid) {
        return format("%s [%s %s]", tok.spelling, tok.kind, text(tok.cx),);
    }

    return text(tok);
}

@property auto toString(ref TokenGroup toks) {
    string s;

    foreach (t; toks) {
        if (t.isValid) {
            s ~= t.spelling ~ " ";
        }
    }

    return s.strip;
}

/** Represents a single token from the preprocessor.
 *
 *  Tokens are effectively segments of source code. Source code is first parsed
 *  into tokens before being converted into the AST and Cursors.
 *
 *  Tokens are obtained from parsed TranslationUnit instances. You currently
 *  can't create tokens manually.
 */
struct Token {
    private alias CType = CXToken;
    CType cx;
    alias cx this;

    private RefCounted!TokenGroup group;

    this(RefCounted!TokenGroup group, ref CXToken token) {
        this.group = group;
        this.cx = token;
    }

    /// Obtain the TokenKind of the current token.
    @property CXTokenKind kind() {
        return clang_getTokenKind(cx);
    }

    /** The spelling of this token.
     *
     *  This is the textual representation of the token in source.
     */
    @property string spelling() {
        auto r = clang_getTokenSpelling(group.tu, cx);
        return toD(r);
    }

    /// The SourceLocation this Token occurs at.
    @property SourceLocation location() {
        auto r = clang_getTokenLocation(group.tu, cx);
        return SourceLocation(r);
    }

    /// The SourceRange this Token occupies.
    @property SourceRange extent() {
        auto r = clang_getTokenExtent(group.tu, cx);
        return SourceRange(r);
    }

    /// The Cursor this Token corresponds to.
    @property Cursor cursor() {
        Cursor c = Cursor.empty(group.tu);

        clang_annotateTokens(group.tu, &cx, 1, &c.cx);

        return c;
    }

    @property bool isValid() {
        return cx !is CType.init;
    }
}

/** Tokenize the source code described by the given range into raw
 * lexical tokens.
 *
 *  TU = the translation unit whose text is being tokenized.
 *
 *  Range = the source range in which text should be tokenized. All of the
 * tokens produced by tokenization will fall within this source range,
 *
 *  Tokens = this pointer will be set to point to the array of tokens
 * that occur within the given source range. The returned pointer must be
 * freed with clang_disposeTokens() before the translation unit is destroyed.
 *
 *  NumTokens = will be set to the number of tokens in the \c* Tokens
 * array.
 */
RefCounted!TokenGroup tokenize(TranslationUnit tu, SourceRange range) {
    TokenGroup.CXTokenArray tokens;
    auto tg = RefCounted!TokenGroup(tu);

    trace("TU tokenize: ", tu, "|", tg.tu);

    clang_tokenize(tu, range, &tokens.tokens, &tokens.length);
    tg.cxtokens = tokens;

    foreach (i; 0 .. tokens.length) {
        auto t = Token(tg, tokens.tokens[i]);
        tg.tokens ~= t;
    }

    return tg;
}

private:

/** Helper class to facilitate token management.
 * Tokens are allocated from libclang in chunks. They must be disposed of as a
 * collective group.
 *
 * One purpose of this class is for instances to represent groups of allocated
 * tokens. Each token in a group contains a reference back to an instance of
 * this class. When all tokens from a group are garbage collected, it allows
 * this class to be garbage collected. When this class is garbage collected,
 * it calls the libclang destructor which invalidates all tokens in the group.
 *
 * You should not instantiate this class outside of this module.
 */
struct TokenGroup {
    alias Delegate = int delegate(ref Token);

    private TranslationUnit tu;
    private CXTokenArray cxtokens;
    private Token[] tokens;

    struct CXTokenArray {
        CXToken* tokens;
        uint length;
    }

    this(TranslationUnit tu) {
        this.tu = tu;
    }

    ~this() {
        if (cxtokens.length > 0) {
            clang_disposeTokens(tu.cx, cxtokens.tokens, cxtokens.length);
            cxtokens.length = 0;
            tokens.length = 0;
        }
    }

    auto opIndex(T)(T idx) {
        return tokens[idx];
    }

    auto opIndex(T...)(T ks) {
        Token[] rval;

        foreach (k; ks) {
            rval ~= tokens[k];
        }

        return rval;
    }

    auto opDollar(int dim)() {
        return length;
    }

    @property auto length() {
        return tokens.length;
    }

    auto opApply(Delegate dg) {
        foreach (tok; tokens) {
            if (auto result = dg(tok))
                return result;
        }

        return 0;
    }
}
