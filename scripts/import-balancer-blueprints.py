"""Normalize the documented Raynquist/Dogmai construction blueprint book."""
import argparse
import base64
import json
import re
import zlib
from pathlib import Path

D={0:(0,-1),4:(1,0),8:(0,1),12:(-1,0)}
entries=[]
def walk(v):
 if 'blueprint' in v:
  b=v['blueprint'];match=re.match(r'(\d+)_(\d+)(?:_|$)',b.get('label',''))
  if match and int(match[1])<=32 and int(match[2])<=32 and not any(x in b['label'] for x in ('_lane','corner','p-split')):entries.append(b)
 elif 'blueprint_book' in v:
  for child in v['blueprint_book'].get('blueprints',[]):walk(child)
def inspect(b,strict=False):
 n,m=map(int,re.match(r'(\d+)_(\d+)',b['label']).groups());entities=[];cells={}
 for raw in b['entities']:
  name=raw['name'];kind='splitter' if name.endswith('splitter') else 'underground' if name.endswith('underground-belt') else 'belt' if name.endswith('transport-belt') else None
  if not kind:continue
  direction=raw.get('direction',0)*(2 if b['version']>>48<2 else 1)
  e={'kind':kind,'x':raw['position']['x']-.5,'y':raw['position']['y']-.5,'direction':direction,'type':raw.get('type'),'input_priority':raw.get('input_priority'),'output_priority':raw.get('output_priority'),'filter':raw.get('filter')}
  entities.append(e)
  offsets=[(0,0)] if kind!='splitter' else [(-.5,0),(.5,0)] if direction in (0,8) else [(0,-.5),(0,.5)]
  for dx,dy in offsets:cells[(e['x']+dx,e['y']+dy)]=e
 def accepts(e,d):return e and (e['direction']==d if e['kind']=='splitter' or e['type']=='input' else e['direction']!=(d+8)%16)
 def incoming(x,y,e):
  for d,(dx,dy) in D.items():
   prior=cells.get((x-dx,y-dy))
   if prior and prior['direction']==d and prior['type']!='input' and accepts(e,d):return True
  return False
 ins=[];outs=[]
 for (x,y),e in cells.items():
  if e['direction']!=8:continue
  if e['kind']=='splitter':
   if not accepts(cells.get((x,y+1)),8):outs.append((x,y+1))
   if not cells.get((x,y-1)):ins.append((x,y-1))
  else:
   if e['type']!='input' and not accepts(cells.get((x,y+1)),8):outs.append((x,y+1))
   if e['type']!='output' and not incoming(x,y,e):ins.append((x,y-1))
 first=min((y for x,y in ins),default=0);last=max((y for x,y in outs),default=0)
 ips=sorted(set((x,y) for x,y in ins if y==first));ops=sorted(set((x,y) for x,y in outs if y==last))
 reach=0
 for e in entities:
  if e['type']=='input':
   dx,dy=D[e['direction']]
   for dist in range(1,21):
    other=cells.get((e['x']+dx*dist,e['y']+dy*dist))
    if other and other['type']=='output' and other['direction']==e['direction']:
     reach=max(reach,dist);break
   else:return None,'unpaired tunnel'
 if len(ips)<n or (strict and len(ips)!=n) or len(ops)!=m:return None,f'ports {len(ips)}->{len(ops)}, expected {n}->{m}'
 shift=ops[0][0];sy=first+1
 normalized=[]
 for e in entities:normalized.append(dict(e,x=e['x']-shift,y=e['y']-sy))
 descriptor={'label':b['label'],'n':n,'m':m,'reach':reach,'specs':normalized,'inputs':[{'x':x-shift,'y':y-sy} for x,y in ips[:n]],'outputs':[{'x':x-shift,'y':y-sy} for x,y in ops]}
 return descriptor,None

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--book",type=Path,required=True)
    parser.add_argument("--output",type=Path,default=Path(__file__).resolve().parents[1]/"mpp/balancer_blueprints.lua")
    args=parser.parse_args()
    raw=args.book.read_text().strip()
    book=json.loads(raw) if raw.startswith("{") else json.loads(zlib.decompress(base64.b64decode(raw[1:])))
    walk(book)
    # These alternatives require a lane-specific model; use validated compatible variants.
    excluded={"5_8_yellow","8_9_blue","16_16_alt_balancer_yellow"}
    layouts=[]
    for blueprint in entries:
        if blueprint["label"] in excluded:
            continue
        descriptor,error=inspect(blueprint)
        if descriptor:
            layouts.append(descriptor)
    def number(value):return str(int(value)) if value==int(value) else str(value)
    def text(value):return 'nil' if value is None else json.dumps(value,ensure_ascii=True)
    lines=['-- Normalized Raynquist/Dogmai blueprint data; see BALANCER_BLUEPRINTS.md.','return {']
    for layout in layouts:
        lines.append('\t{label='+text(layout['label'])+',n='+str(layout['n'])+',m='+str(layout['m'])+',reach='+str(layout['reach'])+',tu='+str('_tu' in layout['label']).lower()+',')
        lines.append('\t\tinputs={'+','.join('{'+number(p['x'])+','+number(p['y'])+'}' for p in layout['inputs'])+'},')
        lines.append('\t\toutputs={'+','.join('{'+number(p['x'])+','+number(p['y'])+'}' for p in layout['outputs'])+'},')
        encoded=[]
        for e in layout['specs']:
            values=[text(e['kind']),number(e['x']),number(e['y']),str(e['direction']),text(e['type']),text(e.get('input_priority')),text(e.get('output_priority'))]
            while values[-1]=='nil':values.pop()
            encoded.append('{'+','.join(values)+'}')
        lines.append('\t\tentities={'+','.join(encoded)+'},')
        lines.append('\t},')
    lines.append('}')

    args.output.write_text("\n".join(lines)+"\n")
    print(f"Imported {len(layouts)} normalized construction layouts into {args.output}")

if __name__ == "__main__":
    main()
