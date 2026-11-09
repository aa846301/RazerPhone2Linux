import re,sys,collections
lines=open(sys.argv[1],encoding='utf-8',errors='replace').read().splitlines()
blocks=[];cur=[]
for l in lines:
    m=re.match(r'kernel time = (\d+)\s+us (.*)',l)
    if m: cur.append((m.group(2).strip(),int(m.group(1))))
    elif l.startswith('total kernel time'): blocks.append(cur);cur=[]
dec=[b for b in blocks[-30:] if sum(t for _,t in b)>20000]
b=dec[-1]
convs=[t for n,t in b if n.startswith('Convolution')]
print('conv calls',len(convs))
# per-layer pattern: print first 40 conv times
print(convs[:40])
hist=collections.Counter((t//25)*25 for t in convs)
print('histogram (us bucket: count):',sorted(hist.items()))
print('time in convs <80us:',sum(t for t in convs if t<80),'us over',sum(1 for t in convs if t<80),'calls')
print('time in convs 80-200us:',sum(t for t in convs if 80<=t<200),'us over',sum(1 for t in convs if 80<=t<200),'calls')
print('time in convs >=200us:',sum(t for t in convs if t>=200),'us over',sum(1 for t in convs if t>=200),'calls')
fl=[t for n,t in b if 'flash' in n]; print('flash',fl)
