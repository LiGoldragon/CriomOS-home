import fs from 'node:fs';
const args=process.argv.slice(2);
if(args[0]!=='queue'||args[1]!=='--thread'||args[3]!=='--message') process.exit(2);
const payload=JSON.parse(args[4]);
if(payload.type!=='Heartbeat'||!payload.identity) process.exit(3);
if(process.env.HEARTBEAT_TEST_CAPTURE) fs.writeFileSync(process.env.HEARTBEAT_TEST_CAPTURE,args[4]);
console.log('Queued message 11111111-2222-3333-4444-555555555555 for thread '+args[2]);
