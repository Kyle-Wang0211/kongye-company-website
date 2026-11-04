import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/config/backend_deployment.dart';
void main() {
  test('web migration binds the exact new RDS tenant and rejects previous tenants', () {
    final target = BackendDeployment.chinaFromBuild();
    target.validate();
    expect(target.id, 'cn-primary');
    expect(target.supabaseUrl, 'https://api.kongye.space');
    expect(target.acceptsApi('https://ra-qcgaflf4k0heipp-pb.rds.apsaradb.com', 'public'), isFalse);
    expect(target.acceptsApi(BackendDeployment.legacyUrl, 'public'), isFalse);
    expect(target.acceptsApi(target.supabaseUrl, 'public'), isTrue);
    expect(target.namespace, endsWith('.rds20261104'));
  });
}
