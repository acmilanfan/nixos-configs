// Build LeechBlock NG's managed-storage file from an options export.
//
//   node leechblock-managed.js <LeechBlockNG common.js> <LeechBlockOptions.json>
//
// LeechBlock copies managed storage into its local storage on every start,
// but the export lacks the compiled block patterns (blockRE<n> etc.): only the
// options page's Save builds those, so imported sites would block nothing.
// Compute them with LeechBlock's own getRegExpSites, exactly as Save does.
// Per-set passwords (passwordSetSpec<n>) are dropped: keys absent from managed
// storage are left alone, so a password set once in the UI survives.
// Exported strings (customStyle, etc.) are escaped with \n by LeechBlock's
// exportOptions; unescape them so runtime local storage gets real newlines.

const fs = require("fs");
const vm = require("vm");

const [commonPath, exportPath] = process.argv.slice(2);

const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(commonPath, "utf8"), ctx, { filename: commonPath });

const options = JSON.parse(fs.readFileSync(exportPath, "utf8"));
for (const key of Object.keys(options)) {
  if (/^passwordSetSpec\d+$/.test(key)) delete options[key];
  if (typeof options[key] === "string") {
    options[key] = options[key].replace(/\\n/g, "\n");
  }
}
for (let set = 1; set <= options.numSets; set++) {
  const re = ctx.getRegExpSites(options[`sites${set}`], options.matchSubdomains);
  options[`blockRE${set}`] = re.block;
  options[`allowRE${set}`] = re.allow;
  options[`referRE${set}`] = re.refer;
  options[`keywordRE${set}`] = re.keyword;
}

process.stdout.write(JSON.stringify({
  name: "leechblockng@proginosko.com",
  description: "LeechBlock NG options managed by nixos-configs",
  type: "storage",
  data: options,
}, null, 2) + "\n");
