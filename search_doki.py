import os
for root, dirs, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            p = os.path.join(root,f)
            try:
                with open(p, encoding='utf-8') as fh:
                    txt = fh.read()
                if 'دۆخی ناردنی داواکاری' in txt:
                    print('EXACT1', p)
                if 'دۆخی ناردنی' in txt and 'دۆخی ناردنی داواکاری' not in txt:
                    print('EXACT2', p)
            except:
                pass
