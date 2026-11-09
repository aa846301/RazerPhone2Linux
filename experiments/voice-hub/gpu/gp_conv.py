"""List per-call Convolution (GEMV) times of one decode token from an MNN_GPU_TIME_PROFILE log,
grouped by time bucket, and estimate the fixed per-call cost against the measured 24.1 GB/s ceiling."""
import collections, re, sys

lines = open(sys.argv[1], encoding='utf-8', errors='replace').read().splitlines()
blocks, cur = [], []
for l in lines:
    m = re.match(r'kernel time = (\d+)\s+us (.*)', l)
    if m:
        cur.append((m.group(2).strip(), int(m.group(1))))
    elif l.startswith('total kernel time'):
        blocks.append(cur)
        cur = []
dec = [b for b in blocks[-30:] if sum(t for _, t in b) > 30000]
b = dec[-1]
convs = [t for n, t in b if n.startswith('Convolution')]
print(f'decode block: {len(b)} kernels, {sum(t for _, t in b) / 1000:.1f} ms; Convolution calls {len(convs)}, {sum(convs) / 1000:.1f} ms')
hist = collections.Counter(convs)
for t, c in sorted(hist.items()):
    print(f'  {t:6d} us x {c}')
