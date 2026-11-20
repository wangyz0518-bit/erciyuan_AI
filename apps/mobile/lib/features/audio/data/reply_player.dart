import '../domain/audio_ports.dart';
import 'platform_audio_adapters.dart';

AudioPcmPlaybackPort createReplyPlayer({required bool Function() inCall}) =>
    NativePcmPlayback(inCall: inCall);
Future<void> unlockReplyPlayer(AudioPcmPlaybackPort? player) async {}
