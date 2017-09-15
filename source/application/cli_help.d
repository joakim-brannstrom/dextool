/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Command Line Interface functionality and text to display help for the user.
*/
module dextool.cli_help;

enum string mainOptions = `usage:
 dextool <command> [options] [<args>...]

options:
 -h, --help         show this global help
 -d, --debug        turn on debug output for detailed tracing
 --version          print the version of dextool
 --plugin-list      print a list of plugins

commands:
  help
`;

enum string basicHelp = "
 -h, --help         show this help
";

enum string commandGrouptHelp = "

See 'dextool <command> -h' to read about a specific subcommand.
";
