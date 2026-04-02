// widgets/analysis_charts.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/personality_status.dart';
import '../constants/app_style.dart';

// 1. Leary 대인관계 모델 그래프 (4축)
class LearyRadarChart extends StatelessWidget {
  final LearyData data;

  const LearyRadarChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.3,
      child: RadarChart(
        RadarChartData(
          dataSets: [
            RadarDataSet(
              fillColor: AppStyle.primaryBlue.withOpacity(0.2),
              borderColor: AppStyle.primaryBlue,
              entryRadius: 3,
              dataEntries: [
                // image_1.png의 축 순서대로 배치 (주도, 우호, 순응, 적대)
                RadarEntry(value: data.dominanceScore.toDouble()),     // 상: 주도
                RadarEntry(value: data.friendlinessScore.toDouble()),   // 우: 우호
                RadarEntry(value: (100 - data.dominanceScore).toDouble()), // 하: 순응
                RadarEntry(value: (100 - data.friendlinessScore).toDouble()), // 좌: 적대
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 2. Big-5 모델 그래프 (5축)
class BigFiveRadarChart extends StatelessWidget {
  final BigFiveData data;

  const BigFiveRadarChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.3,
      child: RadarChart(
        RadarChartData(
          dataSets: [
            RadarDataSet(
              fillColor: AppStyle.statOpenness.withOpacity(0.2),
              borderColor: AppStyle.statOpenness,
              entryRadius: 3,
              dataEntries: [
                // image_2.png의 O C E A N 순서
                RadarEntry(value: data.openness * 100),
                RadarEntry(value: data.conscientiousness * 100),
                RadarEntry(value: data.extraversion * 100),
                RadarEntry(value: data.agreeableness * 100),
                RadarEntry(value: (1 - data.neuroticism) * 100), // Stability로 변환
              ],
            ),
          ],
        ),
      ),
    );
  }
}