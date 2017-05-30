/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool.io;

import std.stdio : File;
import logger = std.experimental.logger;

import dextool.type : ExitStatusType;

///TODO don't catch Exception, catch the specific.
auto tryOpenFile(string filename, string mode) @trusted {
    import std.exception;
    import std.typecons : Unique;

    Unique!File rval;

    try {
        rval = Unique!File(new File(filename, mode));
    }
    catch (Exception ex) {
    }
    if (rval.isEmpty) {
        try {
            logger.errorf("Unable to read/write file '%s'", filename);
        }
        catch (Exception ex) {
        }
    }

    return rval;
}

///TODO don't catch Exception, catch the specific.
auto tryWriting(T)(string fname, T data) @trusted nothrow {
    import std.exception;

    static auto action(T)(string fname, T data) {
        auto f = tryOpenFile(fname, "w");

        if (f.isEmpty) {
            return ExitStatusType.Errors;
        }
        scope (exit)
            f.close();

        f.rawWrite(cast(void[]) data);

        return ExitStatusType.Ok;
    }

    auto status = ExitStatusType.Errors;

    try {
        status = action(fname, data);
    }
    catch (Exception ex) {
    }

    try {
        final switch (status) with (ExitStatusType) {
        case Ok:
            break;
        case Errors:
            logger.error("Failed to write to file ", fname);
            break;
        }
    }
    catch (Exception ex) {
    }

    return status;
}

/** Try to write the data to the destination directory.
 *
 * If the directory do not exist try and create it.
 */
ExitStatusType writeFileData(T)(ref T data) {
    import std.path : dirName;

    static ExitStatusType tryMkdir(string path) nothrow {
        import std.file : isDir, mkdirRecurse;

        try {
            if (path.isDir) {
                return ExitStatusType.Ok;
            }
        }
        catch (Exception ex) {
        }

        try {
            mkdirRecurse(path);
            return ExitStatusType.Ok;
        }
        catch (Exception ex) {
        }

        return ExitStatusType.Errors;
    }

    foreach (p; data) {
        if (tryMkdir(p.filename.dirName) == ExitStatusType.Errors) {
            logger.error("Unable to create destination directory: ", p.filename.dirName);
        }

        auto status = tryWriting(cast(string) p.filename, p.data);
        if (status != ExitStatusType.Ok) {
            return ExitStatusType.Errors;
        }
    }

    return ExitStatusType.Ok;
}
