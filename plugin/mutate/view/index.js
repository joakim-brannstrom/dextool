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
var g_loc_mutids = {};

var key_traverse_locs_up = 'ArrowUp';
var key_traverse_locs_down = 'ArrowDown';
var key_traverse_muts_up = 'ArrowLeft';
var key_traverse_muts_down = 'ArrowRight';
var key_toggle_show_mutant = 'Numpad0';

function init() {

    var current_mutant_selector = document.getElementById('current_mutant');

    current_mutant_selector.addEventListener('change', 
        function(e) { current_mutant_onchange(e); });
    window.addEventListener('resize', 
        on_window_resize);
    window.addEventListener('keydown', 
        function(e) { on_keyboard_input(e); });

    init_legend();
    on_window_resize();

    // Construct the text displayed in the select field for all mutants
    for(var i=0; i<g_mutids.length; i++) {
        var txt = "";
        if (g_mut_st_map[g_muts_st[i]] == "alive")
            txt += "+";
        txt += "'"+g_muts_muts[i]+"'";
        g_mut_option_text[g_mutids[i]] = txt;
    }
    

    var locs = document.getElementsByClassName('loc');

    for (var i=0; i<locs.length; i++){
        locs[i].addEventListener('wheel', 
            function(e) { on_loc_wheel(e); });
        locs[i].addEventListener('click', 
            function(e) { on_loc_click(e); });
        
        // Get all mutant ids in the loc.
        muts = locs[i].getElementsByClassName('mutant');
        g_loc_mutids[locs[i].id] = [];
        for (var j=0; j<muts.length; j++) {
            g_loc_mutids[locs[i].id].push(muts[j].id);
        }
    }
    
    select_loc(locs[0].id);

    g_show_mutant = true;
    var mutid = -1;
    var mutid = window.location.hash.substring(1);
    if (mutid) {
        set_active_mutant(mutid);
        highlight_mutant(mutid);
        select_loc(get_closest_loc(document.getElementById(mutid)).id, true);
    }
}

function toggle_legend() {
    var legend = document.getElementById("legend_box");
    if (legend.style.display === "none")
        legend.style.display = "inline";
    else
        legend.style.display = "none";
}

function on_keyboard_input(e) {
    switch (e.code) {
        case key_traverse_locs_down:
            e.preventDefault();
            traverse_locs(1);
            break;
        case key_traverse_locs_up:
            e.preventDefault();
            traverse_locs(-1);
            break;
        case key_traverse_muts_down:
            traverse_mutants(1);
            break;
        case key_traverse_muts_up:
            traverse_mutants(-1);
            break;
        case key_toggle_show_mutant:
            document.getElementById("show_mutant").checked = !document.getElementById("show_mutant").checked
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

function on_loc_click(e) {
    
    var loc = get_closest_loc(e.target);
    
    if (loc) {
        select_loc(loc.id);
    } else {
        select_loc(g_active_locid);
    }
    return;
}

function select_loc(loc_id, pure) {
    locs = document.getElementsByClassName('loc');
    if(g_active_locid)
        document.getElementById(g_active_locid).style.backgroundColor = LOC_BACKGROUND_COLOR;
    
    loc = document.getElementById(loc_id);
    g_active_locid = loc.id;
    loc.style.backgroundColor = LOC_HIGHLIGHT_COLOR;
    if(!pure) {
        set_active_mutant(-1);
        deactivate_mutants();
        clear_mutation_options();
    }
    set_mutation_options(g_active_locid);
}

function set_mutation_options(loc_id) {
    var mutids;
    mutids = g_loc_mutids[loc_id];
    current_mutant_selector = document.getElementById('current_mutant');
        
    current_mutant_selector.selectedIndex = 0;
    for (var i = 0; i < mutids.length; i++) {
        var s = document.createElement('OPTION');
        s.value = mutids[i];
        s.text = g_mut_option_text[mutids[i]];
        current_mutant_selector.add(s);
        if (g_active_mutid === s.value)
            current_mutant_selector.selectedIndex = i+1;
    }
}

/**
 * Changes the active mutant on a given line
 * @param {*} direction positive for next, negative for previous
 */
function traverse_mutants(direction) {
    current_mutant_selector = document.getElementById('current_mutant');
    selected = current_mutant_selector.selectedIndex;

    if (direction>0) {
        if (selected+1 < current_mutant_selector.options.length)
            current_mutant_selector.selectedIndex += 1;
        else if (MUT_TRAVERSE_LOOP)
            current_mutant_selector.selectedIndex = 0;
        
    } else if (direction < 0) {
        if (selected-1 >= 0)
            current_mutant_selector.selectedIndex-=1;
        else if (MUT_TRAVERSE_LOOP)
            current_mutant_selector.selectedIndex = current_mutant_selector.options.length -1;
    }
    var mutid = current_mutant_selector.value;

    set_active_mutant(mutid);
    highlight_mutant(mutid);    
}
/**
 * Changes the active line 
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
            } else if (direction < 0) {
                if (i-1 >= 0)
                    select_loc(locs[i-1].id);
                else if (LOC_TRAVERSE_LOOP)
                    select_loc(locs[locs.length-1].id);            
            }
            break;
        }
    }
    if (old_active_locid !== g_active_locid && LOC_SCROLL_TO_ON_TRAVERSE) {
        scroll_to(g_active_locid, true);
    }
    return;
}
/**
 * Gets the closest loc of an element
 * @param {*} target The target element
 */
function get_closest_loc(target) {
    if (!target)
        return document.getElementById(g_active_locid);
    if (target.className === "loc")
        return target;
    else
        return target.closest(".loc");
<<<<<<< HEAD
<<<<<<< HEAD
}
=======
    }
>>>>>>> 68992aa2... cleanup
=======
}
>>>>>>> f3e94783... added ability to sort the table on index.html

function on_window_resize() {
    var info_box = document.getElementById('info');
    var top = info_box.offsetTop - info_box.style.marginTop;
    var left = window.innerWidth - info_box.clientWidth - 30;
    info_box.style.left = left + "px";
    info_box.style.top = top + "px";
}

function current_mutant_onchange(e) {
    var current_mutant_selector = document.getElementById('current_mutant'); 
    var id = current_mutant_selector.value;

    current_mutant_selector.focus();
    current_mutant_selector.blur();
    
    if (id == -1) {
        location.hash = "#";
        set_active_mutant(id);
        deactivate_mutants();
        return;
    }
    
    set_active_mutant(id);
    highlight_mutant(id);
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

    for (var i=0; i<g_mutids.length; i++) {
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
        highlight_mutant(g_active_mutid);
    } else {
        deactivate_mutants();
    }
}

function activate_mutant(mutid) {
    if (!g_show_mutant) {
        return;
    }

    mut = document.getElementById(mutid);
    if (mut) {
        clss = document.getElementsByClassName("mutid" + mutid);
        if (clss) {
            for (var i=0; i<clss.length; i++) {
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

function highlight_mutant(mutid) {

    deactivate_mutants();
    mut = document.getElementById(mutid);
    if (!mut)
        return;
    if (mut.classList.contains("mutant")) {
        activate_mutant(mutid);

        for (var i=0; i<g_mutids.length; i++) {
            if (g_mutids[i] == mutid) {
                document.getElementById("current_mutant_status").innerText = g_mut_st_map[g_muts_st[i]];
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
    if (evt.type == "mouseenter") {
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
    location.hash = "#" + anchor; //Removing this allows for using the browser back button.
    if (center) {
        var newpos = document.getElementById(anchor).offsetTop - window.innerHeight/2;
        if (newpos > 0) {
            window.scrollTo(0, newpos);
        }
        else {
            window.scrollTo(0, 0);
        }
    } else {
        window.scrollTo(0, curr_pos);
    }
}

// Move most of this to html at some point
function init_legend() {
    var table = document.createElement('table');
    add_table_row_with_text(table, "Next loc: "+key_traverse_locs_down);
    add_table_row_with_text(table, "Prev loc: "+key_traverse_locs_up);
    add_table_row_with_text(table, "Next mut: "+key_traverse_muts_down);
    add_table_row_with_text(table, "Prev mut: "+key_traverse_muts_up);
    add_table_row_with_text(table, "Toggle show: "+key_toggle_show_mutant);

    table.style.display = "none";
    table.id = "legend_box";
    document.getElementById("info").appendChild(table);
}
function add_table_row_with_text(table, text) {
    var row = document.createElement('tr');
    var cell = document.createElement('td');
    var text_span = document.createElement('span');
    text_span.textContent=text;
    cell.appendChild(text_span);
    row.appendChild(cell);
    table.appendChild(row);
}
