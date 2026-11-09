import re,sys,collections
lines=open(sys.argv[1],encoding='utf-8',errors='replace').read().splitlines()
blocks=[];cur=[]
for l in lines:
    m=re.match(r'kernel time = (\d+)\s+us (.*)',l)
    if m: cur.append((m.group(2).strip(),int(m.group(1))))
    elif l.startswith('total kernel time'):
        blocks.append(cur);cur=[]
last=blocks[-30:]  # 10 tokens x 3 blocks
dec=[b for b in last if sum(t for _,t in b)>30000]
head=[b for b in last if 3000<sum(t for _,t in b)<20000]
def agg(bs,label):
    n=len(bs); d=collections.defaultdict(lambda:[0,0])
    for b in bs:
        for name,t in b:
            key=re.sub(r'\d+','#',name)[:60]
            d[key][0]+=t; d[key][1]+=1
    tot=sum(v[0] for v in d.values())/n
    print(f'== {label}: {n} samples, avg GPU time per token {tot/1000:.1f} ms, kernels per token {sum(v[1] for v in d.values())/n:.0f}')
    for k,(t,c) in sorted(d.items(),key=lambda x:-x[1][0])[:12]:
        print(f'  {t/n/1000:6.2f} ms  {c/n:5.0f} calls  avg {t/c:7.1f} us  {k}')
agg(dec,'decoder layers block'); agg(head,'lm_head block')
for b in head[:1]: print('lm_head kernels:',[(n,t) for n,t in b][:6])

