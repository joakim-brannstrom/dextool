/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/

var g_show_mutant = true;
var g_active_mutid = 0;
var g_mut_option_text = {};
var g_selected_line = null;
function init() {

    var current_mutant_selector = document.getElementById('current_mutant');
    current_mutant_selector.addEventListener("change", current_mutant_onchange );
    window.addEventListener("resize", on_window_resize);

    on_window_resize();
    var mutid = window.location.hash.substring(1);
    if(mutid) {
        set_active_mutant(mutid);
        highlight_mutant(mutid);
    }
    for(var i=0; i<g_mutids.length; i++) {
        var txt = "";
        if (g_muts_st[i] == "alive")
            txt += "+";
        txt += "'"+g_muts_muts[i]+"'";//+= g_mutids[i] + ":'" + g_muts_orgs[i] + "' to '" + g_muts_muts[i] + "'";
        g_mut_option_text[g_mutids[i]] = txt;
    }
    set_mutation_options(g_mutids);
    locs = document.getElementsByClassName("loc");
    for(var i=0; i<locs.length; i++){
        locs[i].addEventListener("mouseenter", function(e){on_loc_enter(e);});
        locs[i].addEventListener("mouseleave", function(e){on_loc_leave(e);});
        locs[i].addEventListener("wheel", function(e){on_loc_wheel(e);});
        locs[i].addEventListener("click", function(e){on_loc_dblclick(e);},true);
    }
}
function on_loc_wheel(e) {
    if(e.target.id !== g_selected_line)
        return;
    deactivate_mutants();
    current_mutant_selector = document.getElementById('current_mutant');
    selected = current_mutant_selector.selectedIndex;
    if(e.deltaY>0 && selected + 1 < current_mutant_selector.options.length) {
        current_mutant_selector.selectedIndex+=1;
        
    }else if(e.deltaY<0 && selected-1>=0) {
        current_mutant_selector.selectedIndex-=1;
    }

    var id = current_mutant_selector.value;
    set_active_mutant(id);
    highlight_mutant(id);
    scroll_to(id, false);
}
function on_loc_enter(e) {
    //e.target.style.backgroundColor = '#cecece';
    return;
}

function on_loc_leave(e) {
    //e.target.style.backgroundColor = '#ffffff';
    return;
}

function on_loc_dblclick(e) {
    locs = document.getElementsByClassName("loc");
    for(var i=0; i<locs.length;i++) {
        locs[i].style.backgroundColor = '#ffffff';
    }
    if(e.target.className === "loc") {
        g_selected_line = e.target.id;
        e.target.style.backgroundColor = '#cecece';
        current_mutant_selector = document.getElementById('current_mutant');
        mutants = e.target.getElementsByClassName("mutant");
        clear_mutation_options();
        if(!mutants.length)
            return;

        var mut_ids = [mutants.length];
        for (var i = 0; i < mutants.length; i++) {
            mut_ids[i] = mutants[i].id;
        }
        
        set_mutation_options(mut_ids);
    }
    return;
}

function clear_mutation_options() {
    current_mutant_selector = document.getElementById('current_mutant');
    while (current_mutant_selector.options.length!=1) {
        current_mutant_selector.options[1]=null;
    }
}

function set_mutation_options(mut_ids) {
    deactivate_mutants();
    var mutid;// = window.location.hash.substring(1);
    current_mutant_selector = document.getElementById('current_mutant');
    current_mutant_selector.selectedIndex = 0;
    for (var i = 0; i < mut_ids.length; i++) {
        
        var s = document.createElement('OPTION');
        s.value = mut_ids[i];
        s.text = g_mut_option_text[mut_ids[i]];
        current_mutant_selector.add(s);
        if (mutid == mut_ids[i])
            current_mutant_selector.selectedIndex = i+1;
    }
}

function on_window_resize() {
    var info_box = document.getElementById('info');
    var top = info_box.offsetTop - info_box.style.marginTop;
    var left = window.innerWidth - info_box.clientWidth - 30;
    info_box.style.left = left + "px";
    info_box.style.top = top + "px";
}

function current_mutant_onchange() {
    var current_mutant_selector = document.getElementById("current_mutant"); 
    if (current_mutant_selector.selectedIndex == 0) {
        location.hash = "#";
        set_active_mutant(-1);
        deactivate_mutants();
        return;
    }
    var id = current_mutant_selector.value;
    set_active_mutant(id);
    highlight_mutant(id);
    scroll_to(id, true);
    current_mutant_selector.focus();
}

function ui_set_mut(id) {
    set_active_mutant(id);
    highlight_mutant(id);
    scroll_to(id, false);

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

        for(var i=0; i<g_mutids.length; i++) {
            if (g_mutids[i] == mutid) {
                document.getElementById("current_mutant_status").innerText = g_muts_st[i];
                document.getElementById("current_mutant_metadata").innerText = g_muts_meta[i];
                document.getElementById("current_mutant_id").innerText = mutid;
                document.getElementById("current_mutant_original").innerText = g_muts_orgs[i];
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

function scroll_to(anchor, center) {
    var curr_pos = window.pageYOffset;
    location.hash = "#" + anchor;
    if (center) {
        var newpos = document.getElementById(anchor).offsetTop - window.innerHeight/2;
        if (newpos > 0) {
            window.scrollTo(0, newpos);
        }
    } else {
        window.scrollTo(0, curr_pos);
    }
}

