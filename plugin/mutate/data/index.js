/**
 * Javascript for the HTML report page "index.html"
 */
var g_lastCol = -1;

function init() {
    theads = document.getElementsByClassName('table-col-sortable');
    for (var i = 0; i < theads.length; i++) {
        theads[i].addEventListener('click', function(e) {sortable_table_onclick(e);});
    }
    setDocTime();
}

function sortable_table_onclick(e) {
    var col = e.target.id.split('-',2)[1];
    if (!col) {
        return;
    }
    var tbody = e.target.closest('table').tBodies[0];
    var sorted = Array.prototype.slice.call(tbody.children);
    var tbl_container = e.target.closest(".table-sortable-div");
    var arrows = tbl_container.getElementsByTagName("i");
    var extractSortKey = function(str) {
        var num = parseFloat(str);
        if (isNaN(num)) {
            return str;
        }
        return num;
    }
    for (var i=0; i<arrows.length; i++) {
        arrows[i].classList.remove("up");
        arrows[i].classList.remove("down");
        arrows[i].classList.add("right");
    }
    if (col === g_lastCol) {
        sorted.sort( function(a,b) {
            return extractSortKey(a.children[col].innerText) > extractSortKey(b.children[col].innerText);
        });
        var arrow = e.target.getElementsByTagName("i")[0];
        arrow.classList.remove("down");
        arrow.classList.add("up");
        g_lastCol = -1;
    } else {
        sorted.sort( function(a,b) {
            return extractSortKey(a.children[col].innerText) < extractSortKey(b.children[col].innerText);
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

function filter_table_on_search(inputFieldId, tableId) {
    var input, filter, table, tr, td, i, txtValue;
    input = document.getElementById(inputFieldId);
    filter = input.value.toUpperCase();
    table = document.getElementById(tableId);
    tr = table.getElementsByTagName("tr");
    for (i = 0; i < tr.length; i++) {
        td = tr[i].getElementsByTagName("td")[0];
        if (td) {
            txtValue = td.textContent || td.innerText;
            if (txtValue.toUpperCase().indexOf(filter) > -1) {
                tr[i].style.display = "";
            } else {
                tr[i].style.display = "none";
            }
        }
    }
}

/** Toggle visibility for a tab and close others.
 */
function openTab(evt, open, tabGroup) {
    
  // Get all elements with class="tabcontent" and hide them
  var tabcontent = document.getElementsByClassName("tabcontent_" + tabGroup);
  for (var i = 0; i < tabcontent.length; i++) {
    tabcontent[i].style.display = "none";
  }

  var closeTab = false;
  // Get all elements with class="tablinks" and remove the class "active"
  var tablinks = document.getElementsByClassName("tablinks_" + tabGroup);
  for (var i = 0; i < tablinks.length; i++) {
    if (tablinks[i].className.includes("active") && tablinks[i].innerText.includes(open)) {
        closeTab = true;
    }
    tablinks[i].className = tablinks[i].className.replace(" active", "");
  }

  // Show the current tab, and add an "active" class to the button that opened the tab
  if (!closeTab) {
    document.getElementById(open).style.display = "block";
    evt.currentTarget.className += " active";
  }
}

function setDocTime() {
    var div = document.getElementById("reportGenerationDate");
    var modDate = convertDate(new Date(document.lastModified));
    div.innerText += " " + modDate;
}

function convertDate(date) {
    return date.getFullYear() + "/" +
    ("0" + (date.getMonth()+1)).slice(-2) + "/" +
    ("0" + date.getDate()).slice(-2) + " " +
    ("0" + date.getHours()).slice(-2) + ":" +
    ("0" + date.getMinutes()).slice(-2) + ":" +
    ("0" + date.getSeconds()).slice(-2);
}
