import json,textwrap
from pathlib import Path
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon as Patch
from shapely.geometry import shape
p=Path(__file__).parent;src=json.loads((p/'map-source.json').read_text());l=src['level'];data=json.loads(Path('godot/assets/data/pen_lucy_civic_proposals.json').read_text());courts=json.loads(Path('godot/assets/data/pen_lucy_courts.json').read_text())['courts'];colors={'police':'#7cbcff','fire':'#ff967d','hospital':'#d4a1ff'}
for service in colors:
 fig=plt.figure(figsize=(16,10),facecolor='#101c23');ax=fig.add_axes((.025,.13,.71,.73),facecolor='#15252c');ax.set(xlim=(-225,610),ylim=(290,-330),aspect='equal');ax.axis('off')
 for park in l['parks']:ax.add_patch(Patch([(v[0],v[2]) for v in park['polygon']],facecolor='#314e3b'))
 for r in l['roads']:
  x,z=zip(*[(v[0],v[2]) for v in r['points']]);ax.plot(x,z,color='#52666d',lw=r['width']*.28,zorder=2)
 for b in src['buildings']:ax.add_patch(Patch(shape(b['polygon']).exterior.coords,facecolor='#877d71',edgecolor='#aa9b85',lw=.12,zorder=3))
 for c in courts:ax.add_patch(Patch(c['footprint'],facecolor='#a18745',zorder=4))
 labels=[('Greenmount Ave',-173,-54,90),('Old York Rd',0,-34,90),('Frisby St',110,58,90),('Wilsby Ave',265,-125,90),('Argonne Dr',367,-3,31),('East 41st St',119,-263,2),('Cator Ave',176,-188,2),('Rose Hill Terrace',-95,-151,1),('Dumbarton Ave',129,-89,2),('Wyanoke Ave',125,-6,3),('East 39th St',-105,104,0),('East 38th St',-84,217,0),('Ellerslie Ave',88,145,-27)]
 for name,x,z,angle in labels:ax.text(x,z,name,color='#d8e0dc',fontsize=7,rotation=angle,ha='center',va='center',zorder=5,bbox=dict(facecolor='#15252c',edgecolor='none',pad=.3,alpha=.8))
 entries=[q for q in data['proposals'] if q['service']==service]
 for index,q in enumerate(entries):
  col=colors[service];ax.add_patch(Patch(q['access'],facecolor=col,alpha=.2,zorder=6));ax.add_patch(Patch(q['polygon'],facecolor=col,edgecolor=col,alpha=.7,zorder=7));x,_,z=q['position'];ax.text(x,z-18,q['id']+(' *' if q['recommended'] else ''),color=col,fontsize=13,weight='bold',ha='center',zorder=8,bbox=dict(facecolor='#101c23',edgecolor=col,boxstyle='round,pad=.3'))
  top=.79-index*.22;fig.text(.756,top,q['id']+'  '+('PREFERRED' if q['recommended'] else 'ALTERNATIVE'),color=col,weight='bold',fontsize=13);fig.text(.756,top-.032,'\n'.join(textwrap.wrap(q['title'],32)),color='#eef1f1',weight='bold',fontsize=11,va='top');fig.text(.756,top-.077,'\n'.join(textwrap.wrap(q['notes'],44)),color='#bdcbd0',fontsize=8.5,va='top',linespacing=1.3);fig.text(.756,top-.185,f"{q['width']:.0f} x {q['depth']:.0f} m lot / 6 m road access",color='#8daab6',fontsize=9)
 ax.text(-199,-300,'N ↑',color='#e0e9eb',fontsize=18,weight='bold');ax.plot([-192,-92],[268,268],color='#bdcbd0',lw=2);ax.text(-142,282,'100 m',ha='center',color='#bdcbd0',fontsize=9)
 fig.text(.045,.94,'PEN LUCY  /  CIVIC SITE STUDY',color='#a8bec9',fontsize=12);fig.text(.045,.89,service.title()+' — three proposed options',color='#eef3f4',fontsize=25,weight='bold');fig.text(.045,.075,'Actual city export  ·  Tan: existing buildings  ·  Ochre: courts  ·  Green: mapped parks  ·  Coloured: proposed envelope',color='#bdcbd0',fontsize=10);fig.text(.045,.04,'PROPOSED ONLY. No homes or courts removed. Compact concepts; access, grading and landscape design remain for a later build.',color='#8daab6',fontsize=10)
 fig.savefig(p/f'{service}-sites.png',dpi=130,facecolor=fig.get_facecolor());plt.close(fig)
