"""Generate independent complete-cell Canvas/Chart oracle fixtures."""
import hashlib
import json
import pathlib
import random
import subprocess

root = pathlib.Path(__file__).resolve().parents[2]
markers = ['Dot','Block','Bar','Braille','HalfBlock','Quadrant','Sextant','Octant','Custom']
canvas = []
chart = []
def canvas_case(name, actions, **fields):
    case = dict(kind='canvas',name=name,area=dict(x=3,y=2,width=17,height=9),
                xBounds=[-10,10],yBounds=[-10,10],actions=actions)
    case.update(fields); canvas.append(case)
shapes = [dict(kind='line',x=-30,y=-12,x2=25,y2=8,color='Red'),
          dict(kind='line',x=-30,y=11,x2=30,y2=11,color='Red'),
          dict(kind='line',x=8,y=-8,x2=-8,y2=8,color='Green'),
          dict(kind='filledLine',x=-12,y=4,x2=15,y2=-7,fillToY=2,color='Blue'),
          dict(kind='rectangle',x=-8,y=-7,width=12,height=10,color='Yellow'),
          dict(kind='circle',x=4,y=2,radius=7,color='Magenta'),
          dict(kind='points',coords=[[-10,-10],[10,10],[0,0],[0.5,0.5],[10.01,0]],color='Cyan')]
for marker in markers:
    for i,shape in enumerate(shapes): canvas_case(f'{marker}-shape-{i}',[shape],marker=marker,customSymbol='界' if marker=='Custom' else '*')
    canvas_case(f'{marker}-layers',shapes[:2]+[dict(kind='layer')]+shapes[2:]+[
        dict(kind='print',x=-9,y=8,line={'spans':[{'text':'界é','style':{'fg':'Red','add':1}}],'style':{'bg':'Blue'}}),
        dict(kind='print',x=10,y=-10,line='end'),dict(kind='print',x=30,y=2,line='hidden')],
        marker=marker,customSymbol='*',initialSymbol='.',initialStyle={'fg':'Green','bg':'Red','add':4},backgroundColor='Black')
    for resolution in ['Low','High']:
        canvas_case(f'{marker}-map-{resolution}',[dict(kind='map',resolution=resolution,color='Green')],
                    marker=marker,customSymbol='*',xBounds=[-180,180],yBounds=[-90,90],area=dict(x=0,y=0,width=40,height=20))
    for width,height in [(0,0),(0,2),(1,1),(2,1),(1,2),(3,3)]:
        canvas_case(f'{marker}-tiny-{width}-{height}',shapes,marker=marker,customSymbol='*',area=dict(x=4,y=5,width=width,height=height))
for marker,w,h,bits in [('Quadrant',2,2,4),('Sextant',2,3,6),('Braille',2,4,8),('Octant',2,4,8)]:
    pixels = [[(pattern%16)*w+bit%w,(pattern//16)*h+bit//w] for pattern in range(1<<bits) for bit in range(bits) if pattern&(1<<bit)]
    canvas_case(f'{marker}-every-pattern',[dict(kind='pixels',coords=pixels,color='Red')],marker=marker,area=dict(x=0,y=0,width=16,height=(1<<bits)//16))
canvas_case('halfblock-colors',[dict(kind='pixels',coords=[[0,0],[1,1],[2,0],[2,1],[3,0]],color='Red'),
                              dict(kind='pixels',coords=[[3,1]],color='Blue')],marker='HalfBlock',area=dict(x=0,y=0,width=5,height=1))
canvas_case('marker-switch',[dict(kind='marker',marker='Block'),dict(kind='points',coords=[[0,0]],color='Blue'),
                            dict(kind='marker',marker='Braille'),dict(kind='points',coords=[[0,0]],color='Yellow'),
                            dict(kind='marker',marker='HalfBlock'),dict(kind='points',coords=[[-10,10]],color='Red')],
            initialSymbol='.',initialStyle={'fg':'White','bg':'Green'},backgroundColor='Black')
for xb,yb in [([0,0],[0,0]),([1,-1],[-2,2]),([-1,1],[2,-2]),([-1,1],[-1,1])]:
    canvas_case(f'bounds-{xb}-{yb}',shapes+[dict(kind='print',x=0,y=0,line='zero')],xBounds=xb,yBounds=yb)
canvas_case('bordered',shapes,block={'title':'Canvas 界','style':{'fg':'Green','bg':'Blue'},'borderStyle':{'fg':'Red'}})
canvas_case('styled-label-precedence',[
    dict(kind='print',x=0,y=0,line={'spans':[{'text':'A界','style':{'fg':[18,97,220],'underlineColor':125,'remove':1,'add':12}}],
                                 'style':{'bg':120}}),
    dict(kind='points',coords=[[0,0]],color='Red'),dict(kind='layer'),
    dict(kind='print',x=0,y=0,line={'spans':[{'text':'Z','style':{'reset':True,'fg':'Yellow'}}]}),
    dict(kind='points',coords=[[0,0]],color='Blue')],
    initialSymbol='.',initialStyle={'fg':'Cyan','underlineColor':[120,80,190],'add':511},backgroundColor='Green')
canvas_case('empty-actions',[],initialStyle={'fg':'Red','bg':'Blue'})
rng = random.Random(302)
for i in range(120):
    actions = []
    for j in range(5):
        kind = rng.choice(['line','filledLine','circle','rectangle'])
        action = dict(kind=kind,x=rng.uniform(-30,30),y=rng.uniform(-30,30),color=rng.choice(['Red','Green','Blue',123,[17,93,201]]))
        action.update(x2=rng.uniform(-30,30),y2=rng.uniform(-30,30),fillToY=rng.uniform(-30,30),
                      radius=rng.uniform(-15,25),width=rng.uniform(-20,30),height=rng.uniform(-20,30))
        actions.append(action)
        if j==2 and i%2==0: actions.append(dict(kind='layer'))
    canvas_case(f'seed302-{i}',actions,marker=markers[i%len(markers)],customSymbol='*',
                area=dict(x=i%9,y=i%7,width=rng.randrange(1,23),height=rng.randrange(1,14)),
                xBounds=[rng.uniform(-15,-1),rng.uniform(1,15)],yBounds=[rng.uniform(-15,-1),rng.uniform(1,15)])

points=[[-4,-5],[-2,3],[0,0],[2,7],[5,-3],[8,5],[12,9]]
def chart_case(name, **fields):
    case=dict(kind='chart',name=name,area=dict(x=3,y=2,width=30,height=15),datasets=[dict(data=points,marker='Braille',style={'fg':'Red'})],
              xAxis=dict(bounds=[-2,10]),yAxis=dict(bounds=[-5,10]))
    case.update(fields);chart.append(case)
for marker in markers:
    for graph in ['Scatter','Line','Bar','Area']:
        chart_case(f'{marker}-{graph}',datasets=[dict(data=points,marker=marker,customSymbol='*',graphType=graph,fillToY=2,style={'fg':'Red','bg':'Blue','add':1})],
                   initialSymbol='.',initialStyle={'fg':'Green','bg':'Magenta','add':4},style={'fg':'White','bg':'Black'})
for legend in ['Top','TopRight','TopLeft','Left','Right','Bottom','BottomRight','BottomLeft',None]:
    for xt,yt in [(False,False),(True,False),(False,True),(True,True)]:
        xa=dict(bounds=[-2,10],labels=['-2','4','10'])
        ya=dict(bounds=[-5,10],labels=['-5','0','5','10'])
        if xt:xa['title']='x axis'
        if yt:ya['title']='y axis'
        chart_case(f'legend-{legend}-{xt}-{yt}',legendPosition=legend,hiddenLegendConstraints=[{'kind':'min','value':0}]*2,xAxis=xa,yAxis=ya,
                   datasets=[dict(data=points,name={'spans':[{'text':'界','style':{'fg':'Yellow'}}],'style':{'add':1}},marker='Block',style={'fg':'Red','bg':'Blue'}),
                             dict(data=[[0,8],[10,-3]],name='line',marker='Braille',graphType='Line',style={'fg':'Green'}),dict(data=[])])
for xa in ['Left','Center','Right']:
    for ya in ['Left','Center','Right']:
        for width,height in [(0,0),(1,1),(2,2),(3,3),(5,2),(8,4),(17,8)]:
            chart_case(f'labels-{xa}-{ya}-{width}-{height}',area=dict(x=5,y=7,width=width,height=height),
                       xAxis={'bounds':[-2,10],'labels':['wide界','comb é','👩‍💻 right'],'alignment':xa,'style':{'fg':'Blue'},'title':'X'},
                       yAxis={'bounds':[-5,10],'labels':['lower界','mid','upper👩‍💻'],'alignment':ya,'style':{'fg':'Yellow'},'title':'Y'})
for count in [0,1,2,5,12]:
    chart_case(f'label-count-{count}',xAxis={'bounds':[-2,10],'labels':[str(i) for i in range(count)]},
               yAxis={'bounds':[-5,10],'labels':[str(i) for i in range(count)]})
for constraint in [{'kind':'length','value':0},{'kind':'length','value':5},{'kind':'percentage','value':25},{'kind':'ratio','numerator':1,'denominator':1},
                   {'kind':'max','value':4},{'kind':'min','value':0},{'kind':'fill','value':1}]:
    chart_case('hidden-'+str(constraint),datasets=[dict(data=points,name='name')],hiddenLegendConstraints=[constraint,constraint])
chart_case('defaults',datasets=[{}],xAxis={},yAxis={})
chart_case('empty',datasets=[])
chart_case('bordered',block={'title':'Chart 界','style':{'fg':'Green','bg':'Blue'},'borderStyle':{'fg':'Red'}},
           xAxis={'bounds':[-2,10],'labels':['left','middle','right'],'title':'x'},yAxis={'bounds':[-5,10],'labels':['low','high'],'title':'y'})
for i in range(80):
    datasets=[]
    for j in range(rng.randrange(1,5)):
        dataset=dict(data=[[rng.uniform(-20,20),rng.uniform(-20,20)] for _ in range(rng.randrange(0,9))],
                     marker=rng.choice(markers),customSymbol='*',graphType=rng.choice(['Scatter','Line','Bar','Area']),
                     fillToY=rng.uniform(-30,30),style={'fg':rng.choice(['Red','Green',125,[12,75,93]]),'add':rng.randrange(512)})
        if rng.randrange(3): dataset['name']=rng.choice(['','A','界line','wide name'])
        datasets.append(dataset)
    axes=[dict(bounds=[-10,10],labels=[str(j) for j in range(rng.randrange(6))],
               alignment=rng.choice(['Left','Center','Right']),title=rng.choice(['','axis','界title'])) for _ in range(2)]
    chart_case(f'seed302-{i}',datasets=datasets,xAxis=axes[0],yAxis=axes[1],
               area=dict(x=i%9,y=i%7,width=rng.randrange(1,35),height=rng.randrange(1,19)),
               legendPosition=rng.choice(['Top','TopRight','TopLeft','Left','Right','Bottom','BottomRight','BottomLeft',None]),
               hiddenLegendConstraints=[{'kind':'min','value':0}]*2)
subprocess.run(['cargo','build','--quiet','--manifest-path','tools/reference/Cargo.toml','--bin','canopy-chart-reference','--locked','--target-dir','/tmp/canopy-chart-target'],cwd=root,check=True)
for name,cases in [('canvas',canvas),('chart',chart)]:
    oracle=subprocess.run(['/tmp/canopy-chart-target/debug/canopy-chart-reference'],input=json.dumps(cases),text=True,capture_output=True,check=True)
    target=root/f'tests/{name}_fixtures.json'
    fixture=json.loads(oracle.stdout)
    fixture['seed']=302
    fixture['cargoLockSha256']=hashlib.sha256((root/'tools/reference/Cargo.lock').read_bytes()).hexdigest()
    target.write_text(json.dumps(fixture,separators=(',',':'))+'\n')
    print(f'{name}: {len(cases)} complete-cell cases -> {target}')
