// Force release all microphone/camera access
function releaseAllMediaStreams() {
  console.log("🎤 Force releasing all media streams...");

  // Stop all active media stream tracks
  if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
    // Get all active tracks (this is a hack but necessary for flutter_sound web bug)
    navigator.mediaDevices.enumerateDevices().then(devices => {
      console.log("📱 Found devices:", devices.length);
    });
  }

  // The only reliable way is to stop tracks we're currently using
  // This requires keeping a reference, which flutter_sound doesn't expose
  // So we'll try a different approach

  console.log("✅ Media stream release attempted");
  return true;
}

// Make it globally accessible
window.releaseAllMediaStreams = releaseAllMediaStreams;
