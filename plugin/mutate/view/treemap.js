
var g_previous_states = []; //Keeps track of the previous states
var g_path = []; //Keeps track of the path
var g_curr_state = null;

// set the dimensions and margins of the graph
var margin = {top: 20, right: 20, bottom: 20, left: 20},
width = Math.max(document.documentElement.clientWidth, window.innerWidth || 0)*0.7 - margin.left - margin.right,
height = Math.max(document.documentElement.clientHeight, window.innerHeight || 0)*0.7 - margin.top - margin.bottom;

//Colorscale for the files is based on mutation score
var color = d3.scaleLinear()
    .domain([0, 0.5 , 1])
    .range(['red',  'orange', 'green'])


function rect_click(d){
    var data = g_curr_state;
    for (var i=0; i<data.children.length; i++) {
        if (data.children[i].name==d.data.name) {
            d3.select("svg").remove();
            //Go to source file view
            if (typeof data.children[i].children === 'undefined') {
                var path = "files/";
                for (var j=0; j<g_path.length; j++) {
                    path += (g_path[j]+"_");
                }
                path += data.children[i].name;
                window.location.href = path+".html"
            }
            //Go to folder
            else {
                g_previous_states.push(data); //Adds the current subtree of the original data to a stack. Not very efficient, but it works.
                g_path.push(d.data.name); //Adds the name of the current folder, allows us to rebuild the path.
                window.location.hash = make_hash();
                make_map(data.children[i]);
            }
        }
    }
}
function make_map(data) {
    g_curr_state = data;
    var svg = d3.select("#container")
    .append("svg")
        .attr("width", width + margin.left + margin.right)
        .attr("height", height + margin.top + margin.bottom)
    .append("g")
        .attr("transform",
            "translate(" + margin.left + "," + margin.top + ")");
    var root = d3.hierarchy(data).sum(function(d){ return d.locs})

    d3.treemap()
    .size([width, height])
    .paddingTop(28)
    .paddingRight(15)
    .paddingInner(15)      // Padding between each rectangle
    .paddingLeft(15)
    .paddingBottom(15)
    .tile(d3["treemapBinary"])
    (root)

    //Add rectangles
    svg
    .selectAll("rect")
    .data(root.descendants().filter(function(d){return d.depth==1}))
    .enter()
    .append("rect")
        .attr('x', function (d) { return d.x0; })
        .attr('y', function (d) { return d.y0; })
        .attr('width', function (d) { return d.x1 - d.x0; })
        .attr('height', function (d) { return d.y1 - d.y0; })
        .attr('id', function (d) {
            return "rect_"+d.data.name;
        })
        .style("stroke-width", 2)
        .style("stroke", "black")
        .style("fill", function(d){
            d.sum(function(d) {return d.score;})
            if(d.data.score!=null)
                return color(d.data.score);
            else{
                return color(d.value / d.leaves().length);
            }
        })
        .on("click", function(d) {rect_click(d)})
        .on("mouseenter", function(d) {
            d3.select(this).attr("opacity", 0.5)
            .attr("cursor", "pointer");
        })
        .on("mouseleave", function(d) {
            d3.select(this).attr("opacity", 1)
            .attr("cursor", "auto");
        });

    // Add File names
    svg
    .selectAll("text")
    .data(root.leaves().filter(function(d){return d.depth==1}))
    .enter()
    .append("text")
        .attr("x", function(d){ return d.x0+5})
        .attr("y", function(d){ return d.y0+13})
        .text(function(d){ return d.data.name })
        .attr("font-size", "13px")
        .attr("fill", "black")
        .attr("pointer-events", "none")


    // Add file score
    svg
    .selectAll("vals")
    .data(root.descendants().filter(function(d){return d.depth==1}))
    .enter()
    .append("text")
        .attr("x", function(d){ return d.x0+5})
        .attr("y", function(d){ return d.y0+35})
        .text(function(d){
            if(d.data.score!=null)
                return "score: "+d.data.score;
            else{
                return "avg score: "+Math.round(d.value / d.leaves().length * 100) / 100;
            }
        })
        .attr("font-size", "13px")
        .attr("fill", "black")
        .attr("pointer-events", "none")

    // Add locs
    svg
    .selectAll("vals")
    .data(root.descendants().filter(function(d){return d.depth==1}))
    .enter()
    .append("text")
        .attr("x", function(d){ return d.x0+5})
        .attr("y", function(d){ return d.y0+50})
        .text(function(d){
            d.sum(function(d){ return d.locs})
            if(d.data.locs!=null)
                return "locs: " +d.data.locs;
            else{
                return "total locs: " +d.value;
            }
        })
        .attr("font-size", "13px")
        .attr("fill", "black")
        .attr("pointer-events", "none")
    // Add folder names
    svg
    .selectAll("titles")
    .data(root.descendants().filter(function(d){if(d.data.children && d.depth==1)return true; else return false;}))
    .enter()
    .append("text")
        .attr("x", function(d){ return d.x0+5})
        .attr("y", function(d){ return d.y0+21})
        .text(function(d){ return d.data.name; })
        .attr("font-size", "19px")
        .attr("fill",  "black")
        .attr("pointer-events", "none")

    // Add title for the root
    svg
    .append("text")
        .attr("x", 0)
        .attr("y", 14)
        .text(function (d) {
            var path ="root/";
            for (var j=0; j<g_path.length; j++) {
                path += (g_path[j]+"/");
            }
            return path;
        })
        .attr("font-family", "Courier New")
        .attr("font-size", "19px")
        .attr("id", "title")
        .attr("fill",  "grey" )
        .on("click", function(d) {
            if (g_previous_states.length) {
                d3.select("svg").remove();
                g_path.pop();
                window.location.hash = make_hash();
                make_map(g_previous_states.pop());
            }
            else {
                window.location.href = "index.html";
            }
        })
        .on("mouseenter", function() {
            d3.select(this)
                .attr("text-decoration","underline")
                .attr("cursor", "pointer");
        })
        .on("mouseleave", function() {
            d3.select(this)
                .attr("text-decoration","none")
                .attr("cursor", "auto");
        })
    return 0;
}
/**
 * Generates the hash from the current path
 */
function make_hash() {
    var path ="#root_";
    for (var j=0; j<g_path.length; j++) {
        path += (g_path[j]+"_");
    }
    return path.slice(0,path.length-1);
}
/**
 * Takes the hash and assigns the correct state.
 * @param {JSON} data
 */
function go_to_hash(data) {
    var hash = window.location.hash.substring(1);
    if (!hash) {
        window.location.hash = "#root";
    }
    else { //Set the state according to the hash
        var path = hash.split("_");
        var curr = data;
        if (path.length > 1 && path[0]=="root") {
            for (var i = 1; i <path.length; i++) {
                for (var j = 0; j<curr["children"].length; j++) {
                    if (curr["children"][j]["name"] == path[i]) {
                        g_previous_states.push(curr);
                        curr = curr["children"][j];
                        g_path.push(curr.name);
                        break;
                    }
                }
            }
            window.location.hash = make_hash(); //Triggers onhashchange
            data = curr;
        }
        else {
            window.location.hash = "#root"; //Triggers onhashchange
        }
    }
    d3.select("svg").remove();
    make_map(data);
}
function init() {
    //Manage the user using the back and forward buttons
    window.onhashchange = function(event) {
        var new_url = event.newURL;
        var index = new_url.lastIndexOf("#")
        if (index < 0) { //No hash, so go back to index
            window.location.href = "index.html";
            return;
        }
        var new_hash = new_url.slice(index, new_url.length);
        var curr_hash = make_hash()
        if (curr_hash!=new_hash) {
            g_previous_states = [];
            g_path = [];
            go_to_hash(g_indata);
        }
    }
    window.addEventListener("unload", function(event) {}); //Prevents caching
    go_to_hash(g_indata);
}

