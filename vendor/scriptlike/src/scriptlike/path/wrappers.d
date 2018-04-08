/++
$(H2 Scriptlike $(SCRIPTLIKE_VERSION))

Wrappers for $(MODULE_STD_PATH) that add support for Scriptlike's
$(API_PATH_EXTR Path) and command echoing features.

Copyright: Copyright (C) 2014-2017 Nick Sabalausky
License:   zlib/libpng
Authors:   Nick Sabalausky
+/
module scriptlike.path.wrappers;

import std.algorithm;
import std.conv;
import std.datetime;
import std.file;
import std.process;
import std.range;
import std.stdio;
import std.string;
import std.traits;
import std.typecons;
import std.typetuple;

static import std.path;
import std.path : dirSeparator, pathSeparator, isDirSeparator,
	CaseSensitive, buildPath, buildNormalizedPath;

import scriptlike.path.extras;

/// Alias of same-named function from $(MODULE_STD_PATH)
alias baseName()         = std.path.baseName;
alias dirName()          = std.path.dirName;          ///ditto
alias rootName()         = std.path.rootName;         ///ditto
alias driveName()        = std.path.driveName;        ///ditto
alias stripDrive()       = std.path.stripDrive;       ///ditto
alias extension()        = std.path.extension;        ///ditto
alias stripExtension()   = std.path.stripExtension;   ///ditto
alias setExtension()     = std.path.setExtension;     ///ditto
alias defaultExtension() = std.path.defaultExtension; ///ditto
alias pathSplitter()     = std.path.pathSplitter;     ///ditto
alias isRooted()         = std.path.isRooted;         ///ditto
alias isAbsolute()       = std.path.isAbsolute;       ///ditto
alias absolutePath       = std.path.absolutePath;     ///ditto
alias relativePath()     = std.path.relativePath;     ///ditto
alias filenameCmp()      = std.path.filenameCmp;      ///ditto
alias globMatch()        = std.path.globMatch;        ///ditto
alias isValidFilename()  = std.path.isValidFilename;  ///ditto
alias isValidPath()      = std.path.isValidPath;      ///ditto
alias expandTilde        = std.path.expandTilde;      ///ditto

/// Like $(FULL_STD_PATH baseName), but operates on Path.
Path baseName(Path path)
	@trusted pure
{
	return Path( std.path.baseName(path.raw) );
}

///ditto
Path baseName(CaseSensitive cs = CaseSensitive.osDefault)
	(Path path, in string suffix)
	@safe pure
{
	return Path( std.path.baseName!cs(path.raw, suffix) );
}
/// Like $(FULL_STD_PATH dirName), but operates on Path.
Path dirName(Path path)
{
	return Path( std.path.dirName(path.raw) );
}

/// Like $(FULL_STD_PATH rootName), but operates on Path.
Path rootName(Path path) @safe pure nothrow
{
	return Path( std.path.rootName(path.raw) );
}

/// Like $(FULL_STD_PATH driveName), but operates on Path.
Path driveName(Path path) @safe pure nothrow
{
	return Path( std.path.driveName(path.raw) );
}

/// Like $(FULL_STD_PATH stripDrive), but operates on Path.
Path stripDrive(Path path) @safe pure nothrow
{
	return Path( std.path.stripDrive(path.raw) );
}

/// Like $(FULL_STD_PATH extension), but takes a Path and returns an Ext.
Ext extension(in Path path) @safe pure nothrow
{
	return Ext( std.path.extension(path.raw) );
}

/// Like $(FULL_STD_PATH stripExtension), but operates on Path.
Path stripExtension(Path path) @safe pure nothrow
{
	return Path( std.path.stripExtension(path.raw) );
}

/// Like $(FULL_STD_PATH setExtension), but operates on Path.
Path setExtension(Path path, string ext)
	@trusted pure nothrow
{
	return Path( std.path.setExtension(path.raw, ext) );
}

///ditto
Path setExtension(Path path, Ext ext)
	@trusted pure nothrow
{
	return path.setExtension(ext.toString());
}

/// Like $(FULL_STD_PATH defaultExtension), but operates on Path and optionally Ext.
Path defaultExtension(Path path, in string ext)
	@trusted pure
{
	return Path( std.path.defaultExtension(path.raw, ext) );
}

///ditto
Path defaultExtension(Path path, Ext ext)
	@trusted pure
{
	return path.defaultExtension(ext.toString());
}

/// Like $(FULL_STD_PATH pathSplitter). Note this returns a range of strings,
/// not a range of Path.
auto pathSplitter(Path path) @safe pure nothrow
{
	return std.path.pathSplitter(path.raw);
}

/// Like $(FULL_STD_PATH isRooted), but operates on Path.
bool isRooted()(in Path path) @safe pure nothrow
{
	return std.path.isRooted(path.raw);
}

/// Like $(FULL_STD_PATH isAbsolute), but operates on Path.
bool isAbsolute(in Path path) @safe pure nothrow
{
	return std.path.isAbsolute(path.raw);
}

/// Like $(FULL_STD_PATH absolutePath), but operates on Path.
Path absolutePath(Path path, lazy string base = getcwd())
	@safe pure
{
	return Path( std.path.absolutePath(path.raw, base) );
}

///ditto
Path absolutePath(Path path, Path base)
	@safe pure
{
	return Path( std.path.absolutePath(path.raw, base.raw.to!string()) );
}

/// Like $(FULL_STD_PATH relativePath), but operates on Path.
Path relativePath(CaseSensitive cs = CaseSensitive.osDefault)
	(Path path, lazy string base = getcwd())
{
	return Path( std.path.relativePath!cs(path.raw, base) );
}

///ditto
Path relativePath(CaseSensitive cs = CaseSensitive.osDefault)
	(Path path, Path base)
{
	return Path( std.path.relativePath!cs(path.raw, base.raw.to!string()) );
}

/// Like $(FULL_STD_PATH filenameCmp), but operates on Path.
int filenameCmp(CaseSensitive cs = CaseSensitive.osDefault)
	(Path path, Path filename2)
	@safe pure
{
	return std.path.filenameCmp(path.raw, filename2.raw);
}

///ditto
int filenameCmp(CaseSensitive cs = CaseSensitive.osDefault)
	(Path path, string filename2)
	@safe pure
{
	return std.path.filenameCmp(path.raw, filename2);
}

///ditto
int filenameCmp(CaseSensitive cs = CaseSensitive.osDefault)
	(string path, Path filename2)
	@safe pure
{
	return std.path.filenameCmp(path, filename2.raw);
}

/// Like $(FULL_STD_PATH globMatch), but operates on Path.
bool globMatch(CaseSensitive cs = CaseSensitive.osDefault)
	(Path path, string pattern)
	@safe pure nothrow
{
	return std.path.globMatch!cs(path.raw, pattern);
}

/// Like $(FULL_STD_PATH isValidFilename), but operates on Path.
bool isValidFilename(in Path path) @safe pure nothrow
{
	return std.path.isValidFilename(path.raw);
}

/// Like $(FULL_STD_PATH isValidPath), but operates on Path.
bool isValidPath(in Path path) @safe pure nothrow
{
	return std.path.isValidPath(path.raw);
}

/// Like $(FULL_STD_PATH expandTilde), but operates on Path.
Path expandTilde(Path path)
{
	return Path( std.path.expandTilde(path.raw) );
}
