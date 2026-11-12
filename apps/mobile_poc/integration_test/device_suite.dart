import 'acceptance_test.dart' as acceptance;
import 'storage_failure_test.dart' as storage;
import 'immersive_test.dart' as immersive;

void main() {
  storage.main();
  acceptance.main();
  immersive.main();
}
