// Written in the D programming language.

/**
 * 
 * Custom types for TOML's datetimes that add fractional time to D ones.
 *
 * License: $(HTTP https://github.com/Kripth/toml/blob/master/LICENSE, MIT)
 * Authors: Kripth
 * References: $(LINK https://github.com/toml-lang/toml/blob/master/README.md)
 * Source: $(HTTP https://github.com/Kripth/toml/blob/master/src/toml/datetime.d, toml/_datetime.d)
 * 
 */
module toml.datetime;

import std.conv : to;
import std.datetime : Duration, dur, DateTimeD = DateTime, Date,
	TimeOfDayD = TimeOfDay;

struct DateTime
{

	public Date date;
	public TimeOfDay timeOfDay;

	public inout @property DateTimeD dateTime()
	{
		return DateTimeD(this.date, this.timeOfDay.timeOfDay);
	}

	alias dateTime this;

	public static pure DateTime fromISOExtString(string str)
	{
		Duration frac;
		if (str.length > 19 && str[19] == '.')
		{
			frac = dur!"msecs"(to!ulong(str[20 .. $]));
			str = str[0 .. 19];
		}
		auto dt = DateTimeD.fromISOExtString(str);
		return DateTime(dt.date, TimeOfDay(dt.timeOfDay, frac));
	}

	public inout string toISOExtString()
	{
		return this.date.toISOExtString() ~ "T" ~ this.timeOfDay.toString();
	}

}

struct TimeOfDay
{

	public TimeOfDayD timeOfDay;
	public Duration fracSecs;

	alias timeOfDay this;

	public static pure TimeOfDay fromISOExtString(string str)
	{
		Duration frac;
		if (str.length > 8 && str[8] == '.')
		{
			frac = dur!"msecs"(to!ulong(str[9 .. $]));
			str = str[0 .. 8];
		}
		return TimeOfDay(TimeOfDayD.fromISOExtString(str), frac);
	}

	public inout string toISOExtString()
	{
		immutable msecs = this.fracSecs.total!"msecs";
		if (msecs != 0)
		{
			return this.timeOfDay.toISOExtString() ~ "." ~ to!string(msecs);
		}
		else
		{
			return this.timeOfDay.toISOExtString();
		}
	}

}
