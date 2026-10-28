import os
for root, dirs, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            p = os.path.join(root,f)
            try:
                with open(p, encoding='utf-8') as fh:
                    txt = fh.read()
                if 'قەرز' in txt and 'دارایی' in txt:
                    print(p)
            except:
                pass
