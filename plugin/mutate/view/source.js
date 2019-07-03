/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/

const LOC_TRAVERSE_LOOP = true;
const MUT_TRAVERSE_LOOP = false;
const LOC_SCROLL_TO_ON_TRAVERSE = true;
const NUM_TESTCASES = 3; //Number of testcases displayed in the info line

var g_show_mutant = true;
var g_active_mutid = 0;
var g_mut_option_text = {};
var g_active_locid = null;
var g_loc_mutids = {};
var g_filter_kinds = [];
var g_filter_status = [];

var key_traverse_locs_up = 'ArrowUp';
var key_traverse_locs_down = 'ArrowDown';
var key_traverse_muts_up = 'ArrowLeft';
var key_traverse_muts_down = 'ArrowRight';
var key_toggle_show_mutant = 'Numpad0';


/**
 * Initializes event listeners, data and intial state
 */
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
        if (g_mut_st_map[g_muts_st[g_mutids[i]]] == "alive")
            txt += "+";
        txt += "'"+g_muts_muts[i]+"'";
        g_mut_option_text[g_mutids[i]] = txt;
    }
    var locs_table = document.getElementById("locs");
    locs_table.style.width = "60%";

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
    //Select loc or mutant by hash
    var mutid = -1;
    var hash = window.location.hash.substring(1);
    if (document.getElementById(hash)) {
        if (document.getElementById(hash).classList.contains('mutant')) {
            mutid = hash;
            set_active_mutant(mutid);
            highlight_mutant(mutid);
            select_loc(get_closest_loc(document.getElementById(mutid)).id, true);
        } else if (document.getElementById(hash).classList.contains('loc')) {
            select_loc(hash, true);
        }
    }
    click_show_legend();
    click_show_mutant();
    init_filter_kind();
    init_filter_status();
    document.body.focus();
}
/**
 * Toggles whether to show the legend or not
 */
function click_show_legend() {
    var show_legend = document.getElementById("show_legend").checked;
    var legend = document.getElementById("legend_box");
    if (show_legend) {
        legend.style.display = "inline";
    } else {
        legend.style.display = "none";
    }
}
/**
 * Manages all keyboard bindings
 * @param {event} e the captured keyboard event
 */
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
/**
 * Traverses mutants if a scroll event is captured in the selected loc
 * @param {event} e the captured scrool event
 */
function on_loc_wheel(e) {
    var loc = get_closest_loc(e.target);
    if(loc.id === g_active_locid)
        traverse_mutants(e.deltaY);
    return;
}
/**
 * Selects a loc when any element within it captures a click event.
 * @param {event} e the captured click event 
 */
function on_loc_click(e) { 
    if (!e.target.classList.contains("loc") && e.target.onclick != null)
        return;
    var loc = get_closest_loc(e.target);
    if (loc) {
        select_loc(loc.id);
    } else {
        select_loc(g_active_locid);
    }
    return;
}
/**
 * Selects the loc with the given id.
 * @param {id} loc_id the id of the loc to select
 * @param {boolean} pure false if active mutant and mutation options are to be cleared.
 */
function select_loc(loc_id, pure) {
    locs = document.getElementsByClassName('loc');
    if(g_active_locid){
        document.getElementById(g_active_locid).classList.toggle("loc_selected");
        remove_info_line();
    }
    loc = document.getElementById(loc_id);
    g_active_locid = loc.id;
    loc.classList.toggle("loc_selected");
    if(!pure) {
        set_active_mutant(-1);
        deactivate_mutants();
        clear_mutation_options();
    }
    show_info_line();
    set_mutation_options(g_active_locid);
}
function show_info_line() {
    if (!document.getElementById(g_active_locid).getElementsByClassName("mutant").length)
        return; 
    var loc_table = document.getElementById("locs");
    var line = g_active_locid.split('-',2)[1];
    var info_row = loc_table.insertRow(line);
   
    info_row.innerHTML = `
    <td id='info_line'>
    <table id='info_table'>
        <tr id="fly"></tr>

    </table>
    </td>
    `;
    var info_table =document.getElementById("info_table");
    for (var i = 0; i < NUM_TESTCASES; i++) {
        var id = "tc" + parseInt(i+1);
        row = info_table.insertRow(i+1);
        row.id = id;
        row.innerHTML = make_td("<span>->:</span>");
    }
    set_info_line(g_active_mutid);
}
function remove_info_line() {
    if (!document.getElementById("info_line"))
        return; 
    var line = g_active_locid.split('-',2)[1];
    document.getElementById("locs").deleteRow(line);
}
function set_info_line(mutid) {
    if (!document.getElementById(g_active_locid).getElementsByClassName("mutant").length)
        return; 
    for (var i = 0; i < NUM_TESTCASES; i++) {
        var id = "tc" + parseInt(i+1);
        var row = document.getElementById(id)
        if (row)
            row.innerHTML = make_td("<span>->:</span>");
    }
    document.getElementById("fly").innerHTML = make_td("<span>->:</span>") + make_td(g_mut_fly_html[mutid]);
    if (!g_muts_testcases[mutid])
        return;
    
    for (var i = 0; i < NUM_TESTCASES; i++) {
        
        var test_case = g_muts_testcases[mutid][i];
        if (test_case) {
            var id = "tc" + parseInt(i+1);
            row = document.getElementById(id);
            row.innerHTML = make_td("<span>->:</span>")  + make_td(test_case + ": "+g_testcases_kills[test_case]);
        }
    }
}
function make_td(html, id) {
    if(!id)
        return "<td>"+html+"</td>";
    return "<td id='"+id+"'>"+html+"</td>";
}
/**
 * Adds the mutants on the loc for the given id 
 * @param {id} loc_id id of the loc whose mutants to add
 */
function set_mutation_options(loc_id) {
    var mutids;
    var mutids = g_loc_mutids[loc_id];
    var current_mutant_selector = document.getElementById('current_mutant');
        
    current_mutant_selector.selectedIndex = 0;
    for (var i = 0; i < mutids.length; i++) {
        if (!g_filter_kinds.includes(g_muts_kind[mutids[i]]) &&
            !g_filter_status.includes(g_muts_st[mutids[i]])) 
        {
            var s = document.createElement('OPTION');
            s.value = mutids[i];
            s.text = g_mut_option_text[mutids[i]];
            current_mutant_selector.add(s);
            if (g_active_mutid === s.value)
                current_mutant_selector.selectedIndex = i+1;
        }
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
    if (mutid != -1)
        scroll_to(mutid);
    else
        scroll_to(g_active_locid);
    //if (current_mutant_selector.children.length>1)
    set_info_line(mutid); 
    //else 
        //remove_info_line();
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
}
/**
 * Moves the info box when the client window is resized
 */
function on_window_resize() {
    var info_box = document.getElementById('info');
    var top = info_box.offsetTop - info_box.style.marginTop;
    var left = window.innerWidth - info_box.clientWidth - 30;
    info_box.style.left = left + "px";
    info_box.style.top = top + "px";
}
/**
 * Updates the selected mutant when using the selector
 * @param {event} e captured change event 
 */
function current_mutant_onchange(e) {
    var current_mutant_selector = document.getElementById('current_mutant'); 
    var id = current_mutant_selector.value;

    current_mutant_selector.focus();
    current_mutant_selector.blur();
    document.body.focus();
    if (id == -1) {
        location.hash = "#";
        set_active_mutant(id);
        deactivate_mutants();
        return;
    }
    
    set_active_mutant(id);
    highlight_mutant(id);
}
/**
 * Removes all options (except the first) from the selector.
 */
function clear_mutation_options() {
    current_mutant_selector = document.getElementById('current_mutant');
    while (current_mutant_selector.options.length!=1) {
        current_mutant_selector.options[1]=null;
    }
}
/**
 * Updates the ui to display the mutant with the given id as selected.
 */
function ui_set_mut(id) {
    loc_id = get_closest_loc(document.getElementById(id)).id
    if (loc_id != g_active_locid){
        select_loc(loc_id);
        return;
    }
    mutids = g_loc_mutids[loc_id];
    set_active_mutant(id);
    highlight_mutant(id);
    scroll_to(id, false);
    set_info_line(id);
    var current_mutant_selector = document.getElementById('current_mutant');
    for (var i=0; i<mutids.length; i++) {
        if (id == mutids[i]) {
            current_mutant_selector.selectedIndex = i+1;
            break;
        }
    }
}
/**
 * Sets the active mutant id as the given id.
 * @param {id} mutid id of mutant to set as activate
 */
function set_active_mutant(mutid) {
    if (mutid) {
        g_active_mutid = mutid;
    }
}
/**
 * Toggles whether to show mutants or not.
 */
function click_show_mutant() {
    g_show_mutant = document.getElementById("show_mutant").checked;
    if (g_show_mutant) {
        highlight_mutant(g_active_mutid);
    } else {
        deactivate_mutants();
    }
}
/**
 * Activates the mutant of the given id.
 * @param {id} mutid id of the mutant to activate 
 */
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
/**
 * Deactivates all mutants
 */
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
/**
 * Highlights the mutant of the given id
 * @param {id} mutid id of the mutant to highlight
 */
function highlight_mutant(mutid) {
    deactivate_mutants();
    mut = document.getElementById(mutid);
    if (!mut)
        return;
    if (mut.classList.contains("mutant")) {
        activate_mutant(mutid);

        for (var i=0; i<g_mutids.length; i++) {
            if (g_mutids[i] == mutid) {
                document.getElementById("current_mutant_status").innerText = g_mut_st_map[g_muts_st[g_mutids[i]]];
                document.getElementById("current_mutant_metadata").innerText = g_muts_meta[i];
                document.getElementById("current_mutant_id").innerText = mutid;
                document.getElementById("current_mutant_original").innerText = g_muts_orgs[i];
                break;
            }
        }
    }
}
function click_filter_kind(kind) {
    var checkbox = document.getElementById(g_mut_kind_map[kind]);
    if(checkbox.checked) {
        for( var i = 0; i < g_filter_kinds.length; i++){
            if (g_filter_kinds[i] === kind) {
                
                g_filter_kinds.splice(i, 1); 
            }
         }
    }
    else {
        console.log("Add: "+kind);
        g_filter_kinds.push(kind);
    }
    clear_mutation_options();
    set_mutation_options(g_active_locid);
}
function click_filter_status(status) {
    var checkbox = document.getElementById(g_mut_st_map[status]);
    if(checkbox.checked) {
        console.log("Remove: "+status);
        for( var i = 0; i < g_filter_status.length; i++){
            console.log("filterI: "+g_filter_status[i]+ " kind: "+status); 
            if (g_filter_status[i] === status) {
                
                g_filter_status.splice(i, 1); 
            }
         }
    }
    else {
        console.log("Add: "+status);
        g_filter_status.push(status);
    }
    clear_mutation_options();
    set_mutation_options(g_active_locid);
}
/**
 * Clears the info box of mutant related text.
 */
function clear_current_mutant_info(){
    document.getElementById("current_mutant_status").innerText = "";
    document.getElementById("current_mutant_metadata").innerText = "";
    document.getElementById("current_mutant_id").innerText = "";
    document.getElementById("current_mutant_original").innerText = "";
}
/**
 * Displays info about all mutants in the same place as the mutant being hovered.
 * @param {event} evt the captured event
 * @param {innerHTML} html The inner html to be displayed.
 */
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
/**
 * Scrolls to the element of the given anchor
 * @param {id} anchor the id of the element to scroll to
 * @param {boolean} center whether to centre the page on the anchor
 */
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
   document.getElementById("legend1_action").innerHTML = "Next line: ";
   document.getElementById("legend2_action").innerHTML = "Prev line: ";
   document.getElementById("legend3_action").innerHTML = "Next mutant: ";
   document.getElementById("legend4_action").innerHTML = "Prev mutant: ";
   document.getElementById("legend5_action").innerHTML = "Toggle show: ";
   document.getElementById("legend1_key").innerHTML = key_traverse_locs_down;
   document.getElementById("legend2_key").innerHTML = key_traverse_locs_up;
   document.getElementById("legend3_key").innerHTML = key_traverse_muts_down;
   document.getElementById("legend4_key").innerHTML = key_traverse_muts_up;
   document.getElementById("legend5_key").innerHTML = key_toggle_show_mutant;
}
function init_filter_kind() {
    var table = document.getElementById("filter_kind");
    
    for (var i=0; i < g_mut_kind_map.length; i++) {
        var row = table.insertRow(i);
        row.innerHTML = `<td><input id="`+g_mut_kind_map[i]+ `" type="checkbox" onclick='click_filter_kind(`+i+`)' checked />
                        <span class="xx_label">`+g_mut_kind_map[i]+`</span></td>`;
    }
}
function init_filter_status() {
    var table = document.getElementById("filter_status");

    for (var i=0; i<g_mut_st_map.length; i++) {
        var row = table.insertRow(i);
        row.innerHTML = `<td><input id="`+g_mut_st_map[i]+ `" type="checkbox" onclick='click_filter_status(`+i+`)' checked />
        <span class="xx_label">`+g_mut_st_map[i]+`</span></td>`;
    }
    return;
}