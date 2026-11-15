// Playback-only regression: deliberately excludes the microphone recording suite.
import 'acceptance_test.dart' as acceptance;
import 'storage_failure_test.dart' as storage;
import 'streaming_fault_test.dart' as streaming;
import 'gateway_test.dart' as gateway;

void main() {
  storage.main();
  acceptance.main();
  streaming.main();
  gateway.main();
}
