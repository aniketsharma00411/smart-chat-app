import os
import uvicorn
import asyncio
import json
import logging
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Dict
from google import genai
from google.genai import types
from dotenv import load_dotenv

# Google Cloud Imports
from google.cloud import speech
from google.cloud import translate_v2 as translate
from google.cloud import texttospeech

from pathlib import Path

load_dotenv(dotenv_path=Path(__file__).parent.parent / '.env')

# Logger setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("SmartChatBackend")

from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="Smart Chat Gateway API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configuration
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
GEMINI_MODEL_NAME = os.getenv("GEMINI_MODEL_NAME", "gemini-3-flash-preview")
GOOGLE_PROJECT_ID = os.getenv("GOOGLE_PROJECT_ID") # Needed for some clients

if not GEMINI_API_KEY:
    logger.warning("WARNING: GEMINI_API_KEY not set. AI features will fail.")

# --- Clients Initialization (Lazy or Global) ---
# We initialize these globally for simplicity in this example, 
# ensuring they pick up credentials from env (GOOGLE_APPLICATION_CREDENTIALS)

try:
    speech_client = speech.SpeechAsyncClient()
    translate_client = translate.Client()
    tts_client = texttospeech.TextToSpeechClient()
    logger.info("✅ Google Cloud Clients initialized successfully.")
except Exception as e:
    logger.error(f"❌ Failed to initialize Google Cloud Clients: {e}")
    speech_client = None
    translate_client = None
    tts_client = None

# --- Helper Models & Functions ---

def get_gemini_client():
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="Server misconfigured: Missing API Key")
    return genai.Client(api_key=GEMINI_API_KEY)

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

# --- Standard API Endpoints ---

@app.post("/api/tone", response_model=ToneResponse)
async def analyze_tone(request: ToneRequest):
    client = get_gemini_client()
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
        logger.error(f"Tone Analysis Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/translate", response_model=TranslateResponse)
async def translate_message(request: TranslateRequest):
    # # Fallback to Gemini if Translate Client fails or for context-aware translations
    # # But here we use standard Google Cloud Translate for consistent style with the voice feature
    # if translate_client:
    #     try:
    #          # Translate API expects list of strings
    #         result = translate_client.translate(request.text, target_language=request.target_language)
    #         return TranslateResponse(
    #             translation=result['translatedText'], 
    #             detected_source_language=result['detectedSourceLanguage']
    #         )
    #     except Exception as e:
    #         logger.error(f"Cloud Translate Error: {e}")
    #         # Fall through to Gemini fallback
            
    client = get_gemini_client()
    prompt = f"""
    Translate the following text to {request.target_language}.
    Detect the source language if possible.
    Text: "{request.text}"
    Return JSON only:
    {{
        "translation": "The translated text",
        "detected_source_language": "The source language code"
    }}
    """
    try:
        response = client.models.generate_content(
            model=GEMINI_MODEL_NAME,
            contents=prompt,
            config=types.GenerateContentConfig(response_mime_type="application/json")
        )
        result = json.loads(response.text)
        return TranslateResponse(
            translation=result.get("translation", ""), 
            detected_source_language=result.get("detected_source_language")
        )
    except Exception as e:
        logger.error(f"Gemini Translation Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

class BatchTranslateItem(BaseModel):
    id: str
    text: str

class BatchTranslateRequest(BaseModel):
    items: List[BatchTranslateItem]
    target_language: str

class BatchTranslateResponse(BaseModel):
    translations: List[Dict[str, str]]

@app.post("/api/translate-batch", response_model=BatchTranslateResponse)
async def translate_batch(request: BatchTranslateRequest):
    client = get_gemini_client()
    
    # optimize: we could structure one giant prompt, or loop.
    # For < 20 messages, a single prompt is faster and cheaper.
    
    items_text = "\n".join([f"ID:{item.id} TEXT:{item.text}" for item in request.items])
    
    prompt = f"""
    Translate the following messages to {request.target_language}.
    Maintain the tone and meaning.
    
    Messages:
    {items_text}
    
    Return JSON only using this format:
    {{
        "translations": [
            {{ "id": "ID_FROM_INPUT", "translated_text": "TRANSLATED_TEXT" }}
        ]
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
        return BatchTranslateResponse(translations=result.get("translations", []))
    except Exception as e:
        logger.error(f"Batch Translate Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

class RewriteRequest(BaseModel):
    text: str
    tone: Optional[str] = "more professional and concise"
    instruction: Optional[str] = None

class RewriteResponse(BaseModel):
    rewritten_text: str

@app.post("/api/rewrite", response_model=RewriteResponse)
async def rewrite_message(request: RewriteRequest):
    client = get_gemini_client()
    
    # Construct prompt based on available inputs
    if request.instruction:
        # If instruction is present, it takes precedence or combines
        prompt_instruction = f"Instruction: {request.instruction}"
        if request.tone:
             prompt_instruction += f"\nAlso keep this tone in mind: {request.tone}"
    else:
        # Default to tone-based rewrite
        prompt_instruction = f"Rewrite the text to be {request.tone}."

    prompt = f"""
    You are an expert editor.
    {prompt_instruction}
    Keep the meaning the same but improve the clarity and style as requested.
    
    Text: "{request.text}"
    
    Return JSON only:
    {{
        "rewritten_text": "The rewritten text"
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
        return RewriteResponse(rewritten_text=result.get("rewritten_text", request.text))
    except Exception as e:
        logger.error(f"Rewrite Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
def health_check():
    return {
        "status": "ok", 
        "model": GEMINI_MODEL_NAME,
        "cloud_clients": {
            "speech": speech_client is not None,
            "translate": translate_client is not None,
            "tts": tts_client is not None
        }
    }

# --- WebSocket & Audio Processing ---

# Store active connections: call_id -> list of WebSockets
class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, List[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, call_id: str):
        await websocket.accept()
        if call_id not in self.active_connections:
            self.active_connections[call_id] = []
        self.active_connections[call_id].append(websocket)
        logger.info(f"New client connected to call {call_id}. Total: {len(self.active_connections[call_id])}")

    def disconnect(self, websocket: WebSocket, call_id: str):
        if call_id in self.active_connections:
            if websocket in self.active_connections[call_id]:
                self.active_connections[call_id].remove(websocket)
            if not self.active_connections[call_id]:
                del self.active_connections[call_id]
        logger.info(f"Client disconnected from call {call_id}.")

    async def broadcast(self, message: str, call_id: str, exclude: WebSocket = None):
        if call_id in self.active_connections:
            for connection in self.active_connections[call_id]:
                if connection != exclude:
                    try:
                        await connection.send_text(message)
                    except Exception as e:
                        logger.error(f"Broadcast error: {e}")

    async def broadcast_bytes(self, data: bytes, call_id: str, exclude: WebSocket = None):
        if call_id in self.active_connections:
            for connection in self.active_connections[call_id]:
                if connection != exclude:
                    try:
                        await connection.send_bytes(data)
                    except Exception as e:
                        logger.error(f"Broadcast bytes error: {e}")

manager = ConnectionManager()

# Audio Configuration
SAMPLE_RATE = 16000
CHANNELS = 1

@app.websocket("/ws/call/{call_id}")
async def websocket_endpoint(websocket: WebSocket, call_id: str, target_lang: str = "es"):
    await manager.connect(websocket, call_id)
    
    # We'll use a queue to buffer audio chunks for the STT stream
    request_queue = asyncio.Queue()
    
    async def stt_generator():
        while True:
            chunk = await request_queue.get()
            if chunk is None:
                return
            # The async client expects StreamingRecognizeRequest objects in the iterator
            yield speech.StreamingRecognizeRequest(audio_content=chunk)

    # Start audio processing task if supported
    process_task = None
    if speech_client and translate_client and tts_client:
        process_task = asyncio.create_task(run_translation_loop(websocket, call_id, target_lang, stt_generator()))
    else:
        logger.warning("Cloud clients missing, running in Echo/Passthrough mode only.")

    try:
        while True:
            # Receive data from Client
            # It can be bytes (Audio) or Text (Control messages)
            data = await websocket.receive()
            
            if "bytes" in data and data["bytes"]:
                audio_bytes = data["bytes"]
                
                # 1. Helper: Broadcast raw audio to others (Standard Call functionality)
                # await manager.broadcast_bytes(audio_bytes, call_id, exclude=websocket)
                
                # 2. Feed to STT Loop
                if process_task:
                    request_queue.put_nowait(audio_bytes)

            elif "text" in data and data["text"]:
                # Handle control messages if any
                 logger.info(f"Control message: {data['text']}")

    except WebSocketDisconnect:
        manager.disconnect(websocket, call_id)
        request_queue.put_nowait(None) # stop generator
        if process_task:
            process_task.cancel()
    except Exception as e:
        logger.error(f"WebSocket Error: {e}")
        manager.disconnect(websocket, call_id)
        request_queue.put_nowait(None) 

async def run_translation_loop(websocket: WebSocket, call_id: str, target_lang: str, request_iterator):
    """
    Continuous loop:
    STT Stream -> Transcript -> Translate -> TTS -> Broadcast Audio
    """
    config = speech.RecognitionConfig(
        encoding=speech.RecognitionConfig.AudioEncoding.LINEAR16,
        sample_rate_hertz=SAMPLE_RATE,
        language_code="en-US", # Assumed Input Language for now (could be dynamic)
        enable_automatic_punctuation=True,
    )
    streaming_config = speech.StreamingRecognitionConfig(
        config=config,
        interim_results=False # We want final results for translation
    )

    async def request_stream_wrapper(config, audio_stream):
        # Yield the configuration as the first request
        yield speech.StreamingRecognizeRequest(streaming_config=config)
        # Then yield audio chunks from the input stream
        async for audio_request in audio_stream:
            yield audio_request

    try:
        # The async client requires the config to be the first item in the requests iterator
        # It does NOT accept 'config' as a keyword argument when 'requests' is provided.
        responses = await speech_client.streaming_recognize(
            requests=request_stream_wrapper(streaming_config, request_iterator),
        )

        async for response in responses:
            if not response.results:
                continue

            result = response.results[0]
            if not result.alternatives:
                continue

            transcript = result.alternatives[0].transcript
            confidence = result.alternatives[0].confidence
            logger.info(f"🎤 STT: {transcript} (conf: {confidence})")

            # 1. Translate
            # Use 'base' model for speed
            translation = translate_client.translate(
                transcript, 
                target_language=target_lang,
                model='base' 
            )
            translated_text = translation['translatedText']
            logger.info(f"🌍 Translated: {translated_text}")

            # 2. TTS
            synthesis_input = texttospeech.SynthesisInput(text=translated_text)
            voice = texttospeech.VoiceSelectionParams(
                language_code=target_lang,
                ssml_gender=texttospeech.SsmlVoiceGender.NEUTRAL
            )
            audio_config = texttospeech.AudioConfig(
                audio_encoding=texttospeech.AudioEncoding.LINEAR16,
                sample_rate_hertz=SAMPLE_RATE
            )

            tts_response = tts_client.synthesize_speech(
                input=synthesis_input, voice=voice, audio_config=audio_config
            )
            
            # 3. Broadcast Synthesized Audio
            # We broadcast this to EVERYONE (including the speaker, optionally, for feedback)
            # Or usually to the *other* participants.
            await manager.broadcast_bytes(tts_response.audio_content, call_id, exclude=None)

    except Exception as e:
        logger.error(f"Translation Loop Failed: {e}")


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)
