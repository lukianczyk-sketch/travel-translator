"""Runs on CI: probes the NLLB ONNX decoder to find the correct first-step
input shapes, and dumps input/output names. Results go to buildlogs/nllb_probe.log."""
import json, os, sys, time, urllib.request
import numpy as np
import onnxruntime as ort

BASE = "https://huggingface.co/Xenova/nllb-200-distilled-600M/resolve/main"
os.makedirs("probe", exist_ok=True)
def get(name, dst):
    if not os.path.exists(dst):
        print("downloading", name, flush=True)
        urllib.request.urlretrieve(f"{BASE}/{name}", dst)
get("onnx/encoder_model_quantized.onnx", "probe/enc.onnx")
get("onnx/decoder_model_merged_quantized.onnx", "probe/dec.onnx")
get("tokenizer.json", "probe/tokenizer.json")

out = []
def log(*a):
    s = " ".join(str(x) for x in a); print(s, flush=True); out.append(s)

enc = ort.InferenceSession("probe/enc.onnx", providers=["CPUExecutionProvider"])
dec = ort.InferenceSession("probe/dec.onnx", providers=["CPUExecutionProvider"])
log("ENC inputs:", [(i.name, i.shape, i.type) for i in enc.get_inputs()])
log("ENC outputs:", [(o.name, o.shape) for o in enc.get_outputs()])
log("DEC inputs:", [(i.name, i.shape, i.type) for i in dec.get_inputs()][:8], "... total", len(dec.get_inputs()))
log("DEC outputs:", [(o.name, o.shape) for o in dec.get_outputs()][:6], "... total", len(dec.get_outputs()))

from tokenizers import Tokenizer
tok = Tokenizer.from_file("probe/tokenizer.json")
tj = json.load(open("probe/tokenizer.json"))
log("tokenizer model type:", tj["model"]["type"], "| merges sample:", str(tj["model"].get("merges", [])[:3]))
log("normalizer:", json.dumps(tj.get("normalizer"))[:300])
log("pre_tokenizer:", json.dumps(tj.get("pre_tokenizer"))[:300])
log("post_processor:", json.dumps(tj.get("post_processor"))[:400])
lang = {t["content"]: t["id"] for t in tj.get("added_tokens", [])}
log("eng_Latn id:", lang.get("eng_Latn"), "pol_Latn id:", lang.get("pol_Latn"), "</s>:", lang.get("</s>"))

text = "Czy ten pociąg jedzie do Krakowa?"
ids = [lang["pol_Latn"]] + tok.encode(text, add_special_tokens=False).ids + [2]
log("input ids:", ids)
ids_np = np.array([ids], dtype=np.int64)
mask = np.ones_like(ids_np)
hidden = enc.run(None, {"input_ids": ids_np, "attention_mask": mask})[0]
log("encoder hidden:", hidden.shape, hidden.dtype)

past_names = [i.name for i in dec.get_inputs() if i.name.startswith("past_key_values.")]
out_names = [o.name for o in dec.get_outputs()]

def step0(seq_len):
    feeds = {
        "input_ids": np.array([[2, lang["eng_Latn"]]], dtype=np.int64),
        "encoder_attention_mask": mask,
        "encoder_hidden_states": hidden,
        "use_cache_branch": np.array([False]),
    }
    for n in past_names:
        feeds[n] = np.zeros((1, 16, seq_len, 64), dtype=np.float32)
    return dec.run(None, feeds)

for seq_len in (1, 0):
    try:
        t = time.time(); outs = step0(seq_len)
        log(f"step0 with dummy past seq_len={seq_len}: OK in {time.time()-t:.2f}s; logits {outs[0].shape}")
        pres = {n: o.shape for n, o in zip(out_names, outs) if n.startswith("present.")}
        log("  present shapes sample:", list(pres.items())[:4])
        ok_len = seq_len; ok_outs = outs
        break
    except Exception as e:
        log(f"step0 with dummy past seq_len={seq_len}: FAILED: {str(e)[:300]}")

# full greedy decode using cache branch
gen = []
outs = ok_outs
past = {}
for n, o in zip(out_names, outs):
    if n.startswith("present."):
        past["past_key_values." + n[len("present."):]] = o
nxt = int(np.argmax(outs[0][0, -1]))
t = time.time()
for step in range(60):
    if nxt == 2: break
    gen.append(nxt)
    feeds = {"input_ids": np.array([[nxt]], dtype=np.int64), "encoder_attention_mask": mask,
             "encoder_hidden_states": hidden, "use_cache_branch": np.array([True])}
    for n in past_names: feeds[n] = past[n]
    outs = dec.run(None, feeds)
    for n, o in zip(out_names, outs):
        if n.startswith("present."):
            past["past_key_values." + n[len("present."):]] = o
    nxt = int(np.argmax(outs[0][0, -1]))
log(f"greedy decode: {len(gen)} tokens in {time.time()-t:.2f}s")
log("decoded:", tok.decode(gen, skip_special_tokens=True))
os.makedirs("buildlogs", exist_ok=True)
open("buildlogs/nllb_probe.log", "w").write("\n".join(out))
