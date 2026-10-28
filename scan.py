path='lib/services/app_localizations.dart'
with open(path,encoding='utf-8') as f:
    c=f.read()
i=c.find('Order delivery')
if i>=0:
    j=c.find('\n  // =====', i+100)
    if j==-1: j=i+1500
    print(c[i:j])
