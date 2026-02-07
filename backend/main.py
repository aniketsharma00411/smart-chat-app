from fastapi.middleware.cors import CORSMiddleware
import os
import uvicorn
import asyncio
import json
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Dict
from google import genai
from google.genai import types
from dotenv import load_dotenv

# Google Cloud Imports
from google.cloud.speech_v2 import SpeechAsyncClient
from google.cloud.speech_v2.types import cloud_speech
from google.cloud import translate_v2 as translate
from google.cloud import texttospeech

from pathlib import Path

load_dotenv(dotenv_path=Path(__file__).parent.parent / '.env')

# Logger setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("SmartChatBackend")

# --- Clients Initialization (Lazy or Global) ---
speech_client = None
translate_client = None
tts_client = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    global speech_client, translate_client, tts_client
    try:
        # Initialize Google Cloud Clients
        speech_client = SpeechAsyncClient()
        translate_client = translate.Client()
        tts_client = texttospeech.TextToSpeechAsyncClient()
        logger.info("✅ Google Cloud Clients (V2) initialized successfully.")

        # Verify project ID is set
        if not GOOGLE_PROJECT_ID:
            logger.error("❌ GOOGLE_PROJECT_ID not set in environment")
        else:
            logger.info(
                f"✅ Using project: {GOOGLE_PROJECT_ID}, location: {GOOGLE_CLOUD_LOCATION}")

    except Exception as e:
        logger.error(f"Failed to initialize Google Cloud Clients: {e}")
        speech_client = None
        translate_client = None
        tts_client = None

    yield

    # Shutdown (cleanup if needed)
    logger.info("👋 Shutting down...")

app = FastAPI(title="Smart Chat Gateway API", lifespan=lifespan)

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
GOOGLE_PROJECT_ID = os.getenv("GOOGLE_PROJECT_ID")  # Required for Speech V2
GOOGLE_CLOUD_LOCATION = os.getenv(
    "GOOGLE_CLOUD_LOCATION", "global")  # Location for Speech V2

if not GEMINI_API_KEY:
    logger.warning("WARNING: GEMINI_API_KEY not set. AI features will fail.")

# --- Helper Models & Functions ---


def get_gemini_client():
    if not GEMINI_API_KEY:
        raise HTTPException(
            status_code=500, detail="Server misconfigured: Missing API Key")
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
        history_context = f"Previous conversation:\n" + \
            "\n".join(request.conversation_history)

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
            config=types.GenerateContentConfig(
                response_mime_type="application/json")
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

    items_text = "\n".join(
        [f"ID:{item.id} TEXT:{item.text}" for item in request.items])

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
        logger.info(
            f"New client connected to call {call_id}. Total: {len(self.active_connections[call_id])}")

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

    # Queue for audio chunks going to Gemini Live
    audio_input_queue = asyncio.Queue()
    # Queue for translated audio coming from Gemini Live
    audio_output_queue = asyncio.Queue()

    # Start audio processing task if translation is enabled
    process_task = None
    translation_enabled = target_lang is not None and target_lang != ""

    if translation_enabled:
        logger.info(f"🌍 Translation enabled: target_lang={target_lang}")
    else:
        logger.info("🔊 Passthrough mode: No translation")

    try:
        while True:
            # Receive data from Client
            data = await websocket.receive()

            if "bytes" in data and data["bytes"]:
                audio_bytes = data["bytes"]

                # 1. Broadcast raw audio ONLY when translation is disabled
                if not translation_enabled:
                    num_connections = len(
                        manager.active_connections.get(call_id, []))
                    logger.info(
                        f"📤 RECV {len(audio_bytes)} bytes | Broadcasting to {num_connections} connections (exclude sender)")
                    # ECHO OFF: Exclude sender so they don't hear themselves
                    await manager.broadcast_bytes(audio_bytes, call_id, exclude=websocket)

                # 2. Feed to Translation Loop (Speech V2)
                if translation_enabled:
                    # Start translation task on first audio
                    if process_task is None:
                        logger.info(
                            "🎤 Starting live translation (Speech V2 + TTS)...")
                        process_task = asyncio.create_task(
                            run_gemini_live_translation(
                                call_id, target_lang, audio_input_queue, audio_output_queue
                            )
                        )
                        # Also start task to broadcast translated audio
                        asyncio.create_task(
                            broadcast_translated_audio(
                                websocket, call_id, audio_output_queue)
                        )

                    # Send audio to translation pipeline
                    audio_input_queue.put_nowait(audio_bytes)

            elif "text" in data and data["text"]:
                # Handle control messages if any
                logger.info(f"Control message: {data['text']}")

    except WebSocketDisconnect:
        manager.disconnect(websocket, call_id)
        audio_input_queue.put_nowait(None)  # Signal end
        if process_task:
            process_task.cancel()
    except Exception as e:
        logger.error(f"WebSocket Error: {e}")
        manager.disconnect(websocket, call_id)
        audio_input_queue.put_nowait(None)


# Language code to full name mapping for system instructions
LANGUAGE_NAMES = {
    'en': 'English',
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'hi': 'Hindi',
    'zh': 'Chinese',
    'ja': 'Japanese',
    'ko': 'Korean',
    'ru': 'Russian',
    'pt': 'Portuguese',
}

# Language code to TTS voice name mapping (with region codes)
TTS_VOICES = {
    'en': 'en-US-Standard-A',
    'es': 'es-ES-Standard-A',
    'fr': 'fr-FR-Standard-A',
    'de': 'de-DE-Standard-A',
    'hi': 'hi-IN-Standard-A',
    'zh': 'zh-CN-Standard-A',
    'ja': 'ja-JP-Standard-A',
    'ko': 'ko-KR-Standard-A',
    'ru': 'ru-RU-Standard-A',
    'pt': 'pt-BR-Standard-A',
}


async def run_gemini_live_translation(call_id: str, target_lang: str, audio_input_queue: asyncio.Queue, audio_output_queue: asyncio.Queue):
    """
    Uses streaming STT + Gemini text translation + TTS for true live translation.
    All tasks run in parallel: audio feeding, STT processing, translation, and TTS.
    """
    if not speech_client or not tts_client:
        logger.error("❌ Google Cloud clients not initialized")
        return

    target_language_name = LANGUAGE_NAMES.get(target_lang, target_lang.upper())
    client = get_gemini_client()

    logger.info(
        f"🌐 Starting Speech V2 translation pipeline for {target_language_name}")

    # Queue for STT results to be processed
    transcript_queue = asyncio.Queue()

    # Configure streaming speech recognition (V2)
    recognition_config = cloud_speech.RecognitionConfig(
        explicit_decoding_config=cloud_speech.ExplicitDecodingConfig(
            encoding=cloud_speech.ExplicitDecodingConfig.AudioEncoding.LINEAR16,
            sample_rate_hertz=16000,
            audio_channel_count=1,
        ),
        language_codes=["en-US"],
        model="long",  # Better for natural conversation
        features=cloud_speech.RecognitionFeatures(
            enable_automatic_punctuation=True,
        ),
    )

    streaming_config = cloud_speech.StreamingRecognitionConfig(
        config=recognition_config,
        streaming_features=cloud_speech.StreamingRecognitionFeatures(
            interim_results=True,
        ),
    )

    # V2 recognizer path
    recognizer = f"projects/{GOOGLE_PROJECT_ID}/locations/{GOOGLE_CLOUD_LOCATION}/recognizers/_"

    logger.info(f"✅ Using recognizer: {recognizer}")
    logger.info(f"✅ Audio format: 16kHz LINEAR16 mono")

    # Task 1: Feed audio from input queue to STT stream
    async def audio_feeder(requests_queue: asyncio.Queue):
        """Feeds audio chunks to the STT request queue"""
        chunk_count = 0
        try:
            while True:
                chunk = await audio_input_queue.get()
                if chunk is None:
                    await requests_queue.put(None)
                    break

                chunk_count += 1
                if chunk_count == 1:
                    logger.info(
                        f"🔊 Audio streaming started (chunk size: {len(chunk)} bytes)")
                elif chunk_count % 100 == 0:
                    logger.debug(f"📊 Streamed {chunk_count} chunks")

                await requests_queue.put(cloud_speech.StreamingRecognizeRequest(audio=chunk))
        except Exception as e:
            logger.error(f"❌ Audio feeder error: {e}")

    # Task 2: Process STT results and queue for translation (V2 API)
    async def stt_processor(requests_queue: asyncio.Queue):
        """Runs STT stream and queues transcripts for translation"""
        recognition_count = 0

        while True:
            try:
                async def request_generator():
                    # First request with config and recognizer
                    yield cloud_speech.StreamingRecognizeRequest(
                        recognizer=recognizer,
                        streaming_config=streaming_config,
                    )

                    # Then audio content
                    while True:
                        req = await requests_queue.get()
                        if req is None:
                            return
                        yield req

                logger.debug(f"📡 Starting STT stream #{recognition_count + 1}")
                response_stream = await speech_client.streaming_recognize(
                    requests=request_generator())

                async for response in response_stream:
                    for result in response.results:
                        if not result.alternatives:
                            continue

                        transcript = result.alternatives[0].transcript.strip()
                        is_final = result.is_final

                        if transcript:
                            recognition_count += 1
                            logger.info(
                                f"🎤 {'[FINAL]' if is_final else '[INTERIM]'} '{transcript}'")
                            await transcript_queue.put((transcript, is_final))

                # Stream ended naturally (user stopped speaking) - this is normal
                logger.debug("🔄 STT stream ended, ready for next utterance")
                await asyncio.sleep(0.1)

            except Exception as e:
                error_str = str(e)
                # Timeout is normal when users pause - not an error!
                if "timed out" in error_str.lower() or "OutOfRange" in error_str:
                    logger.debug("💤 No audio received, stream closed (normal)")
                    await asyncio.sleep(0.5)
                    continue
                elif "INVALID_ARGUMENT" in error_str:
                    logger.error(f"❌ Invalid audio format or config: {e}")
                    await asyncio.sleep(2)
                    continue
                else:
                    logger.warning(f"⚠️ STT issue: {e}")
                    await asyncio.sleep(1)
                    continue

    # Task 3: Translate with timeout handling for missing finals
    async def translator():
        """Processes transcripts, translates, and generates speech"""
        translated_sentences = set()
        last_transcript = ""
        FINAL_TIMEOUT = 3.0  # Treat as final after this many seconds of no updates

        async def process_translation(text: str, sentence_id: str):
            """Actually do the translation and TTS"""
            if sentence_id in translated_sentences:
                return

            translated_sentences.add(sentence_id)

            try:
                prompt = f"Translate this text directly to {target_language_name} (only output the translation, no explanations):\n\n{text}"
                translation_response = client.models.generate_content(
                    model=GEMINI_MODEL_NAME,
                    contents=prompt,
                )
                translated_text = translation_response.text.strip()
                logger.info(f"🌍 '{text}' → '{translated_text}'")

                synthesis_input = texttospeech.SynthesisInput(
                    text=translated_text)
                voice_name = TTS_VOICES.get(
                    target_lang, f"{target_lang}-Standard-A")
                voice = texttospeech.VoiceSelectionParams(
                    language_code=target_lang,
                    name=voice_name
                )
                audio_config = texttospeech.AudioConfig(
                    audio_encoding=texttospeech.AudioEncoding.LINEAR16,
                    sample_rate_hertz=16000,
                )

                tts_response = await tts_client.synthesize_speech(
                    input=synthesis_input,
                    voice=voice,
                    audio_config=audio_config
                )

                audio_output_queue.put_nowait(tts_response.audio_content)
                logger.info(
                    f"🔊 Queued {len(tts_response.audio_content)} bytes")

            except Exception as e:
                logger.error(f"❌ Translation/TTS error: {e}")

        def extract_complete_sentences(text: str):
            import re
            sentence_endings = r'[.!?]'
            sentences = []
            parts = re.split(f'({sentence_endings})', text)

            current_sentence = ""
            for part in parts:
                current_sentence += part
                if re.match(sentence_endings, part) and current_sentence.strip():
                    sentences.append(current_sentence.strip())
                    current_sentence = ""

            return sentences, current_sentence.strip()

        try:
            while True:
                try:
                    transcript, is_final = await asyncio.wait_for(
                        transcript_queue.get(),
                        timeout=FINAL_TIMEOUT
                    )

                    last_transcript = transcript
                    complete_sentences, remaining = extract_complete_sentences(
                        transcript)

                    translation_tasks = []
                    for sentence in complete_sentences:
                        sentence_id = sentence.strip()
                        if len(sentence_id) > 2 and sentence_id not in translated_sentences:
                            logger.info(
                                f"📝 {'[FINAL]' if is_final else '[INTERIM]'} '{sentence_id}'")
                            translation_tasks.append(asyncio.create_task(
                                process_translation(sentence_id, sentence_id)))

                    if is_final and remaining and len(remaining) > 2 and remaining not in translated_sentences:
                        logger.info(f"📝 [FINAL no punct] '{remaining}'")
                        translation_tasks.append(asyncio.create_task(
                            process_translation(remaining, remaining)))

                    if translation_tasks:
                        await asyncio.gather(*translation_tasks, return_exceptions=True)

                except asyncio.TimeoutError:
                    # No new transcript for FINAL_TIMEOUT seconds - user likely finished speaking
                    if last_transcript and last_transcript not in translated_sentences and len(last_transcript) > 2:
                        logger.info(
                            f"💬 Speaking paused → translating: '{last_transcript}'")
                        await process_translation(last_transcript, last_transcript)
                        last_transcript = ""

        except Exception as e:
            logger.error(f"❌ Translator error: {e}")

    # Run all tasks concurrently
    requests_queue = asyncio.Queue()

    try:
        await asyncio.gather(
            audio_feeder(requests_queue),
            stt_processor(requests_queue),
            translator(),
            return_exceptions=True
        )
    except Exception as e:
        logger.error(f"❌ Translation pipeline failed: {e}")
        import traceback
        logger.error(traceback.format_exc())
    finally:
        logger.info("🔌 Streaming translation ended")


async def broadcast_translated_audio(websocket: WebSocket, call_id: str, audio_output_queue: asyncio.Queue):
    """
    Broadcasts translated audio from Gemini Live to all call participants.
    """
    broadcast_count = 0
    try:
        while True:
            translated_audio = await audio_output_queue.get()
            if translated_audio is None:
                break

            broadcast_count += 1
            # Broadcast to all participants (or exclude sender if desired)
            await manager.broadcast_bytes(translated_audio, call_id, exclude=None)

            if broadcast_count % 10 == 0:
                logger.info(
                    f"📶 Broadcasted {broadcast_count} translated audio chunks")
    except Exception as e:
        logger.error(f"❌ Broadcast translated audio failed: {e}")


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
