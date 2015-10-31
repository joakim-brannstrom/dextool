#!/bin/bash
ROOT=$PWD
INOTIFY_PATH="$ROOT/source $ROOT/dub.json"

C_NONE='\e[m'
C_RED='\e[1;31m'
C_YELLOW='\e[1;33m'
C_GREEN='\e[1;32m'

# sanity check
test ! -e $ROOT/dub.json && echo "Missing dub.json" && exit 1

# create build if missing
test ! -d build && mkdir build

# trap "build_release" INT

# init
# wait
# ut_build_run
# ut_check_status
# release_build
# release_check_status
# test_passed
# doc_check_counter
# doc_build
STATE="init"

# return value from check_status. 0 is good, anything else is bad.
CHECK_STATUS_RVAL=1
# Incremented each loop. When it reaches MAX_CNT it will build with documentation and reset counter.
DOC_CNT=9 # force a rebuild on first pass. then reset to 0.
DOC_MAX_CNT=9

function check_status() {
    CHECK_STATUS_RVAL=$?
    MSG=$1
    if [[ $CHECK_STATUS_RVAL -eq 0 ]]; then
        echo -e "${C_GREEN}=== $MSG OK ===${C_NONE}"
    else
        echo -e "${C_RED}=== $MSG ERROR ===${C_NONE}"
    fi
}

function state_init() {
    echo "Started watching path: "
    echo $INOTIFY_PATH | tr "[:blank:]" "\n"
    cp /usr/lib/llvm-3.5/lib/libclang.so $ROOT
}

function state_wait() {
    echo -e "${C_YELLOW}================================${C_NONE}"
    IFILES=$(inotifywait -q -r -e MOVE_SELF -e MODIFY -e ATTRIB -e CREATE --format %w $INOTIFY_PATH)
    echo "Change detected in: $IFILES"
    sleep 1
}

function state_ut_build_run() {
    # dub build -c unittest -b unittest
    # check_status "Compile UnitTest"
    #
    # if [[ $CHECK_STATUS_RVAL -eq 0 ]]; then
    #     dub run -b unittest
    #     check_status "Run UnitTest"
    # fi
    CHECK_STATUS_RVAL=0
    return
}

function state_release_build() {
    dub build
    # check_status "Compile Release"
    return
}

function doc_build() {
    dub build -b docs
    check_status "Generate Documentation"
    echo "firefox $ROOT/docs/"
    DOC_CNT=0
}

function play_sound() {
    # mplayer /usr/share/sounds/KDE-Sys-App-Error.ogg 2>/dev/null >/dev/null
    if [[ "$1" = "ok" ]]; then
        mplayer /usr/share/sounds/KDE-Sys-App-Positive.ogg 2>/dev/null >/dev/null &
    else
        mplayer /usr/share/sounds/KDE-Sys-App-Negative.ogg 2>/dev/null >/dev/null &
    fi
}

function watch_tests() {
while :
do
    echo "State $STATE"
    case "$STATE" in
        "init")
            state_init
            STATE="ut_build_run"
            ;;
        "wait")
            state_wait
            STATE="ut_build_run"
            ;;
        "ut_build_run")
            state_ut_build_run
            STATE="ut_check_status"
            ;;
        "ut_check_status")
            STATE="wait"
            if [[ $CHECK_STATUS_RVAL -eq 0 ]]; then
                STATE="release_build"
            else
                play_sound "fail"
            fi
            ;;
        "release_build")
            state_release_build
            STATE="release_check_status"
            ;;
        "release_check_status")
            STATE="wait"
            if [[ $CHECK_STATUS_RVAL -eq 0 ]]; then
                STATE="test_passed"
            else
                play_sound "fail"
            fi
            ;;
        "test_passed")
            # breaking the pattern of doing something in the FSM but OK hack when it is only one line
            STATE="wait"
            if [[ $DOC_CNT -ge $DOC_MAX_CNT ]]; then
                STATE="doc_build"
            else
                echo "Building doc in "$(($DOC_MAX_CNT - $DOC_CNT))" successfull passes"
                play_sound "ok"
            fi
            DOC_CNT=$(($DOC_CNT + 1))
            ;;
        "doc_build")
            STATE="wait"
            doc_build
            play_sound "ok"
            ;;
        *) echo "Unknown state $STATE"
            exit 1
            ;;
    esac
done
}

watch_tests
