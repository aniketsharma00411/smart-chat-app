import os
import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional
from google import genai
from google.genai import types
from dotenv import load_dotenv
import json

load_dotenv()

app = FastAPI(title="Smart Chat Gateway API")

# Configuration
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
GEMINI_MODEL_NAME = os.getenv("GEMINI_MODEL_NAME", "gemini-3-flash-preview")

if not GEMINI_API_KEY:
    print("WARNING: GEMINI_API_KEY not set. AI features will fail.")

# Helper to get client
def get_gemini_client():
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="Server misconfigured: Missing API Key")
    return genai.Client(api_key=GEMINI_API_KEY)

# Data Models
class ToneRequest(BaseModel):
    text: str
    conversation_history: Optional[List[str]] = []

class ToneResponse(BaseModel):
    tone: str
    reason: Optional[str] = None

class TranslateRequest(BaseModel):
    text: str
    target_language: str

class TranslateResponse(BaseModel):
    translation: str
    detected_source_language: Optional[str] = None

@app.post("/api/tone", response_model=ToneResponse)
async def analyze_tone(request: ToneRequest):
    client = get_gemini_client()
    
    # Contextual tone analysis
    history_context = ""
    if request.conversation_history:
        history_context = f"Previous conversation:\n" + "\n".join(request.conversation_history)

    prompt = f"""
    You are an expert communication coach. Analyze the tone of the upcoming message.
    {history_context}
    
    Message to analyze: "{request.text}"
    
    Return JSON only:
    {{
        "tone": "One or two words describing the tone (e.g. Passive Aggressive, Warm, professional)",
        "reason": "Brief explanation why"
    }}
    """
    
    try:
        response = client.models.generate_content(
            model=GEMINI_MODEL_NAME,
            contents=prompt,
            config=types.GenerateContentConfig(
                response_mime_type="application/json"
            )
        )
        result = json.loads(response.text)
        return ToneResponse(tone=result.get("tone", "Unknown"), reason=result.get("reason"))
    except Exception as e:
        print(f"Tone Analysis Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/translate", response_model=TranslateResponse)
async def translate_message(request: TranslateRequest):
    client = get_gemini_client()
    
    prompt = f"""
    Translate the following text to {request.target_language}.
    Detect the source language if possible.
    
    Text: "{request.text}"
    
    Return JSON only:
    {{
        "translation": "The translated text",
        "detected_source_language": "The source language code (e.g. en, fr)"
    }}
    """
    
    try:
        response = client.models.generate_content(
            model=GEMINI_MODEL_NAME,
            contents=prompt,
            config=types.GenerateContentConfig(
                response_mime_type="application/json"
            )
        )
        result = json.loads(response.text)
        return TranslateResponse(
            translation=result.get("translation", ""), 
            detected_source_language=result.get("detected_source_language")
        )
    except Exception as e:
        print(f"Translation Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
def health_check():
    return {"status": "ok", "model": GEMINI_MODEL_NAME}

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)
