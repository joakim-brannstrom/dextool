module dextool.plugin.frontend.fuzz;

import logger = std.experimental.logger;

struct RawConfiguration {
    string[] xml_dir; //Base directory which contains XML interfaces
    string[] compile_db;

    /* Predefined error messages, used for showing user */
    string XML_ARG_MISSING = "Missing xml-dir as argument";
    string COMPILE_DB_MISSING = "Missing compile-db as argument";

    string help_msg = "Usage: dextool fuzz --compile-db=... --xml-dir=...";

    bool shortPluginHelp;

    /*
    * Parses arguments from terminal
    * @param args Equal to argv
    */
    void parse(string[] args) {
        import std.getopt;
        import std.stdio : writeln;
        try {
            auto helpInformation = getopt(args, std.getopt.config.keepEndOfOptions,
                    "xml-dir", "Base directories to XML interfaces", &xml_dir,
                    "compile-db", "Base directories to compilation databases", &compile_db,
                    "short-plugin-help", &shortPluginHelp);
            
            if (helpInformation.helpWanted) {
                defaultGetoptPrinter("Usage.",
                    helpInformation.options);
                return;
            }

            /* Check default arguments */
            if(!shortPluginHelp && xml_dir.length == 0) {
                defaultGetoptPrinter(XML_ARG_MISSING,
                    helpInformation.options);
                return;
            }

            if(!shortPluginHelp && compile_db.length == 0) {
                defaultGetoptPrinter(COMPILE_DB_MISSING,
                    helpInformation.options);
                return;
            }

        } catch(GetOptException ex) {
            writeln("ERROR: " ~ ex.msg);
            return;
        }
    }
}