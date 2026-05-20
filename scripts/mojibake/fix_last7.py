#!/usr/bin/env python3
import os, re
src = r'D:\zPython\MakerAi\Source'
fixes = {r'\bv\?lido\b':'valid',r'\bvac\?o\b':'empty',r'\bdue\?a\b':'owner',r'\bdue\?o\b':'owner',r'\bquiz\?s\b':'perhaps',r'\brecorrer\?as\b':'you would traverse',r'\b\?critical\b':'critical'}
for root,dirs,files in os.walk(src):
    dirs[:]=[d for d in dirs if d not in('Packages','Resources','hpp')]
    for fn in sorted(files):
        if not fn.endswith('.pas'): continue
        fp=os.path.join(root,fn)
        try:
            with open(fp,'r',encoding='utf-8-sig') as f: c=f.read()
        except:
            try:
                with open(fp,'r',encoding='latin-1') as f: c=f.read()
            except: continue
        changed=False;lines=c.split('\n')
        for i,l in enumerate(lines):
            if '?' not in l: continue
            if '//' not in l and '{' not in l and '(*' not in l: continue
            if any(s in l.lower() for s in['mit license','copyright','permission is','the software','warranty']): continue
            o=l
            for p,r in fixes.items(): l=re.sub(p,r,l,flags=re.IGNORECASE)
            if l!=o: lines[i]=l;changed=True
        if changed:
            new='\n'.join(lines)
            if new.startswith('\ufeff'): new=new[1:]
            with open(fp,'w',encoding='utf-8',newline='\n') as f: f.write('\ufeff'+new)
            print(os.path.relpath(fp,src))
