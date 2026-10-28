import os
for root, dirs, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            p = os.path.join(root,f)
            try:
                with open(p, encoding='utf-8') as fh:
                    d = fh.read()
                if '????? ?????' in d or '????? ??????' in d or '???? ??????' in d:
                    print(p)
                    break
            except:
                pass
