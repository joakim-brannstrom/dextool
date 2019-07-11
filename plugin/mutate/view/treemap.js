
function name(d) {
    return d.parent
        ? name(d.parent) + "/" + d.data.name
        : d.data.name;
}
var g_data = [];
var g_path = [];
// set the dimensions and margins of the graph
var margin = {top: 20, right: 20, bottom: 20, left: 20},
width = Math.max(document.documentElement.clientWidth, window.innerWidth || 0)*0.7 - margin.left - margin.right,
height = Math.max(document.documentElement.clientHeight, window.innerHeight || 0)*0.7 - margin.top - margin.bottom;
// append the svg object to the body of the page


//Colorscale for the files is based on mutation score
var color = d3.scaleLinear()
    .domain([0, 0.5 , 1])
    .range(['red',  'orange', 'green'])

// read json data
d3.json("files.json", function(data) {
    function make_map(data) {
        var svg = d3.select("#container")
        .append("svg")
            .attr("width", width + margin.left + margin.right)
            .attr("height", height + margin.top + margin.bottom)
        .append("g")
            .attr("transform",
                "translate(" + margin.left + "," + margin.top + ")");
        var root = d3.hierarchy(data).sum(function(d){ return d.locs+50}) // Here the size of each leave is given in the 'value' field in input data
        // Then d3.treemap computes the position of each element of the hierarchy
        d3.treemap()
        .size([width, height])
        .paddingTop(28)
        .paddingRight(15)
        .paddingInner(15)      // Padding between each rectangle
        .paddingLeft(15)
        .paddingBottom(15)
        .tile(d3["treemapBinary"])
        (root)
        
        
        //console.log(root)
        svg
        .selectAll("rect")
        .data(root.descendants().filter(function(d){return d.depth==1}))
        .enter()
        .append("rect")
            .attr('x', function (d) { return d.x0; })
            .attr('y', function (d) { return d.y0; })
            .attr('width', function (d) { return d.x1 - d.x0; })
            .attr('height', function (d) { return d.y1 - d.y0; })
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
            .on("click", function(d){
                for (var i=0; i<data.children.length; i++) {
                    if (data.children[i].name==d.data.name) {
                        d3.select("svg").remove();
                        if (typeof data.children[i].children === 'undefined') {
                            var path = "files/";
                            for (var j=0; j<g_path.length; j++) {
                                console.log("seg: ", g_path[j]);
                                path += (g_path[j]+"_");
                            }
                            path += data.children[i].name;
                            window.location.href = path+".html"
                        }
                        else {
                            g_data.push(data); //Adds the current subtree of the original data to a stack. Not very efficient, but it works.
                            g_path.push(d.data.name);
                            make_map(data.children[i]);
                        }
                    }
                }
            
            });
        //console.log(root)
        // Add File names
        svg
        .selectAll("text")
        .data(root.leaves().filter(function(d){return d.depth==1}))
        .enter()
        .append("text")
            .attr("x", function(d){ return d.x0+5})    // +10 to adjust position (more right)
            .attr("y", function(d){ return d.y0+13})    // +20 to adjust position (lower)
            .text(function(d){ return d.data.name })
            .attr("font-size", "13px")
            .attr("fill", "black")

        // Add file score
        svg
        .selectAll("vals")
        .data(root.descendants().filter(function(d){return d.depth==1}))
        .enter()
        .append("text")
            .attr("x", function(d){ return d.x0+5})    // +10 to adjust position (more right)
            .attr("y", function(d){ return d.y0+35})    // +20 to adjust position (lower)
            .text(function(d){
            if(d.data.score!=null) 
                return "score: "+d.data.score; 
            else{
                return "avg score: "+Math.round(d.value / d.leaves().length * 100) / 100;
            } 
            })
            .attr("font-size", "13px")
            .attr("fill", "black")
        // Add locs
        svg
        .selectAll("vals")
        .data(root.descendants().filter(function(d){return d.depth==1}))
        .enter()
        .append("text")
            .attr("x", function(d){ return d.x0+5})    // +10 to adjust position (more right)
            .attr("y", function(d){ return d.y0+50})    // +20 to adjust position (lower)
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
        // Add folder names
        svg
        .selectAll("titles")
        .data(root.descendants().filter(function(d){if(d.data.children && d.depth==1)return true; else return false;}))
        .enter()
        .append("text")
            .attr("x", function(d){ return d.x0+5})
            .attr("y", function(d){ return d.y0+21})
            .text(function(d){ return name(d) })
            .attr("font-size", "19px")
            .attr("fill",  "black")//function(d){ return color(d.data.name)} )

        // Add title for the root
        svg
        .append("text")
            .attr("x", 0)
            .attr("y", 14)    // +20 to adjust position (lower)
            .text(root.data.name)//"Mutation score and lines of code by folder")
            .attr("font-size", "19px")
            .attr("fill",  "grey" )
        .on("click", function(d) {
            if (g_data.length) {
            d3.select("svg").remove();
            make_map(g_data.pop())
            g_path.pop();
            }
        })
        return 0;
    }
    make_map(data);
})


