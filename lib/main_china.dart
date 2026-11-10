import 'config/backend_deployment.dart';
import 'main.dart' as app;

/// This entrypoint cannot silently choose the international backend.
Future<void> main() =>
    app.runPocketWorld(buildDeployment: BackendDeployment.chinaFromBuild());
