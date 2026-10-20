#!/usr/bin/env python3
"""Link the first prose reference of each model on every public page to its Hugging Face model card.
Idempotent; skips code fences, inline code, headings, front matter and text that is already a link.
usage: link_models.py [--check]"""
import glob, os, re, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HF = "https://huggingface.co/"
MODELS = [  # (alias regex, card)
 (r"Nemotron[ -]3\.5[ -]Super[ -]VL", "nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4"),
 (r"Nemotron[ -]3\.5[ -]Lightning(?:-30B-A3B)?", "nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4"),
 (r"Qwen3\.8[ -]27B", "nvidia/Qwen3.8-27B-NVFP4"),
 (r"Qwen3\.8-Flash-Next", "nvidia/Qwen3.8-Flash-Next-NVFP4"),
 (r"GLM-5\.3-Flash", "RedHatAI/GLM-5.3-Flash-NVFP4"),
 (r"Nemotron 3 Nano Omni", "nvidia/nemotron-3-nano-omni-30b-a3b"),
 (r"Gemma 4 26B A4B", "google/gemma-4-26B-A4B-it"),
 (r"Gemma 4 31B", "google/gemma-4-31B-it"),
]
PAGES = ["README.md", "recipes/README.md", "monitoring/README.md", "tests/README.md"] + \
        [p for p in glob.glob("docs/*.md") if "template-standard" not in p] + glob.glob("solutions/**/*.md", recursive=True)
LINK = re.compile(r"\[[^\]]*\]\([^)]*\)")
CODE = re.compile(r"`[^`]*`")

def process(text):
    fm = re.match(r"\A---\n.*?\n---\n", text, re.S)
    head, body = (fm.group(0), text[fm.end():]) if fm else ("", text)
    done = set(); out = []; fence = False
    for line in body.split("\n"):
        if line.lstrip().startswith("```"): fence = not fence; out.append(line); continue
        if fence or line.startswith("#"): out.append(line); continue
        # protect links and code spans, remember them
        keep = []
        def stash(m): keep.append(m.group(0)); return "\x00%d\x00" % (len(keep) - 1)
        tmp = CODE.sub(stash, LINK.sub(stash, line))
        # a model that already appears inside a link on its first reference counts as linked
        for pat, card in MODELS:
            if pat in done: continue
            for k in keep:
                if k.startswith("[") and re.search(pat, k) and "huggingface.co/" in k: done.add(pat); break
        for pat, card in MODELS:
            if pat in done: continue
            m = re.search(pat, tmp)
            if m:
                tmp = tmp[:m.start()] + "[%s](%s%s)" % (m.group(0), HF, card) + tmp[m.end():]
                done.add(pat)
        out.append(re.sub(r"\x00(\d+)\x00", lambda m: keep[int(m.group(1))], tmp))
    return head + "\n".join(out)

changed = []
for rel in sorted(set(PAGES)):
    p = os.path.join(ROOT, rel)
    if not os.path.exists(p): continue
    s = open(p, encoding="utf-8").read(); n = process(s)
    if n != s:
        changed.append(rel)
        if "--check" not in sys.argv: open(p, "w", encoding="utf-8").write(n)
print("\n".join(changed)); print(len(changed), "pages", "need links" if "--check" in sys.argv else "updated")
sys.exit(1 if ("--check" in sys.argv and changed) else 0)
