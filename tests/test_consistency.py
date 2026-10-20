#!/usr/bin/env python3
"""Consistency/traceability tests for sizing data, recipes and monitoring.
Run:  python3 -m pytest tests/test_consistency.py -q   (or python3 tests/test_consistency.py)
GPU/Docker are NOT required; recipe --dry-run is used. See also tests/test_recipe_contract.sh."""
import glob, json, os, re, subprocess, sys, unittest
import yaml
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SIZING = yaml.safe_load(open(os.path.join(ROOT, "tests/data/latest/sizing.yaml")))
RECIPES = sorted(glob.glob(os.path.join(ROOT, "recipes/*/vllm/docker-*.sh")))

class SizingData(unittest.TestCase):
    def test_every_doc_ref_still_present(self):
        missing = []
        for f in SIZING["facts"]:
            for r in f.get("doc_refs", []):
                txt = open(os.path.join(ROOT, r["file"]), encoding="utf-8").read()
                if r["text"] not in txt: missing.append((f["id"], r["file"], r["text"]))
        self.assertEqual(missing, [], "doc text drifted from sizing.yaml: update the doc or the data file")
    def test_status_vocabulary(self):
        ok = {"measured-imported", "doc-reported", "spot-check", "retired-model", "pending"}
        for f in SIZING["facts"]: self.assertIn(f["status"], ok, f["id"])
    def test_imported_ladder_is_monotonic_in_per_session(self):
        d = json.load(open(os.path.join(ROOT, "tests/data/latest/gb300_lightning_ladders_imported.json")))
        for shape, l in d["ladders"].items():
            per = [p["per_session_tok_s"] for p in l["points"]]
            for p in l["points"]:   # convention: per_session == aggregate / C
                self.assertAlmostEqual(p["aggregate_tok_s"] / p["c"], p["per_session_tok_s"], delta=0.02 * p["per_session_tok_s"] + 0.05)
class Recipes(unittest.TestCase):
    def test_recipes_syntax_and_contract(self):
        self.assertEqual(len(RECIPES), 8)
        for r in RECIPES:
            with self.subTest(r=r):
                subprocess.run(["bash", "-n", r], check=True)
                src = open(r).read()
                self.assertIn("lib/common.sh", src); self.assertIn("ds_finish", src); self.assertIn("ds_common_flag", src)
                self.assertNotIn("docker run -d", src.replace("ds_docker run -d", ""))   # all launches go through ds_docker
                health = os.path.join(os.path.dirname(r), "health-" + os.path.basename(r)[len("docker-"):])
                self.assertTrue(os.access(health, os.X_OK), health)
                subprocess.run(["bash", "-n", health], check=True)
    def test_dry_run_exits_zero_and_prints_run(self):
        for r in RECIPES:
            if "gb300" in r and subprocess.run("nvidia-smi --query-gpu=name --format=csv,noheader | grep -q GB300", shell=True).returncode:
                continue    # UUID auto-detect needs a GB300 (or NEMOTRON_LIGHTNING_GPU_UUID/GLM53_GPU_UUID)
            p = subprocess.run([r, "--dry-run", "--no-monitoring"], capture_output=True, text=True, env={**os.environ, "HF_TOKEN": "hf_TESTSECRET"})
            self.assertEqual(p.returncode, 0, r + p.stderr)
            self.assertIn("[dry-run] docker run -d", p.stdout); self.assertNotIn("TESTSECRET", p.stdout)
    def test_unknown_flag_is_usage_error_3(self):
        self.assertEqual(subprocess.run([RECIPES[0], "--nope"], capture_output=True).returncode, 3)

class DocsSite(unittest.TestCase):
    def test_generated_html_is_current(self):
        p = subprocess.run([sys.executable, os.path.join(ROOT, "scripts/docs/regen.py"), "--check"], capture_output=True, text=True, cwd=ROOT)
        self.assertEqual(p.returncode, 0, "docs HTML is stale: run python3 scripts/docs/regen.py\n" + p.stdout)

class ModelLinks(unittest.TestCase):
    def test_first_model_reference_on_every_page_is_linked(self):
        p = subprocess.run([sys.executable, os.path.join(ROOT, "scripts/docs/link_models.py"), "--check"], capture_output=True, text=True, cwd=ROOT)
        self.assertEqual(p.returncode, 0, "run python3 scripts/docs/link_models.py\n" + p.stdout)
    def test_no_interim_or_revalidation_wording_in_public_docs(self):
        import glob
        for f in glob.glob(os.path.join(ROOT, "docs/*.md")) + glob.glob(os.path.join(ROOT, "solutions/**/*.md"), recursive=True) + [os.path.join(ROOT, "README.md"), os.path.join(ROOT, "recipes/README.md")]:
            if "template-standard" in f: continue
            t = open(f).read().lower()
            self.assertNotIn("interim", t, f); self.assertNotIn("revalidation", t, f)

class Highlighter(unittest.TestCase):
    def test_highlight_js_unit_tests(self):
        import shutil
        if not shutil.which("node"): self.skipTest("node not installed")
        for f in ("docs/assets/highlight.js", "docs/assets/picker.js"):
            self.assertEqual(subprocess.run(["node", "--check", os.path.join(ROOT, f)]).returncode, 0, f)
        p = subprocess.run(["node", os.path.join(ROOT, "tests/js/highlight_test.js")], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
    def test_it_guide_covers_all_five_platforms(self):
        t = open(os.path.join(ROOT, "solutions/agentic-coding/it-admin-guide.md")).read()
        for h in ("### GB10 (S)", "### Precision T2 (S, x86)", "### Precision T4 (M) and T6 (L)", "### GB300 (L)"):
            self.assertIn(h, t)
        pj = open(os.path.join(ROOT, "docs/assets/picker.js")).read()
        for name in ("GB10", "T2", "T4", "T6", "GB300"): self.assertIn(name, pj)

class LandscapeGuides(unittest.TestCase):
    def test_every_solution_has_a_landscape_guide_and_scripts(self):
        for sol in ("agentic-coding", "agentic-vss", "openclaw-on-nemoclaw", "hermes-on-nemoclaw", "higher-ed-ai-lab"):
            self.assertTrue(os.path.exists(os.path.join(ROOT, "solutions", sol, "landscape-fleet-deploy.md")), sol)
        for sc in ("deploy-solution.sh", "reset-seat.sh", "disable-script-execution.sh", "deploy-serving-recipe.sh"):
            self.assertEqual(subprocess.run(["bash", "-n", os.path.join(ROOT, "scripts/landscape", sc)]).returncode, 0, sc)

class Measured(unittest.TestCase):
    def test_measured_json_is_current(self):
        p = subprocess.run([sys.executable, os.path.join(ROOT, "scripts/docs/build_measured.py"), "--check"], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, "run python3 scripts/docs/build_measured.py")

class Monitoring(unittest.TestCase):
    def test_alert_rules_unit_tests_pass_promtool(self):
        if subprocess.run("docker image inspect prom/prometheus:v2.53.1", shell=True, capture_output=True).returncode:
            self.skipTest("prometheus image not present")
        p = subprocess.run(["docker", "run", "--rm", "--entrypoint", "promtool", "-v", ROOT + "/monitoring:/m:ro", "-w", "/m",
                            "prom/prometheus:v2.53.1", "test", "rules", "alerts.test.yml"], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
    def test_versions_lock_resolves_every_recipe_id(self):
        for rid in ("lightning", "qwen27b", "flashnext", "glm53", "supervl", "litellm"):
            out = subprocess.run(["bash", "-c", f"source {ROOT}/recipes/lib/common.sh; ds_image {rid}"], capture_output=True, text=True)
            self.assertEqual(out.returncode, 0, rid); self.assertTrue(out.stdout.strip(), rid)
    def test_port_scheme_defaults_to_8000(self):
        for r in RECIPES:
            src = open(r).read(); self.assertIn("ds_pick_port", src, r); self.assertNotRegex(src, r'PORT="\$\{[A-Z0-9_]+:-80[3-9]\d\}"')
    def test_dashboard_template_valid(self):
        t = open(os.path.join(ROOT, "monitoring/tokenomics.dashboard.template.json")).read()
        d = json.loads(t)
        self.assertGreaterEqual(len(d["panels"]), 14)
        self.assertEqual(set(re.findall(r"__[A-Z_]+__", t)), {"__SYSTEM_PRICE__", "__AMORT_MONTHS__", "__WATTS__", "__KWH__"})
        for p in d["panels"]:
            for tg in p["targets"]:
                self.assertNotIn("prompt", tg["expr"].lower().replace("prompt_tokens", ""))   # economics only, no payload
        # cloud comparison is driven by the model picker at the top of the dashboard
        v = d["templating"]["list"][0]
        self.assertEqual((v["name"], v["label"]), ("cloud_model", "compare against"))
        self.assertIn("deskside:cloud_price_in_usd_per_m", v["query"]["query"])
        y = open(os.path.join(ROOT, "monitoring/model-prices.yml")).read()
        self.assertEqual(set(re.findall(r"__[A-Z_]+__", y)), {"__CLOUD_IN__", "__CLOUD_OUT__"})
        self.assertIn("interval: 1m", y)   # static prices must stay inside Grafana's label_values lookback
        for m in ("OpenAI GPT Terra", "OpenAI GPT Luna", "Anthropic Claude Sonnet", "Anthropic Claude Haiku", "Custom (from deploy env)"):
            self.assertIn(f'labels: {{model: "{m}"}}', y)
        self.assertEqual(v["current"]["value"], "OpenAI GPT Terra")   # picker default
class HeadlessNemoclaw(unittest.TestCase):
    """Hash-pinned fetch, no prompts, explicit human hand-off."""
    def run_phase(self, phase, pin=None, extra=()):
        import tempfile, hashlib
        d = tempfile.mkdtemp(); f = os.path.join(d, "inst.sh"); open(f, "w").write("#!/bin/bash\necho installer-ran\n")
        env = {**os.environ, "NEMOCLAW_INSTALLER_URL": "file://" + f, "NEMOCLAW_WORKDIR": d}
        env.pop("NEMOCLAW_INSTALLER_SHA256", None)
        if pin == "good": env["NEMOCLAW_INSTALLER_SHA256"] = hashlib.sha256(open(f, "rb").read()).hexdigest()
        elif pin: env["NEMOCLAW_INSTALLER_SHA256"] = pin
        return subprocess.run([os.path.join(ROOT, "scripts/nemoclaw/headless-install.sh"), phase, *extra], capture_output=True, text=True, env=env)
    def test_unpinned_refused(self): self.assertEqual(self.run_phase("fetch").returncode, 11)
    def test_mismatch_refused(self): self.assertEqual(self.run_phase("fetch", pin="0" * 64).returncode, 11)
    def test_pinned_ok(self): self.assertEqual(self.run_phase("fetch", pin="good").returncode, 0)
    def test_install_hands_off_to_human(self):
        p = self.run_phase("install", pin="good"); self.assertEqual(p.returncode, 10); self.assertIn("human-step-required", p.stdout)
    def test_wire_dry_run(self): self.assertEqual(self.run_phase("wire", extra=("--dry-run",)).returncode, 0)

class ClientLimits(unittest.TestCase):
    def test_limits_never_exceed_window(self):
        for n in (4096, 65536, 70000, 131072, 200000, 262144):
            out, prompt = map(int, subprocess.run(["bash", "-c", f"source {ROOT}/recipes/lib/common.sh; ds_client_limits {n}"], capture_output=True, text=True).stdout.split())
            self.assertLessEqual(out + prompt + 1024, n if n > 1536 else 10**9); self.assertGreaterEqual(out, 512); self.assertLessEqual(out, 16384)
    def test_ide_doc_table_matches_recipe_windows(self):
        doc = open(os.path.join(ROOT, "solutions/agentic-coding/ide-integration.md")).read()
        for r in RECIPES:
            src = open(r).read(); m = re.search(r'MAX_MODEL_LEN="\$\{[A-Z0-9_]+:-(\d+)\}"', src) or re.search(r':=(\d+)\}" "\$\{MAX_NUM_SEQS', src) or re.search(r'--max-model-len (\d+)', src)
            self.assertIsNotNone(m, r); self.assertTrue(m.group(1) in doc.replace(",", ""), "window %s of %s missing from ide-integration.md" % (m.group(1), os.path.basename(r)))

class Topology(unittest.TestCase):
    def _ladder(self, d, pts):
        import json, tempfile
        f = os.path.join(d, "l%d.json" % len(os.listdir(d))); json.dump({"ladders": {"s": {"platform": "x", "points": [{"c": c, "per_session_tok_s": p} for c, p in pts]}}}, open(f, "w")); return f
    def run_cmp(self, a, b, floor=20, extra=()):
        import tempfile, json
        d = tempfile.mkdtemp(); fa, fb = self._ladder(d, a), self._ladder(d, b)
        p = subprocess.run([sys.executable, os.path.join(ROOT, "tests/aiperf/compare-topologies.py"), fa, fb, "--shape", "s", "--floor", str(floor), "--names", "TP", "DP", *extra], capture_output=True, text=True)
        return json.loads(p.stdout)
    def test_dp_wins_when_clearly_better(self):
        r = self.run_cmp([(1, 80), (8, 40), (16, 10), (32, 4)], [(1, 70), (8, 60), (16, 40), (32, 8), (64, 3)]); self.assertEqual(r["choice"], "DP")
    def test_tie_prefers_simpler(self):
        r = self.run_cmp([(1, 80), (8, 40), (16, 10), (32, 4)], [(1, 80), (8, 41), (16, 10), (32, 4)]); self.assertEqual(r["choice"], "TP")
    def test_exhausted_ladder_cannot_win(self):
        r = self.run_cmp([(1, 80), (8, 60), (16, 50)], [(1, 80), (8, 40), (16, 10)]); self.assertIsNone(r["choice"])

if __name__ == "__main__":
    unittest.main()
