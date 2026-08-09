import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../theme/garden_theme.dart';
import '../../widgets/garden_loading_indicator.dart';

/// Reporte financiero mensual — libro diario (partida doble), estado de
/// resultados, descarga de PDF para mostrar a los socios, y carga de
/// asientos manuales (aportes de capital, gastos operativos) que el
/// sistema no puede ver solo. NO reemplaza el libro oficial que ya lleva
/// el contador externo de la empresa — es un reporte gerencial interno.
class AdminFinanceScreen extends StatefulWidget {
  final String adminToken;
  const AdminFinanceScreen({super.key, required this.adminToken});

  @override
  State<AdminFinanceScreen> createState() => _AdminFinanceScreenState();
}

class _AdminFinanceScreenState extends State<AdminFinanceScreen> {
  String get _baseUrl => const String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  Map<String, dynamic>? _ledger;
  List<dynamic> _accounts = [];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
    _loadLedger();
  }

  Future<void> _loadAccounts() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/admin/ledger/accounts'),
          headers: {'Authorization': 'Bearer ${widget.adminToken}'});
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) setState(() => _accounts = data['data'] as List);
    } catch (_) {}
  }

  Future<void> _loadLedger() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/admin/ledger/${_selectedMonth.year}/${_selectedMonth.month}'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      final data = jsonDecode(res.body);
      if (mounted && data['success'] == true) setState(() => _ledger = data['data'] as Map<String, dynamic>);
    } catch (_) {
      if (mounted) {
        GardenErrorDialog.show(context, 'No se pudo cargar el libro contable');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadPdf() async {
    final url = '$_baseUrl/admin/ledger/${_selectedMonth.year}/${_selectedMonth.month}/pdf'
        '?token=${Uri.encodeComponent(widget.adminToken)}';
    // El endpoint requiere Authorization Bearer, pero un link de descarga
    // no puede mandar headers — se abre en el navegador, que no tiene el
    // token. Por eso se descarga acá mismo con http y se abre el resultado.
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/admin/ledger/${_selectedMonth.year}/${_selectedMonth.month}/pdf'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      if (res.statusCode == 200) {
        // No hay File System access simple y multiplataforma acá dentro del
        // admin panel — se abre el PDF ya descargado como data URL, que el
        // navegador ofrece guardar o ver directo.
        final b64 = base64Encode(res.bodyBytes);
        await launchUrl(Uri.parse('data:application/pdf;base64,$b64'), mode: LaunchMode.externalApplication);
      } else if (mounted) {
        GardenErrorDialog.show(context, 'No se pudo generar el PDF');
      }
    } catch (e) {
      if (mounted) {
        GardenErrorDialog.show(context, 'Error: $e');
      }
    }
  }

  void _changeMonth(int deltaMonths) {
    setState(() => _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + deltaMonths));
    _loadLedger();
  }

  Future<void> _showManualEntryDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => _ManualEntryDialog(
        baseUrl: _baseUrl,
        token: widget.adminToken,
        accounts: _accounts,
        onSaved: _loadLedger,
      ),
    );
  }

  static const _meses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;
    final estado = _ledger?['estadoResultados'] as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Finanzas', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(icon: Icon(Icons.chevron_left_rounded, color: textColor), onPressed: () => _changeMonth(-1)),
                Text('${_meses[_selectedMonth.month - 1]} ${_selectedMonth.year}',
                    style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                IconButton(icon: Icon(Icons.chevron_right_rounded, color: textColor), onPressed: () => _changeMonth(1)),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _downloadPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                  label: const Text('Descargar PDF'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _showManualEntryDialog,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Asiento manual'),
                  style: ElevatedButton.styleFrom(backgroundColor: GardenColors.primary, foregroundColor: Colors.white),
                ),
              ],
            ),
            Text('Reporte gerencial interno para socios — no reemplaza el libro oficial del contador.',
                style: TextStyle(color: subtextColor, fontSize: 11.5)),
            const SizedBox(height: 20),
            if (_loading)
              const Expanded(child: Center(child: GardenLoadingIndicator(color: GardenColors.primary)))
            else if (estado == null)
              Expanded(child: Center(child: Text('Sin datos', style: TextStyle(color: subtextColor))))
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: _statCard('Ingresos', estado['totalIngresos'], GardenColors.success, surface, borderColor, textColor, subtextColor)),
                          const SizedBox(width: 12),
                          Expanded(child: _statCard('Gastos', estado['totalGastos'], GardenColors.warning, surface, borderColor, textColor, subtextColor)),
                          const SizedBox(width: 12),
                          Expanded(child: _statCard('Utilidad neta', estado['utilidad'],
                              (estado['utilidad'] as num) >= 0 ? GardenColors.success : GardenColors.error, surface, borderColor, textColor, subtextColor)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text('Detalle de ingresos', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      ...((estado['ingresos'] as List?) ?? []).map((i) => _lineRow(i, textColor, subtextColor)),
                      const SizedBox(height: 20),
                      Text('Detalle de gastos', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      ...((estado['gastos'] as List?) ?? []).map((i) => _lineRow(i, textColor, subtextColor)),
                      const SizedBox(height: 24),
                      Text('Libro diario (${(_ledger!['entries'] as List).length} asientos)',
                          style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      ...((_ledger!['entries'] as List).map((e) => _entryCard(e as Map<String, dynamic>, surface, borderColor, textColor, subtextColor))),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, dynamic amount, Color accent, Color surface, Color borderColor, Color textColor, Color subtextColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Bs ${(amount as num).toStringAsFixed(2)}', style: TextStyle(color: accent, fontSize: 20, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _lineRow(dynamic item, Color textColor, Color subtextColor) {
    final m = item as Map<String, dynamic>;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${m['code']} — ${m['name']}', style: TextStyle(color: subtextColor, fontSize: 12.5)),
          Text('Bs ${(m['amount'] as num).toStringAsFixed(2)}', style: TextStyle(color: textColor, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _entryCard(Map<String, dynamic> entry, Color surface, Color borderColor, Color textColor, Color subtextColor) {
    final lines = entry['lines'] as List;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(entry['description'] as String, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 12.5))),
              Text((entry['date'] as String).split('T').first, style: TextStyle(color: subtextColor, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          ...lines.map((l) {
            final line = l as Map<String, dynamic>;
            final account = line['account'] as Map<String, dynamic>;
            final debit = (line['debit'] as num).toDouble();
            final credit = (line['credit'] as num).toDouble();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                children: [
                  Expanded(child: Text('${account['code']} ${account['name']}', style: TextStyle(color: subtextColor, fontSize: 11))),
                  SizedBox(width: 70, child: Text(debit > 0 ? 'Bs ${debit.toStringAsFixed(2)}' : '', textAlign: TextAlign.right, style: TextStyle(color: textColor, fontSize: 11))),
                  SizedBox(width: 70, child: Text(credit > 0 ? 'Bs ${credit.toStringAsFixed(2)}' : '', textAlign: TextAlign.right, style: TextStyle(color: textColor, fontSize: 11))),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ManualEntryDialog extends StatefulWidget {
  final String baseUrl;
  final String token;
  final List<dynamic> accounts;
  final VoidCallback onSaved;

  const _ManualEntryDialog({required this.baseUrl, required this.token, required this.accounts, required this.onSaved});

  @override
  State<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends State<_ManualEntryDialog> {
  final _descController = TextEditingController();
  final _dateController = TextEditingController(text: DateTime.now().toIso8601String().split('T').first);
  String? _debitAccount;
  String? _creditAccount;
  final _amountController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _descController.dispose();
    _dateController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (_debitAccount == null || _creditAccount == null || amount <= 0 || _descController.text.trim().isEmpty) {
      setState(() => _error = 'Completá cuenta de débito, cuenta de crédito, monto y descripción');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/admin/ledger/manual-entry'),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'date': _dateController.text,
          'description': _descController.text.trim(),
          'lines': [
            {'accountCode': _debitAccount, 'debit': amount, 'credit': 0},
            {'accountCode': _creditAccount, 'debit': 0, 'credit': amount},
          ],
        }),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        widget.onSaved();
        if (mounted) Navigator.pop(context);
      } else if (mounted) {
        setState(() => _error = data['error']?['message'] ?? 'No se pudo guardar');
      }
    } catch (e) {
      setState(() => _error = 'Error de conexión');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Asiento manual'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Para aportes de capital, gastos operativos, sueldos, etc. — lo que el sistema no puede ver solo.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(controller: _dateController, decoration: const InputDecoration(labelText: 'Fecha (YYYY-MM-DD)')),
            const SizedBox(height: 10),
            TextField(controller: _descController, decoration: const InputDecoration(labelText: 'Descripción'), maxLines: 2),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _debitAccount,
              decoration: const InputDecoration(labelText: 'Cuenta que aumenta (Debe)'),
              items: widget.accounts.map((a) => DropdownMenuItem(value: a['code'] as String, child: Text('${a['code']} — ${a['name']}'))).toList(),
              onChanged: (v) => setState(() => _debitAccount = v),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _creditAccount,
              decoration: const InputDecoration(labelText: 'Cuenta que disminuye / origen (Haber)'),
              items: widget.accounts.map((a) => DropdownMenuItem(value: a['code'] as String, child: Text('${a['code']} — ${a['name']}'))).toList(),
              onChanged: (v) => setState(() => _creditAccount = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto (Bs)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando...' : 'Guardar')),
      ],
    );
  }
}
