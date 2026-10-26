"use strict";
const path = require("path");
const pm2 = require(path.join(process.env.APPDATA, "npm", "node_modules", "pm2"));
const deadline = setTimeout(() => { console.error("PM2 status timed out"); process.exit(1); }, 8000);
function fail(message) {
  clearTimeout(deadline);
  console.error(message);
  pm2.disconnect();
  process.exitCode = 1;
}
pm2.connect((error) => {
  if (error) return fail("Could not connect to PM2.");
  pm2.list((error, processes) => {
    if (error) return fail("Could not read PM2 process list.");
    console.log(JSON.stringify(processes.map((entry) => ({
      name: entry.name,
      pid: entry.pid,
      pm2_env: {
        status: entry.pm2_env.status,
        pm_exec_path: entry.pm2_env.pm_exec_path,
        args: entry.pm2_env.args,
        pm_uptime: entry.pm2_env.pm_uptime,
        restart_time: entry.pm2_env.restart_time
      }
    }))));
    pm2.disconnect();
    clearTimeout(deadline);
  });
});
