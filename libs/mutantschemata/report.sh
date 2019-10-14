#!/bin/bash

db=$1

if ! [[ $db = *".sqlite3" ]]; then
    echo "Please provide path to your schemata-database (default: dextool_mutate.sqlite3)"
    exit 1    
fi

unknown=$(sqlite3 $db "SELECT count(*) FROM DSchemataMutant WHERE status=0")
killed=$(sqlite3 $db "SELECT count(*) FROM DSchemataMutant WHERE status=1")
alive=$(sqlite3 $db "SELECT count(*) FROM DSchemataMutant WHERE status=2")
killedByCompiler=$(sqlite3 $db "SELECT count(*) FROM DSchemataMutant WHERE status=3")
timeout=$(sqlite3 $db "SELECT count(*) FROM DSchemataMutant WHERE status=4")
total=$(sqlite3 $db "SELECT count(*) FROM DSchemataMutant")

echo ""
echo " ** Short report for Mutant Schemata ** "
echo "        Amount of mutants:     $total"
echo "        Unknown:               $unknown"
echo "        Killed:                $killed"
echo "        Alive:                 $alive"
echo "        KilledByCompiler:      $killedByCompiler"
echo "        Timeout:               $timeout"
echo "    Mutation Score:              $(echo "($killed+$timeout)/($killed+$timeout+$alive)" | bc -l)"
echo "    (unknown included):          $(echo "($killed+$timeout)/($killed+$timeout+$alive+$unknown)" | bc -l)"
echo ""
