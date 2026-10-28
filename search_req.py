import os
for root, dirs, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            p = os.path.join(root,f)
            try:
                with open(p, encoding='utf-8') as fh:
                    txt = fh.read()
                if 'داوای پارەی' in txt or 'داوای حیسابی' in txt or 'پارەی کردووە' in txt or 'حیسابی کردووە' in txt:
                    print(p)
            except:
                pass
