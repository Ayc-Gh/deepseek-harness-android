const fs = require('node:fs');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const path = require('node:path');
const report = [];
async function test(name, run) {
  try { const detail = await run(); report.push({name,pass:true,detail}); }
  catch(error) { report.push({name,pass:false,error:String(error.stack || error)}); }
}
(async()=>{
  const work='/home/dsh/workspace/smoke';
  fs.mkdirSync(work,{recursive:true});
  await test('ordinary-user-and-capabilities',()=>{
    assert.equal(process.getuid(),2000);
    const s=fs.readFileSync('/proc/self/status','utf8');
    assert.match(s,/CapEff:\s+0+\n/);
    assert.match(s,/CapBnd:\s+0+\n/);
    assert.match(s,/NoNewPrivs:\s+1/);
    assert.equal(fs.existsSync('/data/adb'),false);
    assert.throws(()=>fs.accessSync('/etc',fs.constants.W_OK));
    return {uid:process.getuid(),platform:process.platform,arch:process.arch};
  });
  await test('filesystem-hardlink-rename',()=>{
    const stem=path.join(work,'test-'+Date.now());
    fs.writeFileSync(stem+'.txt','DSH_SMOKE_OK\n');
    fs.linkSync(stem+'.txt',stem+'.hardlink');
    fs.renameSync(stem+'.hardlink',stem+'.renamed');
    assert.equal(fs.readFileSync(stem+'.renamed','utf8'),'DSH_SMOKE_OK\n');
    return 'write/read/link/rename passed';
  });
  await test('bash-git-python',()=>cp.execFileSync('/bin/bash',['-c','printf BASH_OK; git --version; python3 --version'],{encoding:'utf8',cwd:work}));
  await test('sharp-native-image',async()=>{
    const sharp=require('sharp');
    const file=path.join(work,'generated.png');
    await sharp({create:{width:16,height:16,channels:4,background:'#217fcb'}}).png().toFile(file);
    const meta=await sharp(file).metadata();
    assert.equal(meta.width,16);
    return {width:meta.width,height:meta.height,format:meta.format};
  });
  await test('koffi-libc',()=>{
    const koffi=require('koffi');
    const getuid=koffi.load('libc.so.6').func('unsigned int getuid(void)');
    assert.equal(getuid(),2000);
    return 'libc FFI passed';
  });
  await test('ripgrep-native-search',()=>{
    const {rgPath}=require('@vscode/ripgrep');
    const output=cp.execFileSync(rgPath,['-l','DSH_SMOKE_OK',work],{encoding:'utf8'});
    assert.ok(output.includes('.txt'));
    return 'bundled ARM64 ripgrep passed';
  });
  await test('node-pty-terminal',()=>new Promise((resolve,reject)=>{
    const pty=require('node-pty');
    const term=pty.spawn('/bin/bash',['-c','printf PTY_OK; id -u'],{name:'xterm-256color',cols:80,rows:24,cwd:work,env:process.env});
    let output='';
    const timer=setTimeout(()=>{term.kill();reject(Error('PTY timeout'));},10000);
    term.onData(s=>output+=s);
    term.onExit(({exitCode})=>{clearTimeout(timer);try{assert.equal(exitCode,0);assert.ok(output.includes('PTY_OK2000'));resolve(output.trim());}catch(e){reject(e);}});
  }));
  await test('session-native-flock',async()=>{
    const {tryLockExclusive}=require('@deepseek-ai/node-addon-system/flock');
    const fd=fs.openSync(path.join(work,'lock'),'w');
    try {await tryLockExclusive(fd);} finally {fs.closeSync(fd);}
    return 'native advisory lock passed';
  });
  fs.writeFileSync('/home/dsh/native-smoke-results.json',JSON.stringify(report,null,2));
  console.log(JSON.stringify(report,null,2));
  process.exitCode=report.some(t=>!t.pass)?1:0;
})().catch(e=>{console.error(e);process.exitCode=1;});
