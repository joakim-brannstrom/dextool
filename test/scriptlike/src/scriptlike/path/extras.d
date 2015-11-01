/++
$(H2 Scriptlike $(SCRIPTLIKE_VERSION))

Extra Scriptlike-only functionality to complement $(MODULE_STD_PATH).

Copyright: Copyright (C) 2014-2015 Nick Sabalausky
License:   zlib/libpng
Authors:   Nick Sabalausky
+/
module scriptlike.path.extras;

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
	CaseSensitive, osDefaultCaseSensitivity, buildPath, buildNormalizedPath;

import scriptlike.path.wrappers;

/// Represents a file extension.
struct Ext
{
	private string str;
	
	/// Main constructor.
	this(string extension = null) pure @safe nothrow
	{
		this.str = extension;
	}
	
	/// Convert to string.
	string toString() pure @safe nothrow
	{
		return str;
	}
	
	/// No longer needed. Use Ext.toString() instead.
	string toRawString() pure @safe nothrow
	{
		return str;
	}
	
	/// Compare using OS-specific case-sensitivity rules. If you want to force
	/// case-sensitive or case-insensitive, then call filenameCmp instead.
	int opCmp(ref const Ext other) const
	{
		return std.path.filenameCmp(this.str, other.str);
	}

	///ditto
	int opCmp(Ext other) const
	{
		return std.path.filenameCmp(this.str, other.str);
	}

	///ditto
	int opCmp(string other) const
	{
		return std.path.filenameCmp(this.str, other);
	}

	/// Compare using OS-specific case-sensitivity rules. If you want to force
	/// case-sensitive or case-insensitive, then call filenameCmp instead.
	int opEquals(ref const Ext other) const
	{
		return opCmp(other) == 0;
	}

	///ditto
	int opEquals(Ext other) const
	{
		return opCmp(other) == 0;
	}

	///ditto
	int opEquals(string other) const
	{
		return opCmp(other) == 0;
	}

	/// Convert to bool
	T opCast(T)() if(is(T==bool))
	{
		return !!str;
	}
}

/// Represents a filesystem path. The path is always kept normalized
/// automatically (as performed by buildNormalizedPathFixed).
struct Path
{
	private string str = ".";
	
	/// Main constructor.
	this(string path = ".") pure @safe nothrow
	{
		this.str = buildNormalizedPathFixed(path);
	}
	
	pure @trusted nothrow invariant()
	{
		assert(str == buildNormalizedPathFixed(str));
	}
	
	/// Convert to string, quoting or escaping spaces if necessary.
	string toString()
	{
		return .escapeShellArg(str);
	}
	
	/// Returns the underlying string. Does NOT do any escaping, even if path contains spaces.
	string toRawString() const pure @safe nothrow
	{
		return str;
	}

	/// Concatenates two paths, with a directory separator in between.
	Path opBinary(string op)(Path rhs) if(op=="~")
	{
		Path newPath;
		newPath.str = buildNormalizedPathFixed(this.str, rhs.str);
		return newPath;
	}
	
	///ditto
	Path opBinary(string op)(string rhs) if(op=="~")
	{
		Path newPath;
		newPath.str = buildNormalizedPathFixed(this.str, rhs);
		return newPath;
	}
	
	///ditto
	Path opBinaryRight(string op)(string lhs) if(op=="~")
	{
		Path newPath;
		newPath.str = buildNormalizedPathFixed(lhs, this.str);
		return newPath;
	}
	
	/// Appends an extension to a path. Naturally, a directory separator
	/// is NOT inserted in between.
	Path opBinary(string op)(Ext rhs) if(op=="~")
	{
		Path newPath;
		newPath.str = std.path.setExtension(this.str, rhs.str);
		return newPath;
	}
	
	/// Appends a path to this one, with a directory separator in between.
	Path opOpAssign(string op)(Path rhs) if(op=="~")
	{
		str = buildNormalizedPathFixed(str, rhs.str);
		return this;
	}
	
	///ditto
	Path opOpAssign(string op)(string rhs) if(op=="~")
	{
		str = buildNormalizedPathFixed(str, rhs);
		return this;
	}
	
	/// Appends an extension to this path. Naturally, a directory separator
	/// is NOT inserted in between.
	Path opOpAssign(string op)(Ext rhs) if(op=="~")
	{
		str = std.path.setExtension(str, rhs.str);
		return this;
	}
	
	/// Compare using OS-specific case-sensitivity rules. If you want to force
	/// case-sensitive or case-insensitive, then call filenameCmp instead.
	int opCmp(ref const Path other) const
	{
		return std.path.filenameCmp(this.str, other.str);
	}

	///ditto
	int opCmp(Path other) const
	{
		return std.path.filenameCmp(this.str, other.str);
	}

	///ditto
	int opCmp(string other) const
	{
		return std.path.filenameCmp(this.str, other);
	}

	/// Compare using OS-specific case-sensitivity rules. If you want to force
	/// case-sensitive or case-insensitive, then call filenameCmp instead.
	int opEquals(ref const Path other) const
	{
		return opCmp(other) == 0;
	}

	///ditto
	int opEquals(Path other) const
	{
		return opCmp(other) == 0;
	}

	///ditto
	int opEquals(string other) const
	{
		return opCmp(other) == 0;
	}
	
	/// Convert to bool
	T opCast(T)() if(is(T==bool))
	{
		return !!str;
	}
	
	/// Returns the parent path, according to $(FULL_STD_PATH dirName).
	@property Path up()
	{
		return this.dirName();
	}
	
	/// Is this path equal to empty string?
	@property bool empty()
	{
		return str == "";
	}
}

/// Convenience alias
alias extOf      = extension;
alias stripExt   = stripExtension;   ///ditto
alias setExt     = setExtension;     ///ditto
alias defaultExt = defaultExtension; ///ditto

/// Like buildNormalizedPath, but if the result is the current directory,
/// this returns "." instead of "". However, if all the inputs are "", or there
/// are no inputs, this still returns "" just like buildNormalizedPath.
///
/// Also, unlike buildNormalizedPath, this converts back/forward slashes to
/// native on BOTH Windows and Posix, not just on Windows.
string buildNormalizedPathFixed(string[] paths...)
	@trusted pure nothrow
{
	if(all!`a is null`(paths))
		return null;
	
	if(all!`a==""`(paths))
		return "";
	
	auto result = std.path.buildNormalizedPath(paths);

	version(Posix)        result = result.replace(`\`, `/`);
	else version(Windows) { /+ do nothing +/ }
	else                  static assert(0);

	return result==""? "." : result;
}

/// Properly escape arguments containing spaces for the command shell, if necessary.
///
/// Although Path doesn't stricktly need this (since Path.toString automatically
/// calls this anyway), an overload of escapeShellArg which accepts a Path is
/// provided for the sake of generic code.
const(string) escapeShellArg(in string str)
{
	if(str.canFind(' '))
	{
		version(Windows)
			return escapeWindowsArgument(str);
		else version(Posix)
			return escapeShellFileName(str);
		else
			static assert(0, "This platform not supported.");
	}
	else
		return str;
}

///ditto
string escapeShellArg(Path path)
{
	return path.toString();
}

