import json, re, sys, time, urllib.request
from pathlib import Path

OUT = Path(__file__).with_name("lounge_curated_100.json")
MODEL = "qwen3:4b"
SCENARIOS = [
 ("Jenna Kross","Mechanic","A run of ships arrived with intake filters clogged by an unidentified residue. Customs is holding arrivals until they know it is contained.","Why are customs inspections so strict today?"),
 ("Ivet Marr","Cargo Inspector","A freight convoy missed its check-in. Nobody knows whether it broke down, diverted, or was intercepted.","What happened to the missing convoy?"),
 ("Marek Vale","Dockworker","Fuel deliveries are late and the station has begun rationing nonessential service craft.","How bad is the fuel shortage?"),
 ("Sana Rell","Bartender","Freight crews are waiting on inspection clearance, leaving cargo sitting on docks.","What is holding up the freight runs?"),
]
BAD = ("hey", "listen", "pilot's question", "so, you're asking", "you're asking", "i've got the latest")

def generate(name, role, facts, question, index):
    prompt = f'''Write a natural PG-13 lounge exchange. Speaker: {name}, {role}, at Greywake Station.
Allowed facts (use only these; do not invent names, places, events, science, or causes): {facts}
Pilot question: "{question}"
Return only JSON {{"opener":"...","answer":"...","close":"..."}}.
The opener must be a complete, spontaneous human remark, not "Hey", not a question repeat, and not an interruption. Answer directly using only allowed facts. Close naturally without "So yeah".'''
    body=json.dumps({"model":MODEL,"prompt":prompt,"stream":False,"format":"json","think":False,"options":{"temperature":0.65,"num_predict":150,"seed":9000+index}}).encode()
    req=urllib.request.Request("http://127.0.0.1:11434/api/generate",data=body,headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req,timeout=75) as response: return json.loads(json.loads(response.read())["response"])

def review(data, question):
    opener=str(data.get("opener","")).strip(); answer=str(data.get("answer","")).strip(); close=str(data.get("close","")).strip(); lower=opener.lower()
    reasons=[]
    if not all((opener,answer,close)): reasons.append("missing field")
    if lower.startswith(BAD) or opener.endswith(("-","—")): reasons.append("unnatural opener")
    if "so yeah" in close.lower(): reasons.append("stock close")
    if len(answer)<20: reasons.append("thin answer")
    return ("auto_pass" if not reasons else "needs_rewrite"), reasons

target=int(sys.argv[1]) if len(sys.argv)>1 else 100
items=json.loads(OUT.read_text()).get("items",[]) if OUT.exists() else []
for i in range(len(items),target):
    name,role,facts,question=SCENARIOS[i%len(SCENARIOS)]
    record={"id":f"curated-{i+1:03d}","contact_name":name,"contact_role":role,"station":"Greywake Station","allowed_facts":facts,"player_question":question,"attempts":[]}
    for attempt in range(2):
        try:
            text=generate(name,role,facts,question,i*2+attempt); verdict,reasons=review(text,question)
            record["attempts"].append({"text":text,"verdict":verdict,"reasons":reasons})
            if verdict=="auto_pass": break
        except Exception as error: record["attempts"].append({"error":str(error),"verdict":"needs_human","reasons":["generation failure"]})
    chosen=record["attempts"][-1]; text=chosen.get("text",{})
    record.update({"opener":text.get("opener",""),"npc_answer":text.get("answer",""),"close":text.get("close",""),"review_verdict":chosen["verdict"],"review_reasons":chosen["reasons"]})
    items.append(record)
    OUT.write_text(json.dumps({"batch_id":"lounge-curated-100","items":items},indent=2),encoding="utf-8")
    print(f"checkpoint {len(items)}/{target}",flush=True)
print(f"Done: {len(items)} items",flush=True)
