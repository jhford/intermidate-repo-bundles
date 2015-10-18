/**
 * Outputting JSON in bash is annoying and hard so I'm going to take
 * the psuedo JSON that I produce there and make it nicer.
 */
let fs = require('fs');
let _ = require('lodash');

let lines = fs.readFileSync(process.argv[2]).toString().split('\n');
console.log('Data file from :' + lines[0]);
lines = lines.slice(1);
console.log(lines.length);

let dataPoints = [];

// Ugh, i should've done one-line===one-object not pretty printing in bash
let curObject = [];
for (let line of lines) {
  // Massage non-numbers into strings
  if (line.match(/"level":/)) {
    line = line.replace(/: *([^,]*) *(,)? *$/, ': "$1"$2');
  }

  curObject.push(line);
  if (line === '}') {
    let obj = curObject.join('');
    try {
      obj = JSON.parse(obj);
    } catch (e) {
      console.error(e.stack || e);
      console.dir(curObject.join('\n')); 
      throw e;
    }
    dataPoints.push(obj);
    curObject = [];
  }
}

let sortedPnts = {};
for (let pnt of dataPoints) {
  let array = _.get(sortedPnts, [pnt.name], []);
  let obj = {
    time: pnt.time,
    metric: {},
  };
  _.each(pnt.metric, (v, k) => {
    if (k.match(/-filesize$/)) {
      let realName = k.replace(/-filesize$/, '')
      obj.metric[realName] = {
        filename: realName,
        size: v,
      };
    } else {
      obj.metric[k] = v;
    }
  });
  array.splice(pnt.iter, 0, obj);
  _.set(sortedPnts, [pnt.name], array);
}

fs.writeFileSync('out.json', JSON.stringify(sortedPnts, null, 2));

