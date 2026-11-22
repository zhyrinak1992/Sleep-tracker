import 'package:flutter/material.dart';
import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'moon_phase_analytics.dart';

class MoonPhaseScreen extends StatefulWidget {
  const MoonPhaseScreen({super.key, required this.database});
  final SleepDatabase database;
  @override
  State<MoonPhaseScreen> createState() => _MoonPhaseScreenState();
}

class _MoonPhaseScreenState extends State<MoonPhaseScreen> {
  late Future<List<SleepSession>> _future;
  @override
  void initState() { super.initState(); _future=widget.database.getSessions(limit:10000); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Сон и фазы Луны')),
    body: FutureBuilder<List<SleepSession>>(
      future:_future,
      builder:(context,state) {
        if(state.connectionState==ConnectionState.waiting) return const Center(child:CircularProgressIndicator());
        if(state.hasError) return Center(child:Text('Не удалось загрузить историю: ${state.error}'));
        final sessions=state.data??const <SleepSession>[];
        final groups=MoonPhaseAnalytics.summarize(sessions);
        final usable=sessions.where((s)=>s.endedAt!=null && s.endedAt!.isAfter(s.startedAt)).length;
        return ListView(padding:const EdgeInsets.all(20),children:[
          const Text('Сопоставление с астрономической фазой Луны',style:TextStyle(color:AppTheme.muted)),
          const SizedBox(height:8),
          const Text('Для каждой завершённой ночи фаза определяется по середине фактического интервала сна. Если фаза менялась в течение ночи, это можно увидеть в карточке ниже.',style:TextStyle(color:AppTheme.muted,fontSize:12,height:1.45)),
          const SizedBox(height:14),
          SectionCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('Накопленные данные',style:TextStyle(fontWeight:FontWeight.w700)),
            const SizedBox(height:8),
            Text('Завершённых ночей с корректным интервалом: $usable'),
            const SizedBox(height:4),
            const Text('Фаза и освещённость рассчитываются локально по времени, без геолокации и внешнего API.',style:TextStyle(color:AppTheme.muted,fontSize:12)),
          ])),
          const SizedBox(height:12),
          ...groups.where((g)=>g.count>0).map((g)=>Padding(
            padding:const EdgeInsets.only(bottom:9),
            child:SectionCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[Expanded(child:Text(g.label,style:const TextStyle(fontWeight:FontWeight.w700))),Text('${g.count} ночей',style:const TextStyle(color:AppTheme.muted,fontSize:12))]),
              const SizedBox(height:10),
              _row('Средняя длительность',MoonPhaseAnalytics.duration(g.averageDurationMinutes)),
              _row('Средняя оценка самочувствия',g.averageRating==null?'Нет оценок':'${g.averageRating!.toStringAsFixed(1)} / 5'),
              _row('Освещённость на середину ночи',MoonPhaseAnalytics.percent(g.averageIllumination)),
            ])),
          )),
          if(usable==0) const SectionCard(child:Text('Пока нет завершённых ночей для сопоставления.')),
          const SizedBox(height:8),
          const Text('Фаза Луны и процент освещённости — расчётная астрономическая оценка, а не измерение яркости в спальне. Облачность, здания и освещение помещения не учитываются. Наблюдаемые совпадения не означают, что Луна влияет на сон; при малой выборке выводы делать нельзя.',style:TextStyle(color:AppTheme.muted,fontSize:12,height:1.45)),
        ]);
      },
    ),
  );

  Widget _row(String label,String value)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:4),
    child:Row(children:[Expanded(child:Text(label,style:const TextStyle(color:AppTheme.muted))),Text(value,style:const TextStyle(fontWeight:FontWeight.w600))]),
  );
}
