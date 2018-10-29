/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.js;

immutable js_file = `
var g_show_mutant = true;
var g_active_mutid = 0;

function init() {
    var mutid = window.location.hash.substring(1);
    if(mutid) {
        set_active_mutant(mutid);
        highlight_mutant(mutid);
    }

    document.getElementById('current_mutant').addEventListener("change",
    function() {
        if (document.getElementById("current_mutant").selectedIndex == 0) {
            location.hash = "#";
            set_active_mutant(-1);
            deactivate_mutants();
            return;
        }
        var id = document.getElementById('current_mutant').value;
        set_active_mutant(id);
        highlight_mutant(id);
        document.getElementById('current_mutant').focus();
    });

    var top = document.getElementById('info').offsetTop - document.getElementById('info').style.marginTop;
    var left = window.innerWidth - document.getElementById('info').clientWidth - 30;
    document.getElementById('info').style.left = left + "px";
    document.getElementById('info').style.top = top + "px";

    for(var i=0; i<g_mutids.length; i++) {
        var s = document.createElement('OPTION');
        s.value = g_mutids[i];
        var txt = "";
        if (g_muts_st[i] == "alive")
            txt += "+";
        txt += g_mutids[i] + ":'" + g_muts_orgs[i] + "' to '" + g_muts_muts[i] + "'";
        s.text = txt;
        document.getElementById('current_mutant').add(s,g_mutids[i]);
        if (mutid == g_mutids[i])
            document.getElementById('current_mutant').selectedIndex = i+1;
    }
}

function ui_set_mut(id) {
    set_active_mutant(id);
    highlight_mutant(id);

    for(var i=0; i<g_mutids.length; i++) {
        if (id == g_mutids[i]) {
            document.getElementById('current_mutant').selectedIndex = i+1;
            break;
        }
    }
}

function set_active_mutant(mutid) {
    if (mutid) {
        g_active_mutid = mutid;
    }
}

function click_show_mutant() {
    g_show_mutant = document.getElementById("show_mutant").checked;

    if (g_show_mutant) {
        activate_mutant(g_active_mutid);
    } else {
        deactivate_mutants();
    }
}

function activate_mutant(mutid) {
    if (!g_show_mutant)
        return;

    mut = document.getElementById(mutid);
    if (mut) {
        clss = document.getElementsByClassName("mutid" + mutid);
        if (clss) {
            for(var i=0; i<clss.length; i++) {
                clss[i].style.display = 'none';
            }
        }
        mut.style.display = 'inline';
    }
}

function deactivate_mutants() {
    var orgs = document.querySelectorAll(".original");
    var muts = document.querySelectorAll(".mutant");

    for (var i=0; i<orgs.length; i++) {
        orgs[i].style.display = "inline";
    }

    for (i=0; i<muts.length; i++) {
        muts[i].style.display = "none";
    }
}

function highlight_mutant(mutid) {
    mut = document.getElementById(mutid);
    if(mut) {
        deactivate_mutants();
        activate_mutant(mutid);

        scroll_to(mutid);
        for(var i=0; i<g_mutids.length; i++) {
            if (g_mutids[i] == mutid) {
                document.getElementById("current_mutant_status").innerText = g_muts_st[i];
                break;
            }
        }
    }
}

function fly(evt, html) {
    var el = document.getElementById("mousehover");
    if(evt.type == "mouseenter") {
        el.style.display = "inline";
    } else {
        el.style.display = "none";
    }

    el.innerHTML = html;
    el.style.left = (evt.pageX + 30) + 'px';
    el.style.top = (evt.pageY + 30) + 'px';
}

function scroll_to(anchor) {
    location.hash = "#" + anchor;
    var newpos = document.getElementById(anchor).offsetTop - window.innerHeight/2;
    if (newpos > 0) {
        window.scrollTo(0, newpos);
    }
}
`;
