from pathlib import Path
import ast, re, html, json, hashlib
ROOT=Path(__file__).resolve().parents[1]
import argparse
arguments=argparse.ArgumentParser();arguments.add_argument('--source',type=Path,required=True);SOURCE=arguments.parse_args().source
def tokens(text):
    out=[]; i=0
    while i<len(text):
        if text[i].isspace(): i+=1; continue
        if text.startswith('//',i):
            j=text.find('\n',i); i=len(text) if j<0 else j+1; continue
        if text.startswith('/*',i):
            j=text.find('*/',i+2); assert j>=0; i=j+2; continue
        if text[i] in "'\"":
            q=text[i]; j=i+1
            while j<len(text):
                if text[j]=='\\': j+=2; continue
                if text[j]==q: break
                j+=1
            assert j<len(text)
            out.append(('str',ast.literal_eval(text[i:j+1]))); i=j+1; continue
        m=re.match(r'[A-Za-z_][A-Za-z_0-9]*',text[i:])
        if m: out.append(('id',m[0])); i+=len(m[0]); continue
        out.append(('sym',text[i])); i+=1
    return out

def parse_sections(text,constant,section_type,paragraph_type=None):
    ts=tokens(text); i=next(k for k,t in enumerate(ts) if t==('id',constant))+1
    def eat(value):
        nonlocal i
        assert ts[i][1]==value,(i,ts[i],value)
        i+=1
    def literal():
        nonlocal i
        result=''
        while ts[i][0]=='str': result+=ts[i][1]; i+=1
        assert result
        return result
    eat('='); eat('['); sections=[]
    while ts[i][1]!=']':
        eat(section_type); eat('('); title=literal(); eat(','); eat('['); ps=[]
        while ts[i][1]!=']':
            emphasized=False
            if paragraph_type: eat(paragraph_type); eat('(')
            value=literal()
            if paragraph_type:
                if ts[i][1]==',':
                    i+=1
                    if ts[i][1]=='emphasized':
                        eat('emphasized'); eat(':'); emphasized=ts[i][1]=='true'; i+=1
                        if ts[i][1]==',': i+=1
                eat(')')
            ps.append({'text':value,'emphasized':emphasized})
            if ts[i][1]==',':i+=1
        eat(']'); eat(')')
        sections.append({'title':title,'paragraphs':ps})
        if ts[i][1]==',':i+=1
    return sections

docs=[('privacy_policy_content.dart','kPrivacyPolicyZh','LegalSection','LegalParagraph','privacy.html','隐私政策'),('user_agreement_content.dart','kUserAgreementZh','LegalSection','LegalParagraph','terms.html','用户协议'),('platform_rules_content.dart','kPlatformRulesZh','RuleSection',None,'community-rules.html','平台公约')]
nav=''.join(f'<a href="{name}">{title}</a>'for _,_,_,_,name,title in docs)
manifest=[]
for file,constant,stype,ptype,name,title in docs:
 source=(SOURCE/file).read_text();sections=parse_sections(source,constant,stype,ptype);body=[]
 for i,section in enumerate(sections):
  paragraphs=[]
  for p in section['paragraphs']:
   text=html.escape(p['text'].replace('方寸间','窗后城'))
   if p['emphasized']:text='<strong>'+text+'</strong>'
   paragraphs.append('<p>'+text+'</p>')
  body.append('<section><h2>'+html.escape(section['title'])+'</h2>'+''.join(paragraphs)+'</section>')
 text=f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>窗后城{title}｜北京空也科技有限公司</title><link rel="stylesheet" href="styles.css"></head><body class="legal-page"><header class="legal-header wrap"><a class="brand" href="index.html">窗后城</a><a href="index.html#legal-docs">返回社区</a></header><main class="legal-wrap"><h1>窗后城{title}</h1><p class="legal-meta">V1.1 · 生效日期：2026年11月2日</p><p>本页公布窗后城 App 的{title}。公开发布作品前，请同时阅读<a href="publication-notice.html">三维作品发布与审核说明</a>。</p><nav class="legal-doc-nav">{nav}</nav><article class="legal-content">{''.join(body)}</article><div class="legal-contact"><p>北京空也科技有限公司</p><a href="mailto:wkd20040211@163.com">wkd20040211@163.com</a></div></main></body></html>'''
 (ROOT/'docs'/name).write_text(text);manifest.append({'file':name,'source_sha256':hashlib.sha256((SOURCE/file).read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(text.encode()).hexdigest(),'sections':len(sections),'paragraphs':sum(len(s['paragraphs'])for s in sections),'transformation':'existing App content; product name 方寸间→窗后城, formal publication metadata'})
(ROOT/'legal-publication-manifest-20261102.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print('exported',len(manifest),'existing App documents')
