/**
 * Javascript for the HTML report page "index.html"
 */
var g_lastCol = -1;

function init() {
    let resizeTimeout;
    update_infobox_position();
    window.addEventListener("resize", () => {
        if (resizeTimeout) {
            clearTimeout(resizeTimeout)
        };
        resizeTimeout = setTimeout(function () {
            update_infobox_position();
        }, 100);
    });
    if (document.getElementById("csp_error") !== null)
        document.getElementById("csp_error").style.display = "none";
    theads = document.getElementsByClassName('table-col-sortable');
    for (var i = 0; i < theads.length; i++) {
        theads[i].addEventListener('click', function (e) { sortable_table_onclick(e); });
    }
    setDocTime();
}

function sortable_table_onclick(e) {
    var col = e.target.id.split('-', 2)[1];
    if (!col) {
        return;
    }
    var tbody = e.target.closest('table').tBodies[0];
    if (tbody == undefined)
        return;
    var sorted = Array.prototype.slice.call(tbody.children);
    var tbl_container = e.target.closest(".table-sortable-div");
    var arrows = tbl_container.getElementsByTagName("i");
    var extractSortKey = function(str) {
        if (Date.parse(str)) {
            var parts = str.split("-");
            return new Date(parts[0], parts[1] - 1, parts[2]);
        }
        var num = parseFloat(str);
        if (isNaN(num)) {
            return str;
        }
        return num;
    }
    for (var i = 0; i < arrows.length; i++) {
        arrows[i].classList.remove("up");
        arrows[i].classList.remove("down");
        arrows[i].classList.add("right");
    }
    if (col === g_lastCol) {
        sorted.sort( function(a,b) {
            if (typeof(extractSortKey(a.children[col].innerText)) == "string") {
                return a.children[col].innerText.localeCompare(b.children[col].innerText);
            }
            return extractSortKey(a.children[col].innerText) - extractSortKey(b.children[col].innerText);
        });
        var arrow = e.target.getElementsByTagName("i")[0];
        arrow.classList.remove("down");
        arrow.classList.add("up");
        g_lastCol = -1;
    } else {
        sorted.sort( function(a,b) {
            if (typeof(extractSortKey(a.children[col].innerText)) == "string") {
                return b.children[col].innerText.localeCompare(a.children[col].innerText);
            }
            return extractSortKey(b.children[col].innerText) - extractSortKey(a.children[col].innerText);
        });
        var arrow = e.target.getElementsByTagName("i")[0];
        arrow.classList.remove("right");
        arrow.classList.add("down");
        g_lastCol = col;
    }
    while (tbody.lastChild) {
        tbody.removeChild(tbody.lastChild);
    }
    for (var i = 0; i < sorted.length; i++) {
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

function update_infobox_position() {
    list = ['popup-help-content', 'popup-help-content-left'];
    for (var i = 0; i < list.length; i++) {
        infobox = document.getElementsByClassName(list[i]);
        for (var j = 0; j < infobox.length; j++) {
            bounding = infobox[j].getBoundingClientRect();
            if (!list[i].includes("-left") && (bounding.right > (window.innerWidth || document.documentElement.clientWidth))) {
                infobox[j].classList.replace(list[i], list[i] + "-left");
            } else if (list[i].includes("-left") && ((bounding.right + infobox[j].offsetWidth) < (window.innerWidth || document.documentElement.clientWidth))) {
                replace = list[i].replace("-left", "");
                infobox[j].classList.replace(list[i], replace);
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
    if (div == null)
        return;
    div.innerText += " " + modDate;
}

function convertDate(date) {
    return date.getFullYear() + "/" +
        ("0" + (date.getMonth() + 1)).slice(-2) + "/" +
        ("0" + date.getDate()).slice(-2) + " " +
        ("0" + date.getHours()).slice(-2) + ":" +
        ("0" + date.getMinutes()).slice(-2) + ":" +
        ("0" + date.getSeconds()).slice(-2);
}

function update_change(time_frame) {
    const short_months = {
        Jan: '01',
        Feb: '02',
        Mar: '03',
        Apr: '04',
        May: '05',
        Jun: '06',
        Jul: '07',
        Aug: '08',
        Sep: '09',
        Oct: '10',
        Nov: '11',
        Dec: '12',
      };
    
    var end_date = new Date();
    if (time_frame.value != 0){
        end_date.setTime(end_date.getTime() - (parseInt(time_frame.value) * 60 * 60 * 24 * 1000))
    }else{
        //Default is seven days ago
        end_date.setTime(end_date.getTime() - (7 * 60 * 60 * 24 * 1000))
    }

    var timeFrameDate = document.getElementById("timeFrameDate");

    try{
        timeFrameDate.innerText = "Timeframe: Today - " + end_date.toISOString().slice(0,10);
    } catch(e){
        timeFrameDate.innerText = "Timeframe: Invalid date";
    }

    //Get the average score from the requested time frame
    var score_dict = {};
    var curr_date;
    for(const [key, value] of Object.entries(file_score_data)){
        //Create an empty list for each file
        score_dict[key] = [];
        for(const [score_key, score_value] of Object.entries(value)){
            //If a date is within the requested time frame, add it to the list
            curr_date = score_key.split(" ")[0].split("-");
            try{
                if(Date.parse(curr_date[0] + "-" + short_months[curr_date[1]] + "-" + curr_date[2]) > end_date.getTime()){
                    score_dict[key].push(value[score_key]);
                }
            } catch(e){
                score_dict[key].push([0]);
            }
        }
        //Replace the list with the average value of the list
        try{
            score_dict[key] = score_dict[key].reduce((a, b) => a + b) / score_dict[key].length;
        } catch(e){
            score_dict[key] = -1;
        }
    }

    //Update the value in the table
    var table = document.getElementById("fileTable");
    var tr = table.getElementsByTagName("tr");
    for(const [key, value] of Object.entries(tr)){
        if(!value.innerText.includes("Path")){
            var row = value.getElementsByTagName("td");        

            var score;
            //Calculate change
            if(score_dict[row[0].innerText] == -1){
                score = 0;
            } else{
                score = parseFloat(row[1].innerText) - score_dict[row[0].innerText];
            }
            if (Math.abs(score) < 0.001 || Number.isNaN(score)){
                score = 0;
            }

            if(score != 0){
                score = score.toFixed(3);
            }

            //Update column with the change
            row[2].innerText = score;

            if(parseFloat(score) > 0){
                row[2].bgColor = "LightGreen";
            } else if(parseFloat(score) < 0){
                row[2].bgColor = "lightsalmon";
            } else{
                row[2].bgColor = "White";
            }
        }
    }

}