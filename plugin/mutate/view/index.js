/**
 * Javascript for the HTML report page "index.html"
 */
var g_lastCol = -1;

function init() { 
    theads = document.getElementsByClassName('tg-g59y');
    for (var i = 0; i < theads.length; i++) {
        theads[i].addEventListener('click', function(e) {table_onclick(e);});
    }
}

function table_onclick(e) {
    var col = e.target.id.split('-',2)[1];
    var tbody = e.target.closest('table').tBodies[0];
    var sorted = Array.prototype.slice.call(tbody.children);
    
    if (col === g_lastCol) {
        sorted.sort( function(a,b) {
            return a.children[col].innerText > b.children[col].innerText;
        });
        g_lastCol = -1;
    } else {
        sorted.sort( function(a,b) {
            return a.children[col].innerText < b.children[col].innerText;
        });
        g_lastCol = col;
    }
    while (tbody.lastChild) {
        tbody.removeChild(tbody.lastChild);
    }
    for(var i = 0; i<sorted.length; i++) {
        tbody.insertRow(i).innerHTML = sorted[i].innerHTML;
    }
}