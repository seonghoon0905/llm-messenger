import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_style.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  String _selectedRoomId = "all";

  // Temporary dataset (To be replaced with DB/LLM integration)
  final Map<String, dynamic> _dataStore = {
    "all": {
      "name": "전체 평균",
      "leary": [60, 70, 40, 30],
      "big5": [70, 60, 80, 75, 20],
    },
    "room1": {
      "name": "팀 프로젝트 방",
      "leary": [85, 40, 15, 60],
      "big5": [50, 90, 40, 60, 30],
    },
    "room2": {
      "name": "동아리 친구들",
      "leary": [30, 90, 70, 10],
      "big5": [90, 30, 95, 85, 10],
    },
  };

  @override
  Widget build(BuildContext context) {
    final currentData = _dataStore[_selectedRoomId];

    return Scaffold(
      backgroundColor: AppStyle.backgroundGrey,
      appBar: AppBar(
        title: const Text(
          "성격 대시보드",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Room selector button
          _buildRoomSelector(),
          const SizedBox(width: 20),
        ],
      ),
      // Single screen layout without scrolling (Fixed layout in Safe Area)
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Indicator for currently viewed data
            _buildCurrentViewHeader(currentData['name']),
            const SizedBox(height: 12),

            // Leary Model Section (Chart + Image space)
            Expanded(
              flex: 1,
              child: _buildAnalysisSection(
                title: "Leary 대인관계 모델 분석",
                chart: _buildRadarChart(currentData['leary'], [
                  '주도',
                  '우호',
                  '순응',
                  '적대',
                ], AppStyle.primaryBlue),
                color: AppStyle.primaryBlue,
              ),
            ),
            const SizedBox(height: 12),

            // Big-5 Model Section (Chart + Image space)
            Expanded(
              flex: 1,
              child: _buildAnalysisSection(
                title: "Big-5 성격 지표 분석",
                chart: _buildRadarChart(currentData['big5'], [
                  'O',
                  'C',
                  'E',
                  'A',
                  'N',
                ], AppStyle.statOpenness),
                color: AppStyle.statOpenness,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // UI Builder Functions

  Widget _buildRoomSelector() {
    return PopupMenuButton<String>(
      onSelected: (value) => setState(() => _selectedRoomId = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppStyle.primaryBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Text(
              "대화창 선택",
              style: TextStyle(
                color: AppStyle.primaryBlue,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: AppStyle.primaryBlue),
          ],
        ),
      ),
      itemBuilder: (context) => _dataStore.entries.map((e) {
        return PopupMenuItem(value: e.key, child: Text(e.value['name']));
      }).toList(),
    );
  }

  Widget _buildAnalysisSection({
    required String title,
    required Widget chart,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              children: [
                // Left: Radar Chart
                Expanded(flex: 3, child: chart),
                const SizedBox(width: 16),
                // Right: Image placeholder
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: color.withValues(alpha: 0.2),
                        style: BorderStyle.none,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            color: color.withValues(alpha: 0.5),
                            size: 30,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "AI 페르소나\n이미지 공간",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: color.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadarChart(List<int> values, List<String> labels, Color color) {
    return RadarChart(
      RadarChartData(
        radarBorderData: const BorderSide(color: Colors.transparent),
        radarShape: RadarShape.circle,
        getTitle: (index, angle) =>
            RadarChartTitle(text: labels[index], angle: angle),
        dataSets: [
          RadarDataSet(
            fillColor: color.withValues(alpha: 0.25),
            borderColor: color,
            entryRadius: 2,
            dataEntries: values
                .map((v) => RadarEntry(value: v.toDouble()))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentViewHeader(String name) {
    return Row(
      children: [
        const Icon(Icons.analytics_outlined, size: 18, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          "현재 분석 데이터: ",
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: AppStyle.primaryBlue,
          ),
        ),
      ],
    );
  }
}
