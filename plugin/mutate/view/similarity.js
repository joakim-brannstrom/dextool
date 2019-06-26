/**
 * Javascript for the subpage "test_case_similarity"
 * 
 */

 /**
  * Initializes the click events.
  */
function init() {
    var headers = document.getElementsByClassName('tbl_header');
    for (var i = 0; i < headers.length; i++) {
        headers[i].addEventListener('click', function(e) {
            header_onclick(e);
        });
    }
}
/**
 * 
 * @param {event} e click event
 */
function header_onclick(e) {
    var tbl_container = e.target.closest('.comp_container')
        .getElementsByClassName('tbl_container')[0];
    if (tbl_container.style.display === 'inline')
        tbl_container.style.display = 'none';
    else
        tbl_container.style.display = 'inline';
}