import '../models/agent.dart';
import 'ssh_service.dart';

/// Detects installed agent CLIs on the remote host via SSH.
class AgentService {
  const AgentService(this._connection);

  final SshConnection _connection;

  /// Runs detection for all known agents in parallel and returns the ones
  /// that are actually installed, with version strings and (for Claude) a
  /// list of projects.
  Future<List<AgentInfo>> detect() async {
    final futures = kAgentSpecs.map<Future<AgentInfo?>>(_detect);
    final results = await Future.wait(futures);
    return results.whereType<AgentInfo>().toList();
  }

  Future<AgentInfo?> _detect(AgentSpec spec) async {
    try {
      final which =
          await _connection.runFull('command -v ${_shq(spec.command)}');
      if (!which.ok) return null;
      final binaryPath = which.stdout.trim();
      if (binaryPath.isEmpty) return null;

      final verRes = await _connection.runFull(
          '${_shq(spec.command)} ${spec.versionFlag} 2>&1 | head -1');
      final version =
          verRes.stdout.trim().isEmpty ? null : verRes.stdout.trim();

      List<ClaudeProject>? projects;
      if (spec.readProjects) {
        projects = await _claudeProjects();
      }

      return AgentInfo(
        key: spec.key,
        name: spec.name,
        binaryPath: binaryPath,
        command: spec.command,
        description: spec.description,
        version: version,
        projects: projects,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<ClaudeProject>> _claudeProjects() async {
    try {
      // List immediate subdirectories of ~/.claude/projects/.
      final res = await _connection
          .runFull(r'ls -1d "$HOME/.claude/projects"/*/ 2>/dev/null | head -40');
      if (res.exitCode != 0 || res.stdout.trim().isEmpty) return const [];
      return res.stdout
          .trim()
          .split('\n')
          .where((p) => p.isNotEmpty)
          .map((p) {
        final trimmed = p.trimRight().replaceAll(RegExp(r'/$'), '');
        final name = trimmed.split('/').last;
        return ClaudeProject(
          name: name.isEmpty ? trimmed : name,
          path: trimmed,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  static String _shq(String v) => "'${v.replaceAll("'", "'\\''")}'";
}
