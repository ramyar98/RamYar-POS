path='lib/services/app_localizations.dart'
with open(path,encoding='utf-8') as f:
    c=f.read()
s=c.find('Order delivery')
if s>=0:
    start=max(0,s-150)
    end=min(len(c), s+2200)
    with open('out.txt','w',encoding='utf-8') as out:
        out.write(c[start:end])
