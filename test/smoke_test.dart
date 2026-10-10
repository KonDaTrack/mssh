import 'package:flutter_test/flutter_test.dart';
import 'package:mssh/app.dart';
import 'package:mssh/models/host.dart';
import 'package:mssh/screens/hosts_screen.dart';
import 'package:mssh/screens/workspace_screen.dart';

/// Compile-level smoke test: referencing these types forces the whole widget
/// graph (xterm terminal, SFTP tree, preview, SSH service) through the
/// compiler. Runtime plugin channels are intentionally not exercised.
void main() {
  test('root app constructs', () {
    const app = MsshApp();
    expect(app, isNotNull);
  });

  test('hosts screen constructs', () {
    const screen = HostsScreen();
    expect(screen, isNotNull);
  });

  test('workspace carries its host', () {
    const host = Host(id: 'demo', host: 'my-desktop', username: 'k');
    const workspace = WorkspaceScreen(host: host);
    expect(workspace.host.host, 'my-desktop');
    expect(host.displayLabel, 'k@my-desktop');
  });
}
