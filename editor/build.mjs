import {build} from 'esbuild';
import {readFileSync,writeFileSync} from 'node:fs';
import path from 'node:path';
const result=await build({entryPoints:['src/editor.js'],bundle:true,minify:true,format:'iife',target:'chrome91',outfile:'../app/src/main/assets/editor.js',legalComments:'external',metafile:true});
const licensePackages=new Set(Object.keys(result.metafile.inputs).filter(p=>p.includes('node_modules')).map(p=>p.match(/node_modules\/(?:@[^/]+\/)?[^/]+/)?.[0]).filter(Boolean));
const notices=[];for(const name of licensePackages){for(const filename of ['LICENSE','LICENSE.md','LICENSE.txt']){try{notices.push(name+'\n'+readFileSync(path.join(name,filename),'utf8'));break;}catch{}}}
writeFileSync('../app/src/main/assets/editor-LICENSE.txt',notices.join('\n\n'));
