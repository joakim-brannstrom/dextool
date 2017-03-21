module dextool.plugin.frontend.fuzz;

import logger = std.experimental.logger;

struct RawConfiguration {
    string xml_dir; //Base directory which contains XML interfaces
    string compile_db;

    /* Predefined error messages, used for showing user */
    string XML_ARG_MISSING = "Missing xmldir as argument";
    string COMPILE_DB_MISSING = "Missing compile-db as argument";

    string help_msg = "Usage: dextool fuzz --compile-db=... --xml-dir=...";

    bool help;

    /*
    * Parses arguments from terminal
    * @param args Equal to argv
    */
    void parse(string[] args) {
        import std.getopt : getopt, GetOptException;
        try { 
            auto helpInformation = getopt(args, std.getopt.config.keepEndOfOptions,
                    "h|help", &help, "xml-dir", &xml_dir,
                    "compile-db", &compile_db);
        }
        catch(GetOptException ex) {
            logger.error(ex.msg);
            printHelp();
            return;
        }

        if(xml_dir.length == 0) {
            printHelp();
            return;
        }
    }
    /*
     * Outputs a help message to the user
     */
    void printHelp(string err_msg) {
        import std.stdio : writefln;

        writefln("%s\n%s", err_msg, help_msg);
    }
}