/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
module clang.Token;

import std.conv;
import std.string;
import std.typecons;

import deimos.clang.index;

import clang.Cursor;
import clang.SourceLocation;
import clang.SourceRange;
import clang.TranslationUnit;
import clang.Util;
import clang.Visitor;

@property auto toString(Token tok) {
    import std.conv;

    return format("%s [%s %s]", tok.spelling, tok.kind, text(tok.cursor.cx),);
}

@property auto toString(ref TokenRange toks) {
    string s;

    foreach (t; toks) {
        s ~= t.spelling ~ " ";
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
    private struct Container {
        CXTranslationUnit translationUnit;
        CXToken* tokens;
        ulong numTokens;

        ~this() {
            if (tokens != null) {
                clang_disposeTokens(translationUnit, tokens, to!uint(numTokens));
            }
        }
    }

    private const RefCounted!Container container;
    size_t index;

    @property private Container* containerPtr() return const {
        return cast(Container*)&(container.refCountedPayload());
    }

    @property static Cursor empty() {
        //TODO why is this function needed, remove?
        auto r = clang_getNullCursor();
        return Cursor(r);
    }

    /// Obtain the TokenKind of the current token.
    @property CXTokenKind kind() const {
        return clang_getTokenKind(containerPtr.tokens[index]);
    }

    /** The spelling of this token.
     *
     *  This is the textual representation of the token in source.
     */
    @property string spelling() const {
        auto r = clang_getTokenSpelling(containerPtr.translationUnit, containerPtr.tokens[index]);
        return toD(r);
    }

    /// The SourceLocation this Token occurs at.
    @property SourceLocation location() const {
        auto r = clang_getTokenLocation(containerPtr.translationUnit, containerPtr.tokens[index]);
        return SourceLocation(r);
    }

    /// The SourceRange this Token occupies.
    @property SourceRange extent() const {
        auto r = clang_getTokenExtent(containerPtr.translationUnit, containerPtr.tokens[index]);
        return SourceRange(r);
    }

    /// The Cursor this Token corresponds to.
    @property Cursor cursor() {
        Cursor c = empty;
        clang_annotateTokens(containerPtr.translationUnit, &containerPtr.tokens[index], 1, &c.cx);

        return c;
    }
}

struct TokenRange {
    private const RefCounted!(Token.Container) container;
    private size_t begin;
    private size_t end;

    private static RefCounted!(Token.Container) makeContainer(
            CXTranslationUnit translationUnit, CXToken* tokens, ulong numTokens) {
        RefCounted!(Token.Container) result;
        result.translationUnit = translationUnit;
        result.tokens = tokens;
        result.numTokens = numTokens;
        return result;
    }

    this(CXTranslationUnit translationUnit, CXToken* tokens, ulong numTokens) {
        container = makeContainer(translationUnit, tokens, numTokens);
        begin = 0;
        end = numTokens;
    }

    @property bool empty() const {
        return begin >= end;
    }

    @property Token front() const {
        return Token(container, begin);
    }

    @property Token back() const {
        return Token(container, end - 1);
    }

    @property void popFront() {
        ++begin;
    }

    @property void popBack() {
        --end;
    }

    @property TokenRange save() const {
        return this;
    }

    @property size_t length() const {
        return end - begin;
    }

    Token opIndex(size_t index) const {
        return Token(container, begin + index);
    }
}
