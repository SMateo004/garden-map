import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../design/garden_icons.dart';
import '../services/auth_state.dart';
import '../theme/garden_theme.dart';

/// Botón "Mejorar con IA" para los campos de texto libre del registro del cuidador.
///
/// - Con texto escrito: la IA lo mejora (ortografía, claridad) sin cambiar lo que dice.
/// - Sin texto: pide unas notas cortas y redacta el párrafo.
/// En ambos casos muestra primero cómo quedaría y el cuidador decide si lo usa.
/// Aparte de este botón, el servidor corrige la ortografía de forma automática antes de
/// publicar el perfil, así que el cliente final nunca ve errores.
///
/// [field] es la clave del campo en el backend (bio, bioDetail, experienceDescription,
/// whyCaregiver, whatDiffers, handleAnxious, emergencyResponse, spaceDescription,
/// typicalDay, breedsWhy).
class AiWriteAssist extends StatefulWidget {
  final TextEditingController controller;
  final String field;

  /// Se llama después de aplicar el texto (para que la pantalla recalcule su estado).
  final VoidCallback? onApplied;

  const AiWriteAssist({
    super.key,
    required this.controller,
    required this.field,
    this.onApplied,
  });

  @override
  State<AiWriteAssist> createState() => _AiWriteAssistState();
}

class _AiWriteAssistState extends State<AiWriteAssist> {
  static const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.gardenbo.com/api');
  static const _minChars = 10;

  bool _loading = false;

  bool get _hasText => widget.controller.text.trim().length >= _minChars;

  Future<void> _onTap() async {
    String? notes;
    if (!_hasText) {
      notes = await _askNotes();
      if (notes == null) return; // canceló
    }

    setState(() => _loading = true);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/caregiver/profile/improve-text'),
        headers: {'Authorization': 'Bearer ${AuthState.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'field': widget.field,
          if (_hasText) 'text': widget.controller.text.trim(),
          if (notes != null) 'notes': notes,
        }),
      );
      Map<String, dynamic> body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        throw const _AiError('El asistente no está disponible ahora. Intenta de nuevo en un momento.');
      }
      if (res.statusCode != 200 || body['success'] != true) {
        throw _AiError((body['error'] as Map?)?['message'] as String? ?? 'No pudimos usar el asistente. Intenta de nuevo.');
      }
      final text = (body['data'] as Map)['text'] as String;
      if (!mounted) return;
      await _preview(text);
    } on _AiError catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No pudimos conectar con el asistente. Revisa tu conexión e intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _askNotes() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cuéntame en pocas palabras'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: 'Ej: llevo 3 años paseando perros, vivo en Equipetrol, me encantan los cachorros',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.length >= 5) Navigator.pop(ctx, v);
            },
            child: const Text('Redactar'),
          ),
        ],
      ),
    );
  }

  Future<void> _preview(String text) async {
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Así quedaría', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text(
                'Revisa que todo sea cierto antes de usarlo: la IA no conoce tus datos reales.',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              Flexible(child: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontSize: 14, height: 1.4)))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Dejar el mío'))),
                  const SizedBox(width: 12),
                  Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usar este texto'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (accepted == true) {
      widget.controller.text = text;
      widget.onApplied?.call();
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _loading ? null : _onTap,
        icon: _loading
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const GardenIcon(GIcon.editar, size: GIconSize.sm, color: GardenColors.primary),
        label: ListenableBuilder(
          listenable: widget.controller,
          builder: (_, __) => Text(
            _loading ? 'Escribiendo...' : (_hasText ? 'Mejorar con IA' : 'Redactar con IA'),
            style: const TextStyle(color: GardenColors.primary, fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _AiError implements Exception {
  final String message;
  const _AiError(this.message);
}
