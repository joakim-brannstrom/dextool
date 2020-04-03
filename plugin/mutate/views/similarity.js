/**
 * Javascript for the subpage "test_case_similarity"
 *
 */

 /**
  * Initializes the click events.
  */
var g_lastCol = -1;

function init() {

    theads = document.getElementsByClassName('tg-g59y');
    for (var i = 0; i < theads.length; i++) {
        theads[i].addEventListener('click', function(e) {table_onclick(e);});
        theads[i].addEventListener('mouseenter', function(e) {header_enter(e)});
        theads[i].addEventListener('mouseleave', function(e) {header_leave(e)});
    }
    var headers = document.getElementsByClassName('tbl_header');
    for (var i = 0; i < headers.length; i++) {
        headers[i].addEventListener('click', function(e) {header_onclick(e)});
        headers[i].addEventListener('mouseenter', function(e) {header_enter(e)});
        headers[i].addEventListener('mouseleave', function(e) {header_leave(e)});
    }
    var button = document.getElementById("expand_all");
    button.addEventListener("click", function(e) {expand_tables(e)});
    var button = document.getElementById("collapse_all");
    button.addEventListener("click", function(e) {collapse_tables(e)});
}
function expand_tables(e) {
    var tables = document.getElementsByClassName("tbl_container");
    for (var i=0; i<tables.length; i++) {
        tables[i].style.display = "inline";
        var tbl_container = tables[i].closest('.comp_container');
        arrow = tbl_container.getElementsByClassName("tbl_header")[0].getElementsByTagName("i")[0];
        arrow.classList.remove("right");
        arrow.classList.add("down");
    }
}
function collapse_tables(e) {
    var tables = document.getElementsByClassName("tbl_container");

    for (var i=0; i<tables.length; i++) {
        tables[i].style.display = "none";
        var tbl_container = tables[i].closest('.comp_container');
        arrow = tbl_container.getElementsByClassName("tbl_header")[0].getElementsByTagName("i")[0];
        arrow.classList.remove("down");
        arrow.classList.add("right");
    }
}
function header_leave(e) {
    e.target.style.textDecoration = 'none';
}
function header_enter(e) {
    e.target.style.textDecoration = 'underline';
}
/**
 *
 * @param {event} e click event
 */
function header_onclick(e) {
    var tbl_container = e.target.closest('.comp_container')
        .getElementsByClassName('tbl_container')[0];
    if (tbl_container.style.display === 'inline') {
        tbl_container.style.display = 'none';
        var arrow = e.target.getElementsByTagName("i")[0];
        arrow.classList.remove("down");
        arrow.classList.add("right")
    }
    else {
        tbl_container.style.display = 'inline';
        var arrow = e.target.getElementsByTagName("i")[0];
        arrow.classList.remove("right");
        arrow.classList.add("down");
    }
}
function table_onclick(e) {
    var col = e.target.id.split('-',2)[1];
    var tbody = e.target.closest('table').tBodies[0];
    var sorted = Array.prototype.slice.call(tbody.children);
    var tbl_container = e.target.closest(".tbl_container");
    var arrows = tbl_container.getElementsByTagName("i");
    for (var i=0; i<arrows.length; i++) {
        arrows[i].classList.remove("up");
        arrows[i].classList.remove("down");
        arrows[i].classList.add("right");
    }
    if (col === g_lastCol) {
        sorted.sort( function(a,b) {
            return a.children[col].innerText > b.children[col].innerText;
        });
        var arrow = e.target.getElementsByTagName("i")[0];
        arrow.classList.remove("down");
        arrow.classList.add("up");
        g_lastCol = -1;
    } else {
        sorted.sort( function(a,b) {
            return a.children[col].innerText < b.children[col].innerText;
        });
        var arrow = e.target.getElementsByTagName("i")[0];
        arrow.classList.remove("right");
        arrow.classList.add("down");
        g_lastCol = col;
    }
    while (tbody.lastChild) {
        tbody.removeChild(tbody.lastChild);
    }
    for(var i = 0; i<sorted.length; i++) {
        tbody.insertRow(i).innerHTML = sorted[i].innerHTML;
    }
}
