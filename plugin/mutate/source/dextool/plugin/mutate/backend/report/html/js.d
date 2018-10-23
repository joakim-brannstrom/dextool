/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.js;

immutable js_file = `function init() {
    var mutid = window.location.hash.substring(1);
    if(mutid) {
        highlight_mutant(mutid);
    }

    document.getElementById('current_mutant').addEventListener("change",
    function() {
        var id = document.getElementById('current_mutant').value;
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

function highlight_mutant(mutid) {
    var orgs = document.querySelectorAll(".original");
    var muts = document.querySelectorAll(".mutant");

    for (var i=0; i<orgs.length; i++) {
        orgs[i].style.display = "inline";
    }

    for (i=0; i<muts.length; i++) {
        muts[i].style.display = "none";
    }

    mut = document.getElementById(mutid);
    if(mut) {
        clss = document.getElementsByClassName("mutid" + mutid);
        if (clss) {
            for(var i=0; i<clss.length; i++) {
                clss[i].style.display = 'none';
            }
        }
        mut.style.display = 'inline';
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
    var top = document.getElementById(anchor).offsetTop;
    var center = window.innerHeight/2;
    window.scrollTo(0, top - center);
}
`;
