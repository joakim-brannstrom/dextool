// Written in the D programming language.

/**
 * 
 * Tom's Obvious, Minimal Language (v0.4.0).
 *
 * License: $(HTTP https://github.com/Kripth/toml/blob/master/LICENSE, MIT)
 * Authors: Kripth
 * References: $(LINK https://github.com/toml-lang/toml/blob/master/README.md)
 * Source: $(HTTP https://github.com/Kripth/toml/blob/master/src/toml/toml.d, toml/_toml.d)
 * 
 */
module toml.toml;

import std.algorithm : canFind, min, stripRight;
import std.array : Appender;
import std.ascii : newline;
import std.conv : to;
import std.datetime : SysTime, DateTimeD = DateTime, Date,
	TimeOfDayD = TimeOfDay;
import std.exception : enforce, assertThrown;
import std.math : isNaN, isFinite;
import std.string : join, strip, replace, indexOf;
import std.traits : isNumeric, isIntegral, isFloatingPoint, isArray,
	isAssociativeArray, KeyType;
import std.typecons : Tuple;
import std.utf : encode, UseReplacementDchar;

import toml.datetime : DateTime, TimeOfDay;

/**
 * Flags that control how a TOML document is parsed and encoded.
 */
enum TOMLOptions
{

	none = 0x00,
	unquotedStrings = 0x01, /// allow unquoted strings as values when parsing

}

/**
 * TOML type enumeration.
 */
enum TOML_TYPE : byte
{

	STRING, /// Indicates the type of a TOMLValue.
	INTEGER, /// ditto
	FLOAT, /// ditto
	OFFSET_DATETIME, /// ditto
	LOCAL_DATETIME, /// ditto
	LOCAL_DATE, /// ditto
	LOCAL_TIME, /// ditto
	ARRAY, /// ditto
	TABLE, /// ditto
	TRUE, /// ditto
	FALSE /// ditto

}

/**
 * Main table of a TOML document.
 * It works as a TOMLValue with the TOML_TYPE.TABLE type.
 */
struct TOMLDocument
{

	public TOMLValue[string] table;

	public this(TOMLValue[string] table)
	{
		this.table = table;
	}

	public this(TOMLValue value)
	{
		this(value.table);
	}

	public string toString()
	{
		Appender!string appender;
		foreach (key, value; this.table)
		{
			appender.put(formatKey(key));
			appender.put(" = ");
			value.append(appender);
			appender.put(newline);
		}
		return appender.data;
	}

	alias table this;

}

/**
 * Value of a TOML value.
 */
struct TOMLValue
{

	private union Store
	{
		string str;
		long integer;
		double floating;
		SysTime offsetDatetime;
		DateTime localDatetime;
		Date localDate;
		TimeOfDay localTime;
		TOMLValue[] array;
		TOMLValue[string] table;
	}

	private Store store;
	private TOML_TYPE _type;

	public this(T)(T value)
	{
		static if (is(T == TOML_TYPE))
		{
			this._type = value;
		}
		else
		{
			this.assign(value);
		}
	}

	public inout pure nothrow @property @safe @nogc TOML_TYPE type()
	{
		return this._type;
	}

	/**
	 * Throws: TOMLException if type is not TOML_TYPE.STRING
	 */
	public inout @property @trusted string str()
	{
		enforce!TOMLException(this._type == TOML_TYPE.STRING, "TOMLValue is not a string");
		return this.store.str;
	}

	/**
	 * Throws: TOMLException if type is not TOML_TYPE.INTEGER
	 */
	public inout @property @trusted long integer()
	{
		enforce!TOMLException(this._type == TOML_TYPE.INTEGER, "TOMLValue is not an integer");
		return this.store.integer;
	}

	/**
	 * Throws: TOMLException if type is not TOML_TYPE.FLOAT
	 */
	public inout @property @trusted double floating()
	{
		enforce!TOMLException(this._type == TOML_TYPE.FLOAT, "TOMLValue is not a float");
		return this.store.floating;
	}

	/**
	 * Throws: TOMLException if type is not TOML_TYPE.OFFSET_DATETIME
	 */
	public @property ref SysTime offsetDatetime()
	{
		enforce!TOMLException(this.type == TOML_TYPE.OFFSET_DATETIME,
				"TOMLValue is not an offset datetime");
		return this.store.offsetDatetime;
	}

	/**
	 * Throws: TOMLException if type is not TOML_TYPE.LOCAL_DATETIME
	 */
	public @property @trusted ref DateTime localDatetime()
	{
		enforce!TOMLException(this._type == TOML_TYPE.LOCAL_DATETIME,
				"TOMLValue is not a local datetime");
		return this.store.localDatetime;
	}

	/**
	 * Throws: TOMLException if type is not TOML_TYPE.LOCAL_DATE
	 */
	public @property @trusted ref Date localDate()
	{
		enforce!TOMLException(this._type == TOML_TYPE.LOCAL_DATE, "TOMLValue is not a local date");
		return this.store.localDate;
	}

	/**
	 * Throws: TOMLException if type is not TOML_TYPE.LOCAL_TIME
	 */
	public @property @trusted ref TimeOfDay localTime()
	{
		enforce!TOMLException(this._type == TOML_TYPE.LOCAL_TIME, "TOMLValue is not a local time");
		return this.store.localTime;
	}

	/**
	 * Throws: TOMLException if type is not TOML_TYPE.ARRAY
	 */
	public @property @trusted ref TOMLValue[] array()
	{
		enforce!TOMLException(this._type == TOML_TYPE.ARRAY, "TOMLValue is not an array");
		return this.store.array;
	}

	/**
	 * Throws: TOMLException if type is not TOML_TYPE.TABLE
	 */
	public @property @trusted ref TOMLValue[string] table()
	{
		enforce!TOMLException(this._type == TOML_TYPE.TABLE, "TOMLValue is not a table");
		return this.store.table;
	}

	public TOMLValue opIndex(size_t index)
	{
		return this.array[index];
	}

	public TOMLValue* opBinaryRight(string op : "in")(string key)
	{
		return key in this.table;
	}

	public TOMLValue opIndex(string key)
	{
		return this.table[key];
	}

	public int opApply(scope int delegate(string, ref TOMLValue) dg)
	{
		enforce!TOMLException(this._type == TOML_TYPE.TABLE, "TOMLValue is not a table");
		int result;
		foreach (string key, ref value; this.store.table)
		{
			result = dg(key, value);
			if (result)
				break;
		}
		return result;
	}

	public void opAssign(T)(T value)
	{
		this.assign(value);
	}

	private void assign(T)(T value)
	{
		static if (is(T == TOMLValue))
		{
			this.store = value.store;
			this._type = value._type;
		}
		else static if (is(T : string))
		{
			this.store.str = value;
			this._type = TOML_TYPE.STRING;
		}
		else static if (isIntegral!T)
		{
			this.store.integer = value;
			this._type = TOML_TYPE.INTEGER;
		}
		else static if (isFloatingPoint!T)
		{
			this.store.floating = value.to!double;
			this._type = TOML_TYPE.FLOAT;
		}
		else static if (is(T == SysTime))
		{
			this.store.offsetDatetime = value;
			this._type = TOML_TYPE.OFFSET_DATETIME;
		}
		else static if (is(T == DateTime))
		{
			this.store.localDatetime = value;
			this._type = TOML_TYPE.LOCAL_DATETIME;
		}
		else static if (is(T == DateTimeD))
		{
			this.store.localDatetime = DateTime(value.date, TimeOfDay(value.timeOfDay));
			this._type = TOML_TYPE.LOCAL_DATETIME;
		}
		else static if (is(T == Date))
		{
			this.store.localDate = value;
			this._type = TOML_TYPE.LOCAL_DATE;
		}
		else static if (is(T == TimeOfDay))
		{
			this.store.localTime = value;
			this._type = TOML_TYPE.LOCAL_TIME;
		}
		else static if (is(T == TimeOfDayD))
		{
			this.store.localTime = TimeOfDay(value);
			this._type = TOML_TYPE.LOCAL_TIME;
		}
		else static if (isArray!T)
		{
			static if (is(T == TOMLValue[]))
			{
				if (value.length)
				{
					// verify that every element has the same type
					TOML_TYPE cmp = value[0].type;
					foreach (element; value[1 .. $])
					{
						enforce!TOMLException(element.type == cmp,
								"Array's values must be of the same type");
					}
				}
				alias data = value;
			}
			else
			{
				TOMLValue[] data;
				foreach (element; value)
				{
					data ~= TOMLValue(element);
				}
			}
			this.store.array = data;
			this._type = TOML_TYPE.ARRAY;
		}
		else static if (isAssociativeArray!T && is(KeyType!T : string))
		{
			static if (is(T == TOMLValue[string]))
			{
				alias data = value;
			}
			else
			{
				TOMLValue[string] data;
				foreach (key, v; value)
				{
					data[key] = v;
				}
			}
			this.store.table = data;
			this._type = TOML_TYPE.TABLE;
		}
		else static if (is(T == bool))
		{
			_type = value ? TOML_TYPE.TRUE : TOML_TYPE.FALSE;
		}
		else
		{
			static assert(0);
		}
	}

	public bool opEquals(T)(T value)
	{
		static if (is(T == TOMLValue))
		{
			if (this._type != value._type)
				return false;
			final switch (this.type) with (TOML_TYPE)
			{
			case STRING:
				return this.store.str == value.store.str;
			case INTEGER:
				return this.store.integer == value.store.integer;
			case FLOAT:
				return this.store.floating == value.store.floating;
			case OFFSET_DATETIME:
				return this.store.offsetDatetime == value.store.offsetDatetime;
			case LOCAL_DATETIME:
				return this.store.localDatetime == value.store.localDatetime;
			case LOCAL_DATE:
				return this.store.localDate == value.store.localDate;
			case LOCAL_TIME:
				return this.store.localTime == value.store.localTime;
			case ARRAY:
				return this.store.array == value.store.array;
				//case TABLE: return this.store.table == value.store.table; // causes errors
			case TABLE:
				return this.opEquals(value.store.table);
			case TRUE:
			case FALSE:
				return true;
			}
		}
		else static if (is(T : string))
		{
			return this._type == TOML_TYPE.STRING && this.store.str == value;
		}
		else static if (isNumeric!T)
		{
			if (this._type == TOML_TYPE.INTEGER)
				return this.store.integer == value;
			else if (this._type == TOML_TYPE.FLOAT)
				return this.store.floating == value;
			else
				return false;
		}
		else static if (is(T == SysTime))
		{
			return this._type == TOML_TYPE.OFFSET_DATETIME && this.store.offsetDatetime == value;
		}
		else static if (is(T == DateTime))
		{
			return this._type == TOML_TYPE.LOCAL_DATETIME && this.store.localDatetime.dateTime == value.dateTime
				&& this.store.localDatetime.timeOfDay.fracSecs == value.timeOfDay.fracSecs;
		}
		else static if (is(T == DateTimeD))
		{
			return this._type == TOML_TYPE.LOCAL_DATETIME
				&& this.store.localDatetime.dateTime == value;
		}
		else static if (is(T == Date))
		{
			return this._type == TOML_TYPE.LOCAL_DATE && this.store.localDate == value;
		}
		else static if (is(T == TimeOfDay))
		{
			return this._type == TOML_TYPE.LOCAL_TIME && this.store.localTime.timeOfDay == value.timeOfDay
				&& this.store.localTime.fracSecs == value.fracSecs;
		}
		else static if (is(T == TimeOfDayD))
		{
			return this._type == TOML_TYPE.LOCAL_TIME && this.store.localTime == value;
		}
		else static if (isArray!T)
		{
			if (this._type != TOML_TYPE.ARRAY || this.store.array.length != value.length)
				return false;
			foreach (i, element; this.store.array)
			{
				if (element != value[i])
					return false;
			}
			return true;
		}
		else static if (isAssociativeArray!T && is(KeyType!T : string))
		{
			if (this._type != TOML_TYPE.TABLE || this.store.table.length != value.length)
				return false;
			foreach (key, v; this.store.table)
			{
				auto cmp = key in value;
				if (cmp is null || v != *cmp)
					return false;
			}
			return true;
		}
		else static if (is(T == bool))
		{
			return value ? _type == TOML_TYPE.TRUE : _type == TOML_TYPE.FALSE;
		}
		else
		{
			return false;
		}
	}

	public inout void append(ref Appender!string appender)
	{
		final switch (this._type) with (TOML_TYPE)
		{
		case STRING:
			appender.put(formatString(this.store.str));
			break;
		case INTEGER:
			appender.put(this.store.integer.to!string);
			break;
		case FLOAT:
			immutable str = this.store.floating.to!string;
			appender.put(str);
			if (!str.canFind('.') && !str.canFind('e'))
				appender.put(".0");
			break;
		case OFFSET_DATETIME:
			appender.put(this.store.offsetDatetime.toISOExtString());
			break;
		case LOCAL_DATETIME:
			appender.put(this.store.localDatetime.toISOExtString());
			break;
		case LOCAL_DATE:
			appender.put(this.store.localDate.toISOExtString());
			break;
		case LOCAL_TIME:
			appender.put(this.store.localTime.toISOExtString());
			break;
		case ARRAY:
			appender.put("[");
			foreach (i, value; this.store.array)
			{
				value.append(appender);
				if (i + 1 < this.store.array.length)
					appender.put(", ");
			}
			appender.put("]");
			break;
		case TABLE:
			// display as an inline table
			appender.put("{ ");
			size_t i = 0;
			foreach (key, value; this.store.table)
			{
				appender.put(formatKey(key));
				appender.put(" = ");
				value.append(appender);
				if (++i != this.store.table.length)
					appender.put(", ");
			}
			appender.put(" }");
			break;
		case TRUE:
			appender.put("true");
			break;
		case FALSE:
			appender.put("false");
			break;
		}
	}

	public inout string toString()
	{
		Appender!string appender;
		this.append(appender);
		return appender.data;
	}

}

private string formatKey(string str)
{
	foreach (c; str)
	{
		if ((c < '0' || c > '9') && (c < 'A' || c > 'Z') && (c < 'a' || c > 'z')
				&& c != '-' && c != '_')
			return formatString(str);
	}
	return str;
}

private string formatString(string str)
{
	Appender!string appender;
	foreach (c; str)
	{
		switch (c)
		{
		case '"':
			appender.put("\\\"");
			break;
		case '\\':
			appender.put("\\\\");
			break;
		case '\b':
			appender.put("\\b");
			break;
		case '\f':
			appender.put("\\f");
			break;
		case '\n':
			appender.put("\\n");
			break;
		case '\r':
			appender.put("\\r");
			break;
		case '\t':
			appender.put("\\t");
			break;
		default:
			appender.put(c);
		}
	}
	return "\"" ~ appender.data ~ "\"";
}

/**
 * Parses a TOML document.
 * Returns: a TOMLDocument with the parsed data
 * Throws:
 * 		TOMLParserException when the document's syntax is incorrect
 */
TOMLDocument parseTOML(string data, TOMLOptions options = TOMLOptions.none)
{

	size_t index = 0;

	/**
	 * Throws a TOMLParserException at the current line and column.
	 */
	void error(string message)
	{
		if (index >= data.length)
			index = data.length;
		size_t i, line, column;
		while (i < index)
		{
			if (data[i++] == '\n')
			{
				line++;
				column = 0;
			}
			else
			{
				column++;
			}
		}
		throw new TOMLParserException(message, line + 1, column);
	}

	/**
	 * Throws a TOMLParserException throught the error function if
	 * cond is false.
	 */
	void enforceParser(bool cond, lazy string message)
	{
		if (!cond)
		{
			error(message);
		}
	}

	TOMLValue[string] _ret;
	auto current = &_ret;

	string[][] tableNames;

	void setImpl(TOMLValue[string]* table, string[] keys, string[] original, TOMLValue value)
	{
		auto ptr = keys[0] in *table;
		if (keys.length == 1)
		{
			// should not be there
			enforceParser(ptr is null, "Key is already defined");
			(*table)[keys[0]] = value;
		}
		else
		{
			// must be a table
			if (ptr !is null)
				enforceParser((*ptr).type == TOML_TYPE.TABLE, join(original[0 .. $ - keys.length],
						".") ~ " is already defined and is not a table");
			else
				(*table)[keys[0]] = (TOMLValue[string]).init;
			setImpl(&((*table)[keys[0]].table()), keys[1 .. $], original, value);
		}
	}

	void set(string[] keys, TOMLValue value)
	{
		setImpl(current, keys, keys, value);
	}

	/**
	 * Removes whitespace characters and comments.
	 * Return: whether there's still data to read
	 */
	bool clear(bool clear_newline = true)()
	{
		static if (clear_newline)
		{
			enum chars = " \t\r\n";
		}
		else
		{
			enum chars = " \t\r";
		}
		if (index < data.length)
		{
			if (chars.canFind(data[index]))
			{
				index++;
				return clear!clear_newline();
			}
			else if (data[index] == '#')
			{
				// skip until end of line
				while (++index < data.length && data[index] != '\n')
				{
				}
				static if (clear_newline)
				{
					index++; // point at the next character
					return clear();
				}
				else
				{
					return true;
				}
			}
			else
			{
				return true;
			}
		}
		else
		{
			return false;
		}
	}

	/**
	 * Indicates whether the given character is valid in an unquoted key.
	 */
	bool isValidKeyChar(immutable char c)
	{
		return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0'
			&& c <= '9' || c == '-' || c == '_';
	}

	string readQuotedString(bool multiline)()
	{
		Appender!string ret;
		bool backslash = false;
		while (index < data.length)
		{
			static if (!multiline)
			{
				enforceParser(data[index] != '\n', "Unterminated quoted string");
			}
			if (backslash)
			{
				void readUnicode(size_t size)()
				{
					enforceParser(index + size < data.length, "Invalid UTF-8 sequence");
					char[4] buffer;
					immutable len = encode!(UseReplacementDchar.yes)(buffer,
							cast(dchar) to!ulong(data[index + 1 .. index + 1 + size], 16));
					ret.put(buffer[0 .. len].idup);
					index += size;
				}

				switch (data[index])
				{
				case '"':
					ret.put('"');
					break;
				case '\\':
					ret.put('\\');
					break;
				case 'b':
					ret.put('\b');
					break;
				case 't':
					ret.put('\t');
					break;
				case 'n':
					ret.put('\n');
					break;
				case 'f':
					ret.put('\f');
					break;
				case 'r':
					ret.put('\r');
					break;
				case 'u':
					readUnicode!4();
					break;
				case 'U':
					readUnicode!8();
					break;
				default:
					static if (multiline)
					{
						index++;
						if (clear())
						{
							// remove whitespace characters until next valid character
							index--;
							break;
						}
					}
					enforceParser(false, "Invalid escape sequence: '\\" ~ (index < data.length
							? [data[index]] : "EOF") ~ "'");
				}
				backslash = false;
			}
			else
			{
				if (data[index] == '\\')
				{
					backslash = true;
				}
				else if (data[index] == '"')
				{
					// string closed
					index++;
					static if (multiline)
					{
						// control that the string is really closed
						if (index + 2 <= data.length && data[index .. index + 2] == "\"\"")
						{
							index += 2;
							return ret.data.stripFirstLine;
						}
						else
						{
							ret.put("\"");
							continue;
						}
					}
					else
					{
						return ret.data;
					}
				}
				else
				{
					static if (multiline)
					{
						mixin(doLineConversion);
					}
					ret.put(data[index]);
				}
			}
			index++;
		}
		error("Expecting \" (double quote) but found EOF");
		assert(0);
	}

	string readSimpleQuotedString(bool multiline)()
	{
		Appender!string ret;
		while (index < data.length)
		{
			static if (!multiline)
			{
				enforceParser(data[index] != '\n', "Unterminated quoted string");
			}
			if (data[index] == '\'')
			{
				// closed
				index++;
				static if (multiline)
				{
					// there must be 3 of them
					if (index + 2 <= data.length && data[index .. index + 2] == "''")
					{
						index += 2;
						return ret.data.stripFirstLine;
					}
					else
					{
						ret.put("'");
					}
				}
				else
				{
					return ret.data;
				}
			}
			else
			{
				static if (multiline)
				{
					mixin(doLineConversion);
				}
				ret.put(data[index++]);
			}
		}
		error("Expecting ' (single quote) but found EOF");
		assert(0);
	}

	string removeUnderscores(string str, string[] ranges...)
	{
		bool checkRange(char c)
		{
			foreach (range; ranges)
			{
				if (c >= range[0] && c <= range[1])
					return true;
			}
			return false;
		}

		bool underscore = false;
		for (size_t i = 0; i < str.length; i++)
		{
			if (str[i] == '_')
			{
				if (underscore || i == 0 || i == str.length - 1
						|| !checkRange(str[i - 1]) || !checkRange(str[i + 1]))
					throw new Exception("");
				str = str[0 .. i] ~ str[i + 1 .. $];
				i--;
				underscore = true;
			}
			else
			{
				underscore = false;
			}
		}
		return str;
	}

	TOMLValue readSpecial()
	{
		immutable start = index;
		while (index < data.length && !"\t\r\n,]}#".canFind(data[index]))
			index++;
		string ret = data[start .. index].stripRight(' ');
		enforceParser(ret.length > 0, "Invalid empty value");
		switch (ret)
		{
		case "true":
			return TOMLValue(true);
		case "false":
			return TOMLValue(false);
		case "inf":
		case "+inf":
			return TOMLValue(double.infinity);
		case "-inf":
			return TOMLValue(-double.infinity);
		case "nan":
		case "+nan":
			return TOMLValue(double.nan);
		case "-nan":
			return TOMLValue(-double.nan);
		default:
			immutable original = ret;
			try
			{
				if (ret.length >= 10 && ret[4] == '-' && ret[7] == '-')
				{
					// date or datetime
					if (ret.length >= 19 && (ret[10] == 'T' || ret[10] == ' ')
							&& ret[13] == ':' && ret[16] == ':')
					{
						// datetime
						if (ret[10] == ' ')
							ret = ret[0 .. 10] ~ 'T' ~ ret[11 .. $];
						if (ret[19 .. $].canFind("-") || ret[$ - 1] == 'Z')
						{
							// has timezone
							return TOMLValue(SysTime.fromISOExtString(ret));
						}
						else
						{
							// is space allowed instead of T?
							return TOMLValue(DateTime.fromISOExtString(ret));
						}
					}
					else
					{
						return TOMLValue(Date.fromISOExtString(ret));
					}
				}
				else if (ret.length >= 8 && ret[2] == ':' && ret[5] == ':')
				{
					return TOMLValue(TimeOfDay.fromISOExtString(ret));
				}
				if (ret.length > 2 && ret[0] == '0')
				{
					switch (ret[1])
					{
					case 'x':
						return TOMLValue(to!long(removeUnderscores(ret[2 .. $],
								"09", "AZ", "az"), 16));
					case 'o':
						return TOMLValue(to!long(removeUnderscores(ret[2 .. $], "08"), 8));
					case 'b':
						return TOMLValue(to!long(removeUnderscores(ret[2 .. $], "01"), 2));
					default:
						break;
					}
				}
				if (ret.canFind('.') || ret.canFind('e') || ret.canFind('E'))
				{
					return TOMLValue(to!double(removeUnderscores(ret, "09")));
				}
				else
				{
					if (ret[0] != '0' || ret.length == 1)
						return TOMLValue(to!long(removeUnderscores(ret, "09")));
				}
			}
			catch (Exception)
			{
			}
			// not a valid value at this point
			if (options & TOMLOptions.unquotedStrings)
				return TOMLValue(original);
			else
				error("Invalid type: '" ~ original ~ "'");
			assert(0);
		}
	}

	string readKey()
	{
		enforceParser(index < data.length, "Key declaration expected but found EOF");
		string ret;
		if (data[index] == '"')
		{
			index++;
			ret = readQuotedString!false();
		}
		else if (data[index] == '\'')
		{
			index++;
			ret = readSimpleQuotedString!false();
		}
		else
		{
			Appender!string appender;
			while (index < data.length && isValidKeyChar(data[index]))
			{
				appender.put(data[index++]);
			}
			ret = appender.data;
			enforceParser(ret.length != 0, "Key is empty or contains invalid characters");
		}
		return ret;
	}

	string[] readKeys()
	{
		string[] keys;
		index--;
		do
		{
			index++;
			clear!false();
			keys ~= readKey();
			clear!false();
		}
		while (index < data.length && data[index] == '.');
		enforceParser(keys.length != 0, "Key cannot be empty");
		return keys;
	}

	TOMLValue readValue()
	{
		if (index < data.length)
		{
			switch (data[index++])
			{
			case '"':
				if (index + 2 <= data.length && data[index .. index + 2] == "\"\"")
				{
					index += 2;
					return TOMLValue(readQuotedString!true());
				}
				else
				{
					return TOMLValue(readQuotedString!false());
				}
			case '\'':
				if (index + 2 <= data.length && data[index .. index + 2] == "''")
				{
					index += 2;
					return TOMLValue(readSimpleQuotedString!true());
				}
				else
				{
					return TOMLValue(readSimpleQuotedString!false());
				}
			case '[':
				clear();
				TOMLValue[] array;
				bool comma = true;
				while (data[index] != ']')
				{ //TODO check range error
					enforceParser(comma, "Elements of the array must be separated with a comma");
					array ~= readValue();
					clear!false(); // spaces allowed between elements and commas
					if (data[index] == ',')
					{ //TODO check range error
						index++;
						comma = true;
					}
					else
					{
						comma = false;
					}
					clear(); // spaces and newlines allowed between elements
				}
				index++;
				return TOMLValue(array);
			case '{':
				clear!false();
				TOMLValue[string] table;
				bool comma = true;
				while (data[index] != '}')
				{ //TODO check range error
					enforceParser(comma, "Elements of the table must be separated with a comma");
					auto keys = readKeys();
					enforceParser(clear!false() && data[index++] == '='
							&& clear!false(), "Expected value after key declaration");
					setImpl(&table, keys, keys, readValue());
					enforceParser(clear!false(),
							"Expected ',' or '}' but found " ~ (index < data.length ? "EOL" : "EOF"));
					if (data[index] == ',')
					{
						index++;
						comma = true;
					}
					else
					{
						comma = false;
					}
					clear!false();
				}
				index++;
				return TOMLValue(table);
			default:
				index--;
				break;
			}
		}
		return readSpecial();
	}

	void readKeyValue(string[] keys)
	{
		if (clear())
		{
			enforceParser(data[index++] == '=', "Expected '=' after key declaration");
			if (clear!false())
			{
				set(keys, readValue());
				// there must be nothing after the key/value declaration except comments and whitespaces
				if (clear!false())
					enforceParser(data[index] == '\n',
							"Invalid characters after value declaration: " ~ data[index]);
			}
			else
			{
				//TODO throw exception (missing value)
			}
		}
		else
		{
			//TODO throw exception (missing value)
		}
	}

	void next()
	{

		if (data[index] == '[')
		{
			current = &_ret; // reset base
			index++;
			bool array = false;
			if (index < data.length && data[index] == '[')
			{
				index++;
				array = true;
			}
			string[] keys = readKeys();
			enforceParser(index < data.length && data[index++] == ']',
					"Invalid " ~ (array ? "array" : "table") ~ " key declaration");
			if (array)
				enforceParser(index < data.length && data[index++] == ']',
						"Invalid array key declaration");
			if (!array)
			{
				//TODO only enforce if every key is a table
				enforceParser(!tableNames.canFind(keys),
						"Table name has already been directly defined");
				tableNames ~= keys;
			}
			void update(string key, bool allowArray = true)
			{
				if (key !in *current)
					set([key], TOMLValue(TOML_TYPE.TABLE));
				auto ret = (*current)[key];
				if (ret.type == TOML_TYPE.TABLE)
					current = &((*current)[key].table());
				else if (allowArray && ret.type == TOML_TYPE.ARRAY)
					current = &((*current)[key].array[$ - 1].table());
				else
					error("Invalid type");
			}

			foreach (immutable key; keys[0 .. $ - 1])
			{
				update(key);
			}
			if (array)
			{
				auto exist = keys[$ - 1] in *current;
				if (exist)
				{
					//TODO must be an array
					(*exist).array ~= TOMLValue(TOML_TYPE.TABLE);
				}
				else
				{
					set([keys[$ - 1]], TOMLValue([TOMLValue(TOML_TYPE.TABLE)]));
				}
				current = &((*current)[keys[$ - 1]].array[$ - 1].table());
			}
			else
			{
				update(keys[$ - 1], false);
			}
		}
		else
		{
			readKeyValue(readKeys());
		}

	}

	while (clear())
	{
		next();
	}

	return TOMLDocument(_ret);

}

private @property string stripFirstLine(string data)
{
	size_t i = 0;
	while (i < data.length && data[i] != '\n')
		i++;
	if (data[0 .. i].strip.length == 0)
		return data[i + 1 .. $];
	else
		return data;
}

version (Windows)
{
	// convert posix's line ending to windows'
	private enum doLineConversion = q{
		if(data[index] == '\n' && index != 0 && data[index-1] != '\r') {
			index++;
			ret.put("\r\n");
			continue;
		}
	};
}
else
{
	// convert windows' line ending to posix's
	private enum doLineConversion = q{
		if(data[index] == '\r' && index + 1 < data.length && data[index+1] == '\n') {
			index += 2;
			ret.put("\n");
			continue;
		}
	};
}

unittest
{

	TOMLDocument doc;

	// tests from the official documentation
	// https://github.com/toml-lang/toml/blob/master/README.md

	doc = parseTOML(`
		# This is a TOML document.

		title = "TOML Example"

		[owner]
		name = "Tom Preston-Werner"
		dob = 1979-05-27T07:32:00-08:00 # First class dates

		[database]
		server = "192.168.1.1"
		ports = [ 8001, 8001, 8002 ]
		connection_max = 5000
		enabled = true

		[servers]

		  # Indentation (tabs and/or spaces) is allowed but not required
		  [servers.alpha]
		  ip = "10.0.0.1"
		  dc = "eqdc10"

		  [servers.beta]
		  ip = "10.0.0.2"
		  dc = "eqdc10"

		[clients]
		data = [ ["gamma", "delta"], [1, 2] ]

		# Line breaks are OK when inside arrays
		hosts = [
		  "alpha",
		  "omega"
		]
	`);
	assert(doc["title"] == "TOML Example");
	assert(doc["owner"]["name"] == "Tom Preston-Werner");
	assert(doc["owner"]["dob"] == SysTime.fromISOExtString("1979-05-27T07:32:00-08:00"));
	assert(doc["database"]["server"] == "192.168.1.1");
	assert(doc["database"]["ports"] == [8001, 8001, 8002]);
	assert(doc["database"]["connection_max"] == 5000);
	assert(doc["database"]["enabled"] == true);
	//TODO
	assert(doc["clients"]["data"][0] == ["gamma", "delta"]);
	assert(doc["clients"]["data"][1] == [1, 2]);
	assert(doc["clients"]["hosts"] == ["alpha", "omega"]);

	doc = parseTOML(`
		# This is a full-line comment
		key = "value"
	`);
	assert("key" in doc);
	assert(doc["key"].type == TOML_TYPE.STRING);
	assert(doc["key"].str == "value");

	foreach (k, v; doc)
	{
		assert(k == "key");
		assert(v.type == TOML_TYPE.STRING);
		assert(v.str == "value");
	}

	assertThrown!TOMLException({ parseTOML(`key = # INVALID`); }());
	assertThrown!TOMLException({ parseTOML("key =\nkey2 = 'test'"); }());

	// ----
	// Keys
	// ----

	// bare keys
	doc = parseTOML(`
		key = "value"
		bare_key = "value"
		bare-key = "value"
		1234 = "value"
	`);
	assert(doc["key"] == "value");
	assert(doc["bare_key"] == "value");
	assert(doc["bare-key"] == "value");
	assert(doc["1234"] == "value");

	// quoted keys
	doc = parseTOML(`
		"127.0.0.1" = "value"
		"character encoding" = "value"
		"ʎǝʞ" = "value"
		'key2' = "value"
		'quoted "value"' = "value"
	`);
	assert(doc["127.0.0.1"] == "value");
	assert(doc["character encoding"] == "value");
	assert(doc["ʎǝʞ"] == "value");
	assert(doc["key2"] == "value");
	assert(doc["quoted \"value\""] == "value");

	// no key name
	assertThrown!TOMLException({ parseTOML(`= "no key name" # INVALID`); }());

	// empty key
	assert(parseTOML(`"" = "blank"`)[""] == "blank");
	assert(parseTOML(`'' = 'blank'`)[""] == "blank");

	// dotted keys
	doc = parseTOML(`
		name = "Orange"
		physical.color = "orange"
		physical.shape = "round"
		site."google.com" = true
	`);
	assert(doc["name"] == "Orange");
	assert(doc["physical"] == ["color" : "orange", "shape" : "round"]);
	assert(doc["site"]["google.com"] == true);

	// ------
	// String
	// ------

	// basic strings
	doc = parseTOML(`str = "I'm a string. \"You can quote me\". Name\tJos\u00E9\nLocation\tSF."`);
	assert(doc["str"] == "I'm a string. \"You can quote me\". Name\tJosé\nLocation\tSF.");

	// multi-line basic strings
	doc = parseTOML(`str1 = """
Roses are red
Violets are blue"""`);
	version (Posix)
		assert(doc["str1"] == "Roses are red\nViolets are blue");
	else
		assert(doc["str1"] == "Roses are red\r\nViolets are blue");

	doc = parseTOML(`
		# The following strings are byte-for-byte equivalent:
		str1 = "The quick brown fox jumps over the lazy dog."
		
		str2 = """
The quick brown \


		  fox jumps over \
		    the lazy dog."""
		
		str3 = """\
			The quick brown \
			fox jumps over \
			the lazy dog.\
       """`);
	assert(doc["str1"] == "The quick brown fox jumps over the lazy dog.");
	assert(doc["str1"] == doc["str2"]);
	assert(doc["str1"] == doc["str3"]);

	// literal strings
	doc = parseTOML(`
		# What you see is what you get.
		winpath  = 'C:\Users\nodejs\templates'
		winpath2 = '\\ServerX\admin$\system32\'
		quoted   = 'Tom "Dubs" Preston-Werner'
		regex    = '<\i\c*\s*>'
	`);
	assert(doc["winpath"] == `C:\Users\nodejs\templates`);
	assert(doc["winpath2"] == `\\ServerX\admin$\system32\`);
	assert(doc["quoted"] == `Tom "Dubs" Preston-Werner`);
	assert(doc["regex"] == `<\i\c*\s*>`);

	// multi-line literal strings
	doc = parseTOML(`
		regex2 = '''I [dw]on't need \d{2} apples'''
		lines  = '''
The first newline is
trimmed in raw strings.
   All other whitespace
   is preserved.
'''`);
	assert(doc["regex2"] == `I [dw]on't need \d{2} apples`);
	assert(doc["lines"] == "The first newline is" ~ newline ~ "trimmed in raw strings."
			~ newline ~ "   All other whitespace" ~ newline ~ "   is preserved." ~ newline);

	// -------
	// Integer
	// -------

	doc = parseTOML(`
		int1 = +99
		int2 = 42
		int3 = 0
		int4 = -17
	`);
	assert(doc["int1"].type == TOML_TYPE.INTEGER);
	assert(doc["int1"].integer == 99);
	assert(doc["int2"] == 42);
	assert(doc["int3"] == 0);
	assert(doc["int4"] == -17);

	doc = parseTOML(`
		int5 = 1_000
		int6 = 5_349_221
		int7 = 1_2_3_4_5     # VALID but discouraged
	`);
	assert(doc["int5"] == 1_000);
	assert(doc["int6"] == 5_349_221);
	assert(doc["int7"] == 1_2_3_4_5);

	// leading 0s not allowed
	assertThrown!TOMLException({ parseTOML(`invalid = 01`); }());

	// underscores must be enclosed in numbers
	assertThrown!TOMLException({ parseTOML(`invalid = _123`); }());
	assertThrown!TOMLException({ parseTOML(`invalid = 123_`); }());
	assertThrown!TOMLException({ parseTOML(`invalid = 123__123`); }());
	assertThrown!TOMLException({ parseTOML(`invalid = 0b01_21`); }());
	assertThrown!TOMLException({ parseTOML(`invalid = 0x_deadbeef`); }());
	assertThrown!TOMLException({ parseTOML(`invalid = 0b0101__00`); }());

	doc = parseTOML(`
		# hexadecimal with prefix 0x
		hex1 = 0xDEADBEEF
		hex2 = 0xdeadbeef
		hex3 = 0xdead_beef

		# octal with prefix 0o
		oct1 = 0o01234567
		oct2 = 0o755 # useful for Unix file permissions

		# binary with prefix 0b
		bin1 = 0b11010110
	`);
	assert(doc["hex1"] == 0xDEADBEEF);
	assert(doc["hex2"] == 0xdeadbeef);
	assert(doc["hex3"] == 0xdead_beef);
	assert(doc["oct1"] == 342391);
	assert(doc["oct2"] == 493);
	assert(doc["bin1"] == 0b11010110);

	assertThrown!TOMLException({ parseTOML(`invalid = 0h111`); }());

	// -----
	// Float
	// -----

	doc = parseTOML(`
		# fractional
		flt1 = +1.0
		flt2 = 3.1415
		flt3 = -0.01

		# exponent
		flt4 = 5e+22
		flt5 = 1e6
		flt6 = -2E-2

		# both
		flt7 = 6.626e-34
	`);
	assert(doc["flt1"].type == TOML_TYPE.FLOAT);
	assert(doc["flt1"].floating == 1);
	assert(doc["flt2"] == 3.1415);
	assert(doc["flt3"] == -.01);
	assert(doc["flt4"] == 5e+22);
	assert(doc["flt5"] == 1e6);
	assert(doc["flt6"] == -2E-2);
	assert(doc["flt7"] == 6.626e-34);

	doc = parseTOML(`flt8 = 9_224_617.445_991_228_313`);
	assert(doc["flt8"] == 9_224_617.445_991_228_313);

	doc = parseTOML(`
		# infinity
		sf1 = inf  # positive infinity
		sf2 = +inf # positive infinity
		sf3 = -inf # negative infinity

		# not a number
		sf4 = nan  # actual sNaN/qNaN encoding is implementation specific
		sf5 = +nan # same as nan
		sf6 = -nan # valid, actual encoding is implementation specific
	`);
	assert(doc["sf1"] == double.infinity);
	assert(doc["sf2"] == double.infinity);
	assert(doc["sf3"] == -double.infinity);
	assert(doc["sf4"].floating.isNaN());
	assert(doc["sf5"].floating.isNaN());
	assert(doc["sf6"].floating.isNaN());

	// -------
	// Boolean
	// -------

	doc = parseTOML(`
		bool1 = true
		bool2 = false
	`);
	assert(doc["bool1"].type == TOML_TYPE.TRUE);
	assert(doc["bool2"].type == TOML_TYPE.FALSE);
	assert(doc["bool1"] == true);
	assert(doc["bool2"] == false);

	// ----------------
	// Offset Date-Time
	// ----------------

	doc = parseTOML(`
		odt1 = 1979-05-27T07:32:00Z
		odt2 = 1979-05-27T00:32:00-07:00
		odt3 = 1979-05-27T00:32:00.999999-07:00
	`);
	assert(doc["odt1"].type == TOML_TYPE.OFFSET_DATETIME);
	assert(doc["odt1"].offsetDatetime == SysTime.fromISOExtString("1979-05-27T07:32:00Z"));
	assert(doc["odt2"] == SysTime.fromISOExtString("1979-05-27T00:32:00-07:00"));
	assert(doc["odt3"] == SysTime.fromISOExtString("1979-05-27T00:32:00.999999-07:00"));

	doc = parseTOML(`odt4 = 1979-05-27 07:32:00Z`);
	assert(doc["odt4"] == SysTime.fromISOExtString("1979-05-27T07:32:00Z"));

	// ---------------
	// Local Date-Time
	// ---------------

	doc = parseTOML(`
		ldt1 = 1979-05-27T07:32:00
		ldt2 = 1979-05-27T00:32:00.999999
	`);
	assert(doc["ldt1"].type == TOML_TYPE.LOCAL_DATETIME);
	assert(doc["ldt1"].localDatetime == DateTime.fromISOExtString("1979-05-27T07:32:00"));
	assert(doc["ldt2"] == DateTime.fromISOExtString("1979-05-27T00:32:00.999999"));

	// ----------
	// Local Date
	// ----------

	doc = parseTOML(`
		ld1 = 1979-05-27
	`);
	assert(doc["ld1"].type == TOML_TYPE.LOCAL_DATE);
	assert(doc["ld1"].localDate == Date.fromISOExtString("1979-05-27"));

	// ----------
	// Local Time
	// ----------

	doc = parseTOML(`
		lt1 = 07:32:00
		lt2 = 00:32:00.999999
	`);
	assert(doc["lt1"].type == TOML_TYPE.LOCAL_TIME);
	assert(doc["lt1"].localTime == TimeOfDay.fromISOExtString("07:32:00"));
	assert(doc["lt2"] == TimeOfDay.fromISOExtString("00:32:00.999999"));
	assert(doc["lt2"].localTime.fracSecs.total!"msecs" == 999999);

	// -----
	// Array
	// -----

	doc = parseTOML(`
		arr1 = [ 1, 2, 3 ]
		arr2 = [ "red", "yellow", "green" ]
		arr3 = [ [ 1, 2 ], [3, 4, 5] ]
		arr4 = [ "all", 'strings', """are the same""", '''type''']
		arr5 = [ [ 1, 2 ], ["a", "b", "c"] ]
	`);
	assert(doc["arr1"].type == TOML_TYPE.ARRAY);
	assert(doc["arr1"].array == [TOMLValue(1), TOMLValue(2), TOMLValue(3)]);
	assert(doc["arr2"] == ["red", "yellow", "green"]);
	assert(doc["arr3"] == [[1, 2], [3, 4, 5]]);
	assert(doc["arr4"] == ["all", "strings", "are the same", "type"]);
	assert(doc["arr5"] == [TOMLValue([1, 2]), TOMLValue(["a", "b", "c"])]);

	assertThrown!TOMLException({ parseTOML(`arr6 = [ 1, 2.0 ]`); }());

	doc = parseTOML(`
		arr7 = [
		  1, 2, 3
		]

		arr8 = [
		  1,
		  2, # this is ok
		]
	`);
	assert(doc["arr7"] == [1, 2, 3]);
	assert(doc["arr8"] == [1, 2]);

	// -----
	// Table
	// -----

	doc = parseTOML(`
		[table-1]
		key1 = "some string"
		key2 = 123
		
		[table-2]
		key1 = "another string"
		key2 = 456
	`);
	assert(doc["table-1"].type == TOML_TYPE.TABLE);
	assert(doc["table-1"] == ["key1" : TOMLValue("some string"), "key2" : TOMLValue(123)]);
	assert(doc["table-2"] == ["key1" : TOMLValue("another string"), "key2" : TOMLValue(456)]);

	doc = parseTOML(`
		[dog."tater.man"]
		type.name = "pug"
	`);
	assert(doc["dog"]["tater.man"]["type"]["name"] == "pug");

	doc = parseTOML(`
		[a.b.c]            # this is best practice
		[ d.e.f ]          # same as [d.e.f]
		[ g .  h  . i ]    # same as [g.h.i]
		[ j . "ʞ" . 'l' ]  # same as [j."ʞ".'l']
	`);
	assert(doc["a"]["b"]["c"].type == TOML_TYPE.TABLE);
	assert(doc["d"]["e"]["f"].type == TOML_TYPE.TABLE);
	assert(doc["g"]["h"]["i"].type == TOML_TYPE.TABLE);
	assert(doc["j"]["ʞ"]["l"].type == TOML_TYPE.TABLE);

	doc = parseTOML(`
		# [x] you
		# [x.y] don't
		# [x.y.z] need these
		[x.y.z.w] # for this to work
	`);
	assert(doc["x"]["y"]["z"]["w"].type == TOML_TYPE.TABLE);

	doc = parseTOML(`
		[a.b]
		c = 1
		
		[a]
		d = 2
	`);
	assert(doc["a"]["b"]["c"] == 1);
	assert(doc["a"]["d"] == 2);

	assertThrown!TOMLException({ parseTOML(`
			# DO NOT DO THIS
				
			[a]
			b = 1
			
			[a]
			c = 2
		`); }());

	assertThrown!TOMLException({ parseTOML(`
			# DO NOT DO THIS EITHER

			[a]
			b = 1

			[a.b]
			c = 2
		`); }());

	assertThrown!TOMLException({ parseTOML(`[]`); }());
	assertThrown!TOMLException({ parseTOML(`[a.]`); }());
	assertThrown!TOMLException({ parseTOML(`[a..b]`); }());
	assertThrown!TOMLException({ parseTOML(`[.b]`); }());
	assertThrown!TOMLException({ parseTOML(`[.]`); }());

	// ------------
	// Inline Table
	// ------------

	doc = parseTOML(`
		name = { first = "Tom", last = "Preston-Werner" }
		point = { x = 1, y = 2 }
		animal = { type.name = "pug" }
	`);
	assert(doc["name"]["first"] == "Tom");
	assert(doc["name"]["last"] == "Preston-Werner");
	assert(doc["point"] == ["x" : 1, "y" : 2]);
	assert(doc["animal"]["type"]["name"] == "pug");

	// ---------------
	// Array of Tables
	// ---------------

	doc = parseTOML(`
		[[products]]
		name = "Hammer"
		sku = 738594937
		
		[[products]]
		
		[[products]]
		name = "Nail"
		sku = 284758393
		color = "gray"
	`);
	assert(doc["products"].type == TOML_TYPE.ARRAY);
	assert(doc["products"].array.length == 3);
	assert(doc["products"][0] == ["name" : TOMLValue("Hammer"), "sku" : TOMLValue(738594937)]);
	assert(doc["products"][1] == (TOMLValue[string]).init);
	assert(doc["products"][2] == ["name" : TOMLValue("Nail"), "sku"
			: TOMLValue(284758393), "color" : TOMLValue("gray")]);

	// nested
	doc = parseTOML(`
		[[fruit]]
		  name = "apple"

		  [fruit.physical]
		    color = "red"
		    shape = "round"

		  [[fruit.variety]]
		    name = "red delicious"

		  [[fruit.variety]]
		    name = "granny smith"

		[[fruit]]
		  name = "banana"

		  [[fruit.variety]]
		    name = "plantain"
	`);
	assert(doc["fruit"].type == TOML_TYPE.ARRAY);
	assert(doc["fruit"].array.length == 2);
	assert(doc["fruit"][0]["name"] == "apple");
	assert(doc["fruit"][0]["physical"] == ["color" : "red", "shape" : "round"]);
	assert(doc["fruit"][0]["variety"][0] == ["name" : "red delicious"]);
	assert(doc["fruit"][0]["variety"][1]["name"] == "granny smith");
	assert(doc["fruit"][1] == ["name" : TOMLValue("banana"), "variety"
			: TOMLValue([["name" : "plantain"]])]);

	assertThrown!TOMLException({ parseTOML(`
			# INVALID TOML DOC
			[[fruit]]
			  name = "apple"

			  [[fruit.variety]]
			    name = "red delicious"

			  # This table conflicts with the previous table
			  [fruit.variety]
			    name = "granny smith"
		`); }());

	doc = parseTOML(`
		points = [ { x = 1, y = 2, z = 3 },
			{ x = 7, y = 8, z = 9 },
			{ x = 2, y = 4, z = 8 } ]
	`);
	assert(doc["points"].array.length == 3);
	assert(doc["points"][0] == ["x" : 1, "y" : 2, "z" : 3]);
	assert(doc["points"][1] == ["x" : 7, "y" : 8, "z" : 9]);
	assert(doc["points"][2] == ["x" : 2, "y" : 4, "z" : 8]);

	// additional tests for code coverage

	assert(TOMLValue(42) == 42.0);
	assert(TOMLValue(42) != "42");
	assert(TOMLValue("42") != 42);

	try
	{
		parseTOML(`
			
			error = @		
		`);
	}
	catch (TOMLParserException e)
	{
		assert(e.position.line == 3); // start from line 1
		assert(e.position.column == 9 + 3); // 3 tabs
	}

	assertThrown!TOMLException({ parseTOML(`error = "unterminated`); }());
	assertThrown!TOMLException({ parseTOML(`error = 'unterminated`); }());
	assertThrown!TOMLException({ parseTOML(`error = "\ "`); }());

	assertThrown!TOMLException({ parseTOML(`error = truè`); }());
	assertThrown!TOMLException({ parseTOML(`error = falsè`); }());

	assertThrown!TOMLException({ parseTOML(`[error`); }());

	doc = parseTOML(`test = "\\\"\b\t\n\f\r\u0040\U00000040"`);
	assert(doc["test"] == "\\\"\b\t\n\f\r@@");

	doc = parseTOML(`test = """quoted "string"!"""`);
	assert(doc["test"] == "quoted \"string\"!");

	// options

	assert(parseTOML(`raw = this is unquoted`,
			TOMLOptions.unquotedStrings)["raw"] == "this is unquoted");

	// document

	TOMLValue value = TOMLValue(["test" : 44]);
	doc = TOMLDocument(value);

	// opEquals

	assert(TOMLValue(true) == TOMLValue(true));
	assert(TOMLValue("string") == TOMLValue("string"));
	assert(TOMLValue(0) == TOMLValue(0));
	assert(TOMLValue(.0) == TOMLValue(.0));
	assert(TOMLValue(SysTime.fromISOExtString("1979-05-27T00:32:00-07:00")) == TOMLValue(
			SysTime.fromISOExtString("1979-05-27T00:32:00-07:00")));
	assert(TOMLValue(DateTime.fromISOExtString("1979-05-27T07:32:00")) == TOMLValue(
			DateTime.fromISOExtString("1979-05-27T07:32:00")));
	assert(TOMLValue(Date.fromISOExtString("1979-05-27")) == TOMLValue(
			Date.fromISOExtString("1979-05-27")));
	assert(TOMLValue(TimeOfDay.fromISOExtString("07:32:00")) == TOMLValue(
			TimeOfDay.fromISOExtString("07:32:00")));
	assert(TOMLValue([1, 2, 3]) == TOMLValue([1, 2, 3]));
	assert(TOMLValue(["a" : 0, "b" : 1]) == TOMLValue(["a" : 0, "b" : 1]));

	// toString()

	assert(TOMLDocument(["test" : TOMLValue(0)]).toString() == "test = 0" ~ newline);

	assert(TOMLValue(true).toString() == "true");
	assert(TOMLValue("string").toString() == "\"string\"");
	assert(TOMLValue("\"quoted \\ \b \f \r\n \t string\"")
			.toString() == "\"\\\"quoted \\\\ \\b \\f \\r\\n \\t string\\\"\"");
	assert(TOMLValue(42).toString() == "42");
	assert(TOMLValue(99.44).toString() == "99.44");
	assert(TOMLValue(.0).toString() == "0.0");
	assert(TOMLValue(1e100).toString() == "1e+100");
	assert(TOMLValue(SysTime.fromISOExtString("1979-05-27T00:32:00-07:00"))
			.toString() == "1979-05-27T00:32:00-07:00");
	assert(TOMLValue(DateTime.fromISOExtString("1979-05-27T07:32:00"))
			.toString() == "1979-05-27T07:32:00");
	assert(TOMLValue(Date.fromISOExtString("1979-05-27")).toString() == "1979-05-27");
	assert(TOMLValue(TimeOfDay.fromISOExtString("07:32:00.999999")).toString() == "07:32:00.999999");
	assert(TOMLValue([1, 2, 3]).toString() == "[1, 2, 3]");
	immutable table = TOMLValue(["a" : 0, "b" : 1]).toString();
	assert(table == "{ a = 0, b = 1 }" || table == "{ b = 1, a = 0 }");

	foreach (key, value; TOMLValue(["0" : 0, "1" : 1]))
	{
		assert(value == key.to!int);
	}

	value = 42;
	assert(value.type == TOML_TYPE.INTEGER);
	assert(value == 42);
	value = TOMLValue("42");
	assert(value.type == TOML_TYPE.STRING);
	assert(value == "42");

}

/**
 * Exception thrown on generic TOML errors.
 */
class TOMLException : Exception
{

	public this(string message, string file = __FILE__, size_t line = __LINE__)
	{
		super(message, file, line);
	}

}

/**
 * Exception thrown during the parsing of TOML document.
 */
class TOMLParserException : TOMLException
{

	private Tuple!(size_t, "line", size_t, "column") _position;

	public this(string message, size_t line, size_t column, string file = __FILE__,
			size_t _line = __LINE__)
	{
		super(message ~ " (" ~ to!string(line) ~ ":" ~ to!string(column) ~ ")", file, _line);
		this._position.line = line;
		this._position.column = column;
	}

	/**
	 * Gets the position (line and column) where the parsing expection
	 * has occured.
	 */
	public pure nothrow @property @safe @nogc auto position()
	{
		return this._position;
	}

}
