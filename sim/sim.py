import math, random
GAIN=[0.5,0.45,0.44,0.43,0.47,0.51,0.58,0.62,0.69,0.73,0.8,0.84,0.92,0.96,0.99,1.08,1.14,1.2,1.26,1.32,1.38,1.44,1.5,1.56]+[1.6]*8
def true_gain(u):  # 仿真里的"真实"加速曲线, 故意与初始表有 ±15% 偏差
    i=min(int(u/2),31); return GAIN[i]*1.05 if u>=1 else 1.0

def gen(seed, secs=60, p_pair=0.5, p_cancel=0.08, tick=0.125):
    r=random.Random(seed)
    n=int(secs/0.008)
    # 硬件原始位移: 一段段平滑运动 + 偶尔快速甩动
    u=[];vx=vy=0
    tgt=(0,0);hold=0
    for i in range(n):
        if hold<=0:
            sp=r.choice([0,3,6,10,20,40]) ; ang=r.uniform(0,6.28)
            tgt=(sp*math.cos(ang),sp*math.sin(ang)); hold=r.randint(10,80)
        hold-=1
        vx+=(tgt[0]-vx)*0.3; vy+=(tgt[1]-vy)*0.3
        u.append((vx+r.gauss(0,0.4),vy+r.gauss(0,0.4)))
    acc=[]; truth=[]; px=py=0
    for (a,b) in u:
        m=math.hypot(a,b); g=true_gain(m)
        dx,dy=round(a*g),round(b*g)
        acc.append([dx,dy]); px+=dx;py+=dy; truth.append((px,py))
    # 污染注入
    flag=[0]*n
    t=0.0
    while t<secs:
        t+=tick*r.uniform(0.6,1.4)
        i=int(t/0.008)
        if i>=n-2: break
        while i<n-2 and (math.hypot(*u[i])<1 or math.hypot(*u[i+1])<1): i+=1   # 污染只会落在真有硬件位移的事件上(实测 u<1 的事件 acc 恒为 0)
        if i>=n-2: break
        D=(r.uniform(-900,900),r.uniform(-500,500))
        x=r.random()
        if x<p_pair:          # +D 落在事件 i, -D 落在 i+1
            acc[i][0]+=D[0];acc[i][1]+=D[1]; acc[i+1][0]-=D[0];acc[i+1][1]-=D[1]; flag[i]=flag[i+1]=1
        elif x<p_pair+p_cancel: # 位移被抵消: 事件 i 的位移变成 ~0
            acc[i]=[0,0]; flag[i]=1
        # 其余: +D 与 -D 同事件内抵消 => 干净
    return u,acc,truth,flag

def est_current(u,acc,gain,hi=1.6,lo=0.6,learn=0.03):
    g=list(gain); px=py=0; out=[]
    for (ux,uy),(dx,dy) in zip(u,acc):
        um=math.hypot(ux,uy); am=math.hypot(dx,dy); b=min(int(um/2),31)
        ex=um*g[b]
        if um>=1 and (am<lo*ex or am>hi*ex+3):
            dx,dy=ux*g[b],uy*g[b]
        elif um>=1:
            g[b]=g[b]*(1-learn)+(am/um)*learn
        px+=dx;py+=dy; out.append((px,py))
    return out
def est_drop(u,acc,gain):
    px=py=0;out=[]
    for (ux,uy),(dx,dy) in zip(u,acc):
        um=math.hypot(ux,uy); am=math.hypot(dx,dy)
        if am>60 and am>8*um+25: dx=dy=0
        px+=dx;py+=dy; out.append((px,py))
    return out
def est_model(u,acc,gain):
    px=py=0;out=[]
    for (ux,uy),(dx,dy) in zip(u,acc):
        m=math.hypot(ux,uy); g=gain[min(int(m/2),31)]
        px+=ux*g;py+=uy*g; out.append((px,py))
    return out
def est_raw(u,acc,gain):
    px=py=0;out=[]
    for _,(dx,dy) in zip(u,acc):
        px+=dx;py+=dy; out.append((px,py))
    return out
def score(est,truth):
    e=[math.hypot(a[0]-b[0],a[1]-b[1]) for a,b in zip(est,truth)]
    e.sort(); rms=math.sqrt(sum(x*x for x in e)/len(e))
    return round(rms,1),round(e[int(len(e)*.99)],1),round(e[-1],1)
if __name__=="__main__":
    for name,f in [("raw(旧)",est_raw),("drop(v2)",est_drop),("model",est_model),("current(v4)",est_current)]:
        res=[score(f(*gen(s)[:2],GAIN),gen(s)[2]) for s in range(5)]
        print(name,"rms/p99/max px:",res)
