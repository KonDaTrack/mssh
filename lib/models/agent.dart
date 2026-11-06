/// A detected agent CLI on the remote host.
class AgentInfo {
  const AgentInfo({
    required this.key,
    required this.name,
    required this.binaryPath,
    required this.command,
    required this.description,
    this.version,
    this.projects,
  });

  /// Stable identifier used in card keys / icons.
  final String key;
  final String name;

  /// Absolute path returned by `which`.
  final String binaryPath;

  /// The shell command to launch this agent.
  final String command;
  final String description;
  final String? version;

  /// Only populated for Claude: the list of project directories under
  /// `~/.claude/projects/`.
  final List<ClaudeProject>? projects;
}

class ClaudeProject {
  const ClaudeProject({required this.name, required this.path});

  /// Directory basename, used as the display label.
  final String name;

  /// Absolute path on the remote host.
  final String path;
}

/// All agents we know about and how to detect them. Listed in preference order.
const List<AgentSpec> kAgentSpecs = [
  AgentSpec(
    key: 'claude',
    name: 'Claude',
    command: 'claude',
    versionFlag: '--version',
    description: 'Anthropic Claude 代码代理 (claude-code)',
    readProjects: true,
  ),
  AgentSpec(
    key: 'aider',
    name: 'Aider',
    command: 'aider',
    versionFlag: '--version',
    description: 'AI pair programming in your terminal',
    readProjects: false,
  ),
  AgentSpec(
    key: 'gemini',
    name: 'Gemini CLI',
    command: 'gemini',
    versionFlag: '--version',
    description: 'Google Gemini CLI agent',
    readProjects: false,
  ),
  AgentSpec(
    key: 'codex',
    name: 'Codex',
    command: 'codex',
    versionFlag: '--version',
    description: 'OpenAI Codex CLI',
    readProjects: false,
  ),
  AgentSpec(
    key: 'openhands',
    name: 'OpenHands',
    command: 'openhands',
    versionFlag: '--version',
    description: 'All-Hands AI coding agent',
    readProjects: false,
  ),
];

class AgentSpec {
  const AgentSpec({
    required this.key,
    required this.name,
    required this.command,
    required this.versionFlag,
    required this.description,
    required this.readProjects,
  });

  final String key;
  final String name;
  final String command;
  final String versionFlag;
  final String description;
  final bool readProjects;
}
