from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
import io
import re
import soundfile as sf
import torch
from kokoro import KPipeline

app = FastAPI()

# Initialize the Kokoro pipeline (it will download weights on first run, ~300MB)
print("[TTS Server] Initializing Kokoro Pipeline...")
try:
    pipeline = KPipeline(lang_code='a')
    print("[TTS Server] Kokoro Pipeline initialized successfully.")
except Exception as e:
    print("[TTS Server] Error initializing pipeline: ", e)
    pipeline = None

_blend_cache: dict = {}

def resolve_voice(voice_str: str):
    if voice_str in _blend_cache:
        return _blend_cache[voice_str]
    if '+' not in voice_str:
        pack = pipeline.load_single_voice(voice_str)
        _blend_cache[voice_str] = pack
        return pack
    parts = voice_str.split('+')
    voices = []
    weights = []
    for part in parts:
        part = part.strip()
        m = re.match(r'^(.+?)\[([0-9.]+)\]$', part)
        if m:
            voices.append(m.group(1))
            weights.append(float(m.group(2)))
        else:
            voices.append(part)
            weights.append(1.0)
    total = sum(weights)
    weights = [w / total for w in weights]
    packs = [pipeline.load_single_voice(v) for v in voices]
    blended = sum(p * w for p, w in zip(packs, weights))
    _blend_cache[voice_str] = blended
    print(f"[TTS Server] Blended voice: {list(zip(voices, weights))}")
    return blended

@app.get("/health")
async def health_check():
    return {"status": "ok", "pipeline_ready": pipeline is not None}

@app.post("/tts")
async def text_to_speech(data: dict):
    if pipeline is None:
        raise HTTPException(status_code=500, detail="Kokoro pipeline not initialized")
        
    text = data.get("text", "")
    voice = data.get("voice", "af_bella")
    speed = data.get("speed", 1.0)
    
    if not text:
        raise HTTPException(status_code=400, detail="Text cannot be empty")
        
    print(f"[TTS Server] Generating speech for text: '{text}' using voice: '{voice}'")
    try:
        voice_pack = resolve_voice(voice)
        generator = pipeline(text, voice=voice_pack, speed=speed, split_pattern=r'\n+')
        for _, _, audio in generator:
            wav_io = io.BytesIO()
            # Kokoro sample rate is 24000Hz
            sf.write(wav_io, audio, 24000, format='WAV', subtype='PCM_16')
            wav_io.seek(0)
            return Response(content=wav_io.read(), media_type="audio/wav")
    except Exception as e:
        print("[TTS Server] Error during generation: ", e)
        raise HTTPException(status_code=500, detail=str(e))
        
    raise HTTPException(status_code=500, detail="Failed to generate audio")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=5000)
