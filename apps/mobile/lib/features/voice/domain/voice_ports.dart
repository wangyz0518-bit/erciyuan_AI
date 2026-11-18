/// Speech recognition uses the device's recognizer with on-device mode only.
/// It must never send text to the chat pipeline without explicit user action.
abstract interface class OnDeviceAsrPort {
  Future<bool> listen(void Function(String words, bool finalResult) onWords);
  Future<void> stop();
  Future<void> dispose();
}

/// System TTS is a separate optional fallback, not a character voice clone.
abstract interface class SystemTtsPort {
  Future<void> speak(String text, void Function() onFinished);
  Future<void> stop();
  Future<void> dispose();
}
