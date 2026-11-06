import 'package:flutter/material.dart';

import '../models/agent.dart';
import '../services/agent_service.dart';
import '../services/ssh_service.dart';
import '../theme.dart';

/// The Agents tab: shows detected CLIs as icon cards, and for Claude lists its
/// projects so the user can open a terminal pre-cd'd to the right directory.
class AgentsScreen extends StatefulWidget {
  const AgentsScreen({
    super.key,
    required this.connection,
    required this.onLaunch,
  });

  final SshConnection connection;

  /// Called when the user picks an agent (+ optional directory).
  /// [command] is the full shell command to run in a new terminal.
  final void Function(String command, String label) onLaunch;

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

enum _LoadState { idle, loading, done, error }

class _AgentsScreenState extends State<AgentsScreen> {
  _LoadState _state = _LoadState.idle;
  List<AgentInfo> _agents = const [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    setState(() {
      _state = _LoadState.loading;
      _error = null;
    });
    try {
      final agents = await AgentService(widget.connection).detect();
      if (!mounted) return;
      setState(() {
        _agents = agents;
        _state = _LoadState.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _state = _LoadState.error;
      });
    }
  }

  void _launch(String command, String label) => widget.onLaunch(command, label);

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      _LoadState.idle || _LoadState.loading => _loadingView(),
      _LoadState.error => _errorView(),
      _LoadState.done => _doneView(),
    };
  }

  Widget _loadingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            '正在检测 Agent CLI…',
            style: const TextStyle(color: AppTheme.textDim),
          ),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 52, color: AppTheme.danger),
            const SizedBox(height: 14),
            Text('检测失败：$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textDim)),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _detect,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _doneView() {
    if (_agents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.smart_toy_outlined,
                  size: 64, color: AppTheme.border),
              const SizedBox(height: 18),
              const Text('未发现 Agent CLI',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text(
                '支持 claude / aider / gemini / codex / openhands。\n'
                '先在远端安装再返回这里。',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textDim, height: 1.5),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _detect,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新检测'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        for (final agent in _agents)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _AgentCard(
              agent: agent,
              onLaunch: _launch,
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: TextButton.icon(
            onPressed: _detect,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('重新检测'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Agent card
// ---------------------------------------------------------------------------

class _AgentCard extends StatefulWidget {
  const _AgentCard({required this.agent, required this.onLaunch});

  final AgentInfo agent;
  final void Function(String command, String label) onLaunch;

  @override
  State<_AgentCard> createState() => _AgentCardState();
}

class _AgentCardState extends State<_AgentCard> {
  bool _projectsExpanded = false;

  AgentInfo get a => widget.agent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: a.projects != null
                ? () => setState(
                    () => _projectsExpanded = !_projectsExpanded)
                : () => widget.onLaunch(a.command, a.name),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                children: [
                  _AgentIcon(agentKey: a.key),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              a.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (a.version != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceAlt,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  a.version!,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppTheme.textDim,
                                    fontFamily: AppTheme.monoFont,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          a.description,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textDim,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _launchChips(context),
                      ],
                    ),
                  ),
                  if (a.projects != null)
                    Icon(
                      _projectsExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.textDim,
                    ),
                ],
              ),
            ),
          ),
          // Projects section (Claude only)
          if (a.projects != null && _projectsExpanded)
            _ProjectsList(
              projects: a.projects!,
              agentCommand: a.command,
              agentName: a.name,
              onLaunch: widget.onLaunch,
            ),
        ],
      ),
    );
  }

  Widget _launchChips(BuildContext context) {
    final projects = a.projects;
    if (projects != null) {
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          _Chip(
            label: '快速启动',
            icon: Icons.rocket_launch_rounded,
            onTap: () => widget.onLaunch(a.command, a.name),
          ),
          if (projects.isNotEmpty)
            _Chip(
              label: '${projects.length} 个项目',
              icon: Icons.folder_open_rounded,
              onTap: () =>
                  setState(() => _projectsExpanded = !_projectsExpanded),
              accent: false,
            ),
        ],
      );
    }
    return _Chip(
      label: '打开终端',
      icon: Icons.terminal_rounded,
      onTap: () => widget.onLaunch(a.command, a.name),
    );
  }
}

class _ProjectsList extends StatelessWidget {
  const _ProjectsList({
    required this.projects,
    required this.agentCommand,
    required this.agentName,
    required this.onLaunch,
  });

  final List<ClaudeProject> projects;
  final String agentCommand;
  final String agentName;
  final void Function(String, String) onLaunch;

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Text(
          '未找到 ~/.claude/projects/ 下的项目',
          style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
        ),
      );
    }
    return Column(
      children: [
        const Divider(height: 1, color: AppTheme.border),
        for (final p in projects)
          InkWell(
            onTap: () {
              final cmd = "cd '${p.path.replaceAll("'", "'\\''")}'"
                  ' && $agentCommand';
              onLaunch(cmd, '${p.name} · $agentName');
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(58, 12, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.folder_rounded,
                      size: 18, color: AppTheme.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      p.name,
                      style: const TextStyle(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppTheme.textDim, size: 18),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.accent = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: accent
              ? AppTheme.accent.withValues(alpha: 0.18)
              : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accent
                ? AppTheme.accent.withValues(alpha: 0.35)
                : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: accent ? AppTheme.accent : AppTheme.textDim,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: accent ? AppTheme.accent : AppTheme.textDim,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentIcon extends StatelessWidget {
  const _AgentIcon({required this.agentKey});
  final String agentKey;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (agentKey) {
      'claude' => (
          const Color(0x1ADA7756),
          const Color(0xFFDA7756),
          Icons.psychology_rounded,
        ),
      'aider' => (
          const Color(0x1A5C9DFF),
          AppTheme.accent,
          Icons.smart_toy_rounded,
        ),
      'gemini' => (
          const Color(0x1A8B5CF6),
          const Color(0xFF8B5CF6),
          Icons.auto_awesome_rounded,
        ),
      'codex' => (
          const Color(0x1AF5A623),
          const Color(0xFFF5A623),
          Icons.bolt_rounded,
        ),
      'openhands' => (
          const Color(0x1A43D17C),
          AppTheme.ok,
          Icons.front_hand_rounded,
        ),
      _ => (AppTheme.surfaceAlt, AppTheme.textDim, Icons.terminal_rounded),
    };

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: fg, size: 24),
    );
  }
}
