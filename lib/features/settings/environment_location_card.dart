import 'package:flutter/material.dart';

import '../../data/night_environment_service.dart';
import '../../data/sleep_database.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class EnvironmentLocationCard extends StatefulWidget {
  const EnvironmentLocationCard({super.key});
  @override
  State<EnvironmentLocationCard> createState() => _EnvironmentLocationCardState();
}

class _EnvironmentLocationCardState extends State<EnvironmentLocationCard> {
  final TextEditingController _query = TextEditingController();
  late Future<EnvironmentLocation?> _location;
  List<EnvironmentLocation> _results = [];
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _location = NightEnvironmentService.instance.loadLocation();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_searching || _query.text.trim().length < 2) return;
    setState(() { _searching = true; _error = null; _results = []; });
    try {
      final results = await NightEnvironmentService.instance.searchLocations(_query.text);
      if (!mounted) return;
      setState(() {
        _results = results;
        if (results.isEmpty) _error = 'Город не найден. Попробуй уточнить название.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось найти город: $error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _select(EnvironmentLocation value) async {
    await NightEnvironmentService.instance.saveLocation(value);
    if (!mounted) return;
    setState(() {
      _location = NightEnvironmentService.instance.loadLocation();
      _results = [];
      _query.clear();
      _error = null;
    });
  }

  Future<void> _clear() async {
    await NightEnvironmentService.instance.clearLocation();
    if (!mounted) return;
    setState(() {
      _location = NightEnvironmentService.instance.loadLocation();
      _results = [];
    });
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Город для погоды и солнца',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
      const SizedBox(height: 7),
      const Text(
        'Город выбирается вручную. GPS и доступ к точному местоположению не нужны. По выбранным координатам приложение получает архив погоды, восход и закат для анализа ночей.',
        style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45),
      ),
      const SizedBox(height: 10),
      FutureBuilder<EnvironmentLocation?>(
        future: _location,
        builder: (context, state) {
          if (state.connectionState == ConnectionState.waiting) {
            return const LinearProgressIndicator();
          }
          if (state.hasError) {
            return Text('Не удалось прочитать город: ${state.error}',
              style: const TextStyle(color: AppTheme.accentPink, fontSize: 12));
          }
          final current = state.data;
          if (current != null) ...[
            Row(children: [
              const Icon(Icons.location_city_outlined, color: AppTheme.teal),
              const SizedBox(width: 8),
              Expanded(child: Text(current.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600))),
              IconButton(
                tooltip: 'Удалить город',
                onPressed: _clear,
                icon: const Icon(Icons.close),
              ),
            ]),
            const Divider(height: 18, color: AppTheme.surfaceLight),
          ] else
            const Text('Город ещё не выбран.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          Row(children: [
            Expanded(child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: const InputDecoration(
                hintText: 'Название города',
                isDense: true,
              ),
            )),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: _searching ? null : _search,
              icon: _searching
                ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search),
            ),
          ]),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: AppTheme.accentPink, fontSize: 12)),
          ),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._results.map((result) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_outlined, size: 19),
              title: Text(result.displayName, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                '${result.latitude.toStringAsFixed(3)}, ${result.longitude.toStringAsFixed(3)}',
                style: const TextStyle(fontSize: 10, color: AppTheme.muted),
              ),
              onTap: () => _select(result),
            )),
          ],
        },
      ),
      const SizedBox(height: 8),
      const Text('Источник: Open-Meteo. Архивные данные могут поступать с задержкой; если данных за недавнюю ночь ещё нет, приложение покажет отсутствие измерений.',
        style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
    ]),
  );
}
