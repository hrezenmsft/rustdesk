import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/admin_presence_model.dart';
import 'package:provider/provider.dart';

import '../../common.dart';

/// Dialog listing devices currently online with the self-hosted admin
/// presence API, and allowing the user to connect to one of them using
/// RustDesk's normal connection flow (password/consent are never bypassed).
class AdminPresenceDialog extends StatefulWidget {
  const AdminPresenceDialog({Key? key}) : super(key: key);

  @override
  State<AdminPresenceDialog> createState() => _AdminPresenceDialogState();
}

class _AdminPresenceDialogState extends State<AdminPresenceDialog> {
  late TextEditingController _serverController;
  final _tokenController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final model = Provider.of<AdminPresenceModel>(context, listen: false);
    _serverController = TextEditingController(text: model.server);
  }

  @override
  void dispose() {
    _serverController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = Provider.of<AdminPresenceModel>(context);
    return AlertDialog(
      title: Text(translate('Admin - Online Devices')),
      content: SizedBox(
        width: 420,
        child: model.isLoggedIn
            ? _buildDeviceList(context, model)
            : _buildLogin(context, model),
      ),
      actions: [
        if (model.isLoggedIn)
          TextButton(
            onPressed: () => model.logout(),
            child: Text(translate('Logout')),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(translate('Close')),
        ),
      ],
    );
  }

  Widget _buildLogin(BuildContext context, AdminPresenceModel model) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _serverController,
          decoration: InputDecoration(
            labelText: translate('Admin server address (host:port)'),
            hintText: '192.168.0.10:21114',
          ),
          onChanged: model.setServer,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tokenController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: translate('Admin token'),
          ),
          onSubmitted: (_) => _doLogin(model),
        ),
        const SizedBox(height: 12),
        if (model.error != null)
          Text(model.error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: model.loading ? null : () => _doLogin(model),
            child: model.loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(translate('Login')),
          ),
        ),
      ],
    );
  }

  Future<void> _doLogin(AdminPresenceModel model) async {
    final ok = await model.login(_tokenController.text);
    if (ok) {
      _tokenController.clear();
      await model.refreshDevices();
    }
  }

  Widget _buildDeviceList(BuildContext context, AdminPresenceModel model) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(
                    translate('${model.devices.length} device(s) online'))),
            IconButton(
              tooltip: translate('Refresh'),
              icon: const Icon(Icons.refresh),
              onPressed: model.loading ? null : () => model.refreshDevices(),
            ),
          ],
        ),
        if (model.error != null)
          Text(model.error!, style: const TextStyle(color: Colors.red)),
        SizedBox(
          height: 320,
          child: model.devices.isEmpty
              ? Center(child: Text(translate('No devices online')))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: model.devices.length,
                  itemBuilder: (context, index) {
                    final d = model.devices[index];
                    return ListTile(
                      leading: const Icon(Icons.desktop_windows),
                      title: Text(d.id),
                      subtitle: Text(
                          '${translate('Last seen')}: ${d.lastSeenSecs}s'),
                      onTap: () {
                        // Reuse RustDesk's normal connection flow: this
                        // still requires the target's password/consent,
                        // nothing is bypassed here.
                        Navigator.of(context).pop();
                        connect(context, d.id);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

Future<void> showAdminPresenceDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (context) => ChangeNotifierProvider(
      create: (_) => AdminPresenceModel(),
      child: const AdminPresenceDialog(),
    ),
  );
}
