import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../services/ssh_service.dart';
import '../terminal_theme.dart';
import '../theme.dart';

/// A single interactive shell rendered with xterm.
///
/// Voice input rides on the OS keyboard: the ⌨ button calls
/// [TerminalViewState.requestKeyboard], which pops the platform IME — so the
/// phone's built-in dictation mic types straight into the terminal. Real
/// control keys (Enter / Esc / arrows / ^C…) are on the toolbar because the
/// soft keyboard can't produce them.
class TerminalPane extends StatefulWidget {
  const TerminalPane({
    super.key,
    required this.connection,
    this.startupCommand,
  });

  final SshConnection connection;

  /// Optional command typed into the fresh shell (e.g. `claude`), so a
  /// terminal can launch an agent CLI automatically.
  final String? startupCommand;

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

enum _Status { connecting, ready, closed, error }

class _TerminalPaneState extends State<TerminalPane> {
  final Terminal _terminal = Terminal(maxLines: 20000);
  final GlobalKey<TerminalViewState> _viewKey = GlobalKey<TerminalViewState>();

  SSHSession? _session;
  _Status _status = _Status.connecting;
  Object? _error;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _terminal.onOutput = (data) {
      _session?.write(Uint8List.fromList(utf8.encode(data)));
    };
    _terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      _session?.resizeTerminal(width, height, pixelWidth, pixelHeight);
    };
    _connect();
  }

  Future<void> _connect() async {
    setState(() {
      _status = _Status.connecting;
      _error = null;
    });
    try {
      final session = await widget.connection.openShell(
        cols: _terminal.viewWidth,
        rows: _terminal.viewHeight,
      );
      if (_disposed) {
        session.close();
        return;
      }
      _session = session;
      session.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_terminal.write);
      // A PTY usually folds stderr into stdout; some servers don't, so mirror it.
      session.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_terminal.write);
      unawaited(session.done.then((_) {
        if (!_disposed) setState(() => _status = _Status.closed);
      }));
      setState(() => _status = _Status.ready);

      final cmd = widget.startupCommand;
      if (cmd != null && cmd.trim().isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!_disposed) {
          _session?.write(Uint8List.fromList(utf8.encode('${cmd.trim()}\n')));
        }
      }
    } catch (e) {
      if (_disposed) return;
      setState(() {
        _error = e;
        _status = _Status.error;
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _terminal.onOutput = null;
    _terminal.onResize = null;
    _session?.close();
    super.dispose();
  }

  void _key(TerminalKey key) => _terminal.keyInput(key);

  void _control(int code) {
    _session?.write(Uint8List.fromList(<int>[code]));
  }

  void _showKeyboard() {
    _viewKey.currentState?.requestKeyboard();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_status == _Status.connecting)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: Container(
            color: kTerminalTheme.background,
            child: TerminalView(
              _terminal,
              key: _viewKey,
              theme: kTerminalTheme,
              textStyle: const TerminalStyle(
                fontSize: 13,
                height: 1.25,
                fontFamily: AppTheme.monoFont,
              ),
              padding: const EdgeInsets.all(6),
              autofocus: false,
              hardwareKeyboardOnly: false,
              deleteDetection: true,
              onTapUp: (_, _) => _showKeyboard(),
            ),
          ),
        ),
        if (_status == _Status.closed || _status == _Status.error) _statusBar(),
        _toolbar(),
      ],
    );
  }

  Widget _statusBar() {
    final isError = _status == _Status.error;
    return Container(
      width: double.infinity,
      color: isError
          ? AppTheme.danger.withValues(alpha: 0.14)
          : AppTheme.surfaceAlt,
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isError ? '${_error ?? "连接出错"}' : '会话已结束',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: isError ? AppTheme.danger : AppTheme.textDim,
              ),
            ),
          ),
          TextButton(onPressed: _connect, child: const Text('重连')),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _key2('esc', () => _key(TerminalKey.escape)),
                  _key2('tab', () => _key(TerminalKey.tab)),
                  _key2('↑', () => _key(TerminalKey.arrowUp)),
                  _key2('↓', () => _key(TerminalKey.arrowDown)),
                  _key2('←', () => _key(TerminalKey.arrowLeft)),
                  _key2('→', () => _key(TerminalKey.arrowRight)),
                  _key2('^C', () => _control(0x03)),
                  _key2('^D', () => _control(0x04)),
                  _key2('^Z', () => _control(0x1a)),
                  _key2('^L', () => _control(0x0c)),
                  _key2('/', () => _terminal.textInput('/')),
                  _key2('-', () => _terminal.textInput('-')),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          _key2('⌨ 语音', _showKeyboard, primary: true),
          const SizedBox(width: 6),
          _key2('⏎', () => _key(TerminalKey.enter), primary: true),
        ],
      ),
    );
  }

  Widget _key2(String label, VoidCallback onTap, {bool primary = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: primary ? AppTheme.accent : AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: primary ? 14 : 12,
              vertical: 9,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
                color: primary ? Colors.white : Colors.white70,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
