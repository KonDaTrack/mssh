import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/credential.dart';
import '../models/host.dart';
import '../services/host_store.dart';
import '../theme.dart';

/// Add or edit a host. Secrets are written to the secure store on save.
class HostEditScreen extends StatefulWidget {
  const HostEditScreen({super.key, this.existing});

  final Host? existing;

  @override
  State<HostEditScreen> createState() => _HostEditScreenState();
}

class _HostEditScreenState extends State<HostEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _label;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _privateKey;
  late final TextEditingController _passphrase;

  AuthMethod _authMethod = AuthMethod.password;
  bool _obscurePassword = true;
  bool _saving = false;
  bool _loadingSecrets = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final h = widget.existing;
    _label = TextEditingController(text: h?.label ?? '');
    _host = TextEditingController(text: h?.host ?? '');
    _port = TextEditingController(text: (h?.port ?? 22).toString());
    _username = TextEditingController(text: h?.username ?? '');
    _password = TextEditingController();
    _privateKey = TextEditingController();
    _passphrase = TextEditingController();
    _authMethod = h?.authMethod ?? AuthMethod.password;
    if (h != null) {
      _loadSecrets(h.id);
    }
  }

  Future<void> _loadSecrets(String id) async {
    setState(() => _loadingSecrets = true);
    final cred = await context.read<HostStore>().credentialFor(id);
    if (!mounted) return;
    _password.text = cred.password ?? '';
    _privateKey.text = cred.privateKeyPem ?? '';
    _passphrase.text = cred.passphrase ?? '';
    setState(() => _loadingSecrets = false);
  }

  @override
  void dispose() {
    _label.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _privateKey.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final existing = widget.existing;
    final host = Host(
      id: existing?.id ?? Host.newId(),
      label: _label.text.trim(),
      host: _host.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? 22,
      username: _username.text.trim(),
      authMethod: _authMethod,
    );
    final credential = _authMethod == AuthMethod.password
        ? Credential(password: _password.text)
        : Credential(
            privateKeyPem: _privateKey.text.trim(),
            passphrase: _passphrase.text.isEmpty ? null : _passphrase.text,
          );

    try {
      await context.read<HostStore>().upsert(host, credential: credential);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? '添加主机' : '编辑主机')),
      body: AbsorbPointer(
        absorbing: _loadingSecrets,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _label2('名称（可选）'),
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(
                  hintText: '例如 家里台式机',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              _label2('主机名 / IP'),
              TextFormField(
                controller: _host,
                decoration: const InputDecoration(
                  hintText: '例如 my-desktop（Tailscale MagicDNS 名）',
                ),
                autocorrect: false,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请填写主机名' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label2('用户名'),
                        TextFormField(
                          controller: _username,
                          decoration:
                              const InputDecoration(hintText: 'root / ubuntu…'),
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? '请填写用户名'
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label2('端口'),
                        TextFormField(
                          controller: _port,
                          decoration: const InputDecoration(hintText: '22'),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final p = int.tryParse((v ?? '').trim());
                            if (p == null || p < 1 || p > 65535) {
                              return '无效';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _label2('认证方式'),
              SegmentedButton<AuthMethod>(
                segments: const [
                  ButtonSegment(
                    value: AuthMethod.password,
                    label: Text('密码'),
                    icon: Icon(Icons.password_rounded),
                  ),
                  ButtonSegment(
                    value: AuthMethod.privateKey,
                    label: Text('密钥'),
                    icon: Icon(Icons.key_rounded),
                  ),
                ],
                selected: {_authMethod},
                onSelectionChanged: (s) =>
                    setState(() => _authMethod = s.first),
              ),
              const SizedBox(height: 16),
              if (_authMethod == AuthMethod.password) ...[
                _label2('密码'),
                TextFormField(
                  controller: _password,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: '登录密码',
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded),
                      onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
              ] else ...[
                _label2('私钥（PEM）'),
                TextFormField(
                  controller: _privateKey,
                  minLines: 4,
                  maxLines: 8,
                  autocorrect: false,
                  style: const TextStyle(fontFamily: AppTheme.monoFont, fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: '-----BEGIN OPENSSH PRIVATE KEY-----…',
                  ),
                ),
                const SizedBox(height: 16),
                _label2('私钥密码短语（可选）'),
                TextFormField(
                  controller: _passphrase,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: '加密的私钥才需要',
                  ),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_saving ? '保存中…' : '保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label2(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(
          text,
          style: const TextStyle(
            color: AppTheme.textDim,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
}
