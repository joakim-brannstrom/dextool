/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/

const LOC_BACKGROUND_COLOR = '#ffffff';
const LOC_HIGHLIGHT_COLOR = '#cecece';
const LOC_TRAVERSE_LOOP = true;
const MUT_TRAVERSE_LOOP = false;
const LOC_SCROLL_TO_ON_TRAVERSE = true;

var g_show_mutant = true;
var g_active_mutid = 0;
var g_mut_option_text = {};
var g_active_locid = null;
var g_legend_html = null;

var key_traverse_locs_up = 'ShiftLeft';
var key_traverse_locs_down = 'Tab';
var key_traverse_muts_up = 'ArrowLeft';
var key_traverse_muts_down = 'ArrowRight';
var key_toggle_show_mutant = 'ControlLeft';

function init() {

    var current_mutant_selector = document.getElementById('current_mutant');
    current_mutant_selector.addEventListener('change', current_mutant_onchange);
    window.addEventListener('resize', on_window_resize);
    document.addEventListener('keydown', function(e) { on_keyboard_input(e); });
    on_window_resize();
    init_legend();
    document.getElementById("legend").addEventListener('click', alert(g_legend_html.html()));
    for(var i=0; i<g_mutids.length; i++) {
        var txt = "";
        if (g_muts_st[i] == "alive")
            txt += "+";
        txt += "'"+g_muts_muts[i]+"'";
        g_mut_option_text[g_mutids[i]] = txt;
    }

    var locs = document.getElementsByClassName('loc');
    for(var i=0; i<locs.length; i++){
        locs[i].addEventListener('mouseenter', function(e) { on_loc_enter(e); });
        locs[i].addEventListener('mouseleave', function(e) { on_loc_leave(e); });
        locs[i].addEventListener('wheel', function(e) { on_loc_wheel(e); });
        locs[i].addEventListener('click', function(e) { on_loc_dblclick(e); }, true);
    }

    select_loc(locs[0].id);
    g_show_mutant = true;
    var mutid = window.location.hash.substring(1);
    if(mutid) {
        set_active_mutant(mutid);
        highlight_mutant(mutid);
    }
}
function on_keyboard_input(e) {
    switch (e.code) {
        case key_traverse_locs_down:
            traverse_locs(1);
            break;
        case key_traverse_locs_up:
            traverse_locs(-1);
            break;
        case key_traverse_muts_down:
            traverse_mutants(1);
            break;
        case key_traverse_muts_up:
            traverse_mutants(-1);
            break;
        case key_toggle_show_mutant:
            g_show_mutant = document.getElementById("show_mutant").checked = !g_show_mutant;
            click_show_mutant();
    }
    return;
}
function on_loc_wheel(e) {
    var loc = get_closest_loc(e.target);

    if(loc.id === g_active_locid)
        traverse_mutants(e.deltaY);
    
    return;
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
    
    var loc = get_closest_loc(e.target);
    
    if (loc) {
        select_loc(loc.id);
    } else {
        select_loc(g_active_locid);
    }
    return;
}

function select_loc(loc_id) {
    locs = document.getElementsByClassName('loc');
    for (var i=0; i<locs.length;i++) {
        locs[i].style.backgroundColor = LOC_BACKGROUND_COLOR;
    }
    clear_mutation_options();
    deactivate_mutants();
    loc = document.getElementById(loc_id);
    g_active_locid = loc.id;
    loc.style.backgroundColor = LOC_HIGHLIGHT_COLOR;
    current_mutant_selector = document.getElementById('current_mutant');
    mutants = loc.getElementsByClassName('mutant');
    
    if (!mutants.length)
        return;

    var mut_ids = [mutants.length];
    for (var i = 0; i < mutants.length; i++) {
        mut_ids[i] = mutants[i].id;
    }
    
    set_mutation_options(mut_ids);
}

function set_mutation_options(mut_ids) {
    deactivate_mutants();
    var mutid;
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

/**
 * Changes the active mutant on a given line
 * @param {*} direction positive for next, negative for previous
 */line
funline
    deactivate_mutants();
    current_mutant_selector = document.getElementById('current_mutant');
    selected = current_mutant_selector.selectedIndex;
    if (direction>0) {
        if (selected+1 < current_mutant_selector.options.length)
            current_mutant_selector.selectedIndex += 1;
        else if (MUT_TRAVERSE_LOOP)
            current_mutant_selector.selectedIndex = 0;
        
    }else if (direction < 0) {
        if (selected-1 >= 0)
            current_mutant_selector.selectedIndex-=1;
        else if (MUT_TRAVERSE_LOOP)
            current_mutant_selector.selectedIndex = current_mutant_selector.options.length -1;
    }

    var id = current_mutant_selector.value;
    set_active_mutant(id);
    highlight_mutant(id);
    scroll_to(id, false);
}
/**
 * Changes the active line on a given line
 * @param {*} direction positive for next, negative for previous
 */
function traverse_locs(direction) {
    locs = document.getElementsByClassName('loc');
    var old_active_locid = g_active_locid;
    for (var i = 0; i < locs.length; i++) {
        if (locs[i].id === g_active_locid) {
            if (direction > 0) {
                if (i+1 < locs.length) 
                    select_loc(locs[i+1].id);
                else if (LOC_TRAVERSE_LOOP)
                    select_loc(locs[0].id);
                break;
            } else if (direction < 0) {
                if (i-1 >= 0)
                    select_loc(locs[i-1].id);
                else if (LOC_TRAVERSE_LOOP) {
                    select_loc(locs[locs.length-1].id);
                }
                break;                
            }
            else {
                break;
            }
        }
    }
    if (old_active_locid !== g_active_locid && LOC_SCROLL_TO_ON_TRAVERSE)
        scroll_to(g_active_locid);
    return;
}
/**
 * Gets the closest loc of an element
 * @param {*} target The target element
 */
function get_closest_loc(target) {
    if (target.className === "loc"){
        return target;
    }
    else {
        return target.closest(".loc");
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
    var current_mutant_selector = document.getElementById('current_mutant'); 
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

function clear_mutation_options() {
    current_mutant_selector = document.getElementById('current_mutant');
    while (current_mutant_selector.options.length!=1) {
        current_mutant_selector.options[1]=null;
    }
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
    clear_current_mutant_info();
    var orgs = document.querySelectorAll(".original");
    var muts = document.querySelectorAll(".mutant");
    for (var i=0; i<orgs.length; i++) {
        orgs[i].style.display = "inline";
    }

    for (i=0; i<muts.length; i++) {
        muts[i].style.display = "none";
    }
}

function highlight_mutant(mutid) {key_traverse_mutant_up
    key_traverse_mutant_up
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

function clear_current_mutant_info(){
    document.getElementById("current_mutant_status").innerText = "";
    document.getElementById("current_mutant_metadata").innerText = "";
    document.getElementById("current_mutant_id").innerText = "";
    document.getElementById("current_mutant_original").innerText = "";
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

// Move most of this to html at some point
function init_legend() {
    var container = document.createElement('fieldset');
    var table = container.appendChild('table');
    add_table_row_with_text("Next loc: "+key_traverse_locs_down);
    add_table_row_with_text("Prev loc: "+key_traverse_locs_up);
    add_table_row_with_text("Next mut: "+key_traverse_muts_down);
    add_table_row_with_text("Prev mut: "+key_traverse_muts_up);
    
    g_legend_html = container;
    console.log(g_legend_html);
}
function add_table_row_with_text(table, text) {
    var row = table.appendChild('tr');
    var cell = row.appendChild('td');
    cell.appendChild('span').text(text);
}
