import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_style.dart';
import '../models/chat_room.dart';
import '../models/message.dart';
import '../services/db_helper.dart';
import '../services/api_service.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  List<ChatRoom> _chatRooms = [];
  ChatRoom? _selectedRoom; // null = 전체 평균
  bool _isLoadingRooms = true;
  bool _isAnalyzing = false;
  String? _analysisError;

  // Cache: roomId(or "__all__") → {dominance, affiliation, analyzed_count, quadrant}
  final Map<String, Map<String, dynamic>> _scoreCache = {};

  // ─── Quadrant → 캐릭터명 매핑 ───────────────────────────────────────────────
  static const Map<String, String> _quadrantLabel = {
    'leading-friendly':  '리더형',
    'leading-neutral':   '추진형',
    'leading-hostile':   '압박형',
    'balanced-friendly': '협력형',
    'balanced-neutral':  '중립형',
    'balanced-hostile':  '방어형',
    'following-friendly':'배려형',
    'following-neutral': '관망형',
    'following-hostile': '반항형',
  };

  // ─── Quadrant → 아이콘 이미지 경로 매핑 ────────────────────────────────────
  static const Map<String, String> _quadrantIcon = {
    'leading-friendly':  'icon/책임적.png',
    'leading-neutral':   'icon/지배적.png',
    'leading-hostile':   'icon/독재적.png',
    'balanced-friendly': 'icon/협력적.png',
    'balanced-neutral':  'icon/평범적.png',
    'balanced-hostile':  'icon/의심적.png',
    'following-friendly':'icon/순응적.png',
    'following-neutral': 'icon/의존적.png',
    'following-hostile': 'icon/반항적.png',
  };

  static const String _defaultQuadrant  = 'balanced-neutral';
  static const String _defaultIconPath  = 'icon/평범적.png';
  static const String _defaultCharLabel = '중립형';

  static const _allKey = '__all__';
  static const _maxMsgsPerRoom = 30; // 전체 분석 시 방당 최대 메시지 수
  static const _maxMsgsRoom = 80;    // 단일 방 분석 시 최대 메시지 수

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final rooms = await DBHelper().getChatRooms();
    setState(() {
      _chatRooms = rooms;
      _isLoadingRooms = false;
    });
    // 화면 열리면 자동으로 전체 분석 시작
    _triggerAnalysis(null);
  }

  // ─── Analysis Logic ───────────────────────────────────────────────────────

  Future<void> _triggerAnalysis(ChatRoom? room) async {
    final cacheKey = room?.id ?? _allKey;
    if (_scoreCache.containsKey(cacheKey)) {
      setState(() => _selectedRoom = room);
      return;
    }

    setState(() {
      _selectedRoom = room;
      _isAnalyzing = true;
      _analysisError = null;
    });

    try {
      final List<Message> messages;

      if (room == null) {
        // 전체: 각 방에서 최근 N개씩 합산
        final buffer = <Message>[];
        for (final r in _chatRooms) {
          final roomMsgs = await DBHelper().getMessages(r.id);
          buffer.addAll(roomMsgs.reversed.take(_maxMsgsPerRoom));
        }
        messages = buffer;
      } else {
        final all = await DBHelper().getMessages(room.id);
        messages = all.reversed.take(_maxMsgsRoom).toList();
      }

      final myCount =
          messages.where((m) => m.isMe && !m.isDeleted).length;

      if (myCount == 0) {
        setState(() {
          _scoreCache[cacheKey] = {
            'dominance': 50.0,
            'affiliation': 50.0,
            'analyzed_count': 0,
            'quadrant': _defaultQuadrant,
          };
          _isAnalyzing = false;
        });
        return;
      }

      final payload = messages
          .where((m) => !m.isDeleted && m.displayText.trim().isNotEmpty)
          .map((m) => {
                'role': m.isMe ? 'me' : 'partner',
                'text': m.displayText,
              })
          .toList();

      final result =
          await ApiService().analyzeLeary(messages: payload);

      if (!mounted) return;
      setState(() {
        _scoreCache[cacheKey] = {
          'dominance':        (result['dominance']         as num? ?? 50).toDouble(),
          'affiliation':      (result['affiliation']       as num? ?? 50).toDouble(),
          'analyzed_count':   (result['analyzed_count']    as num? ?? myCount).toDouble(),
          'my_message_count': (result['my_message_count']  as num? ?? myCount).toDouble(),
          'quadrant':         result['quadrant'] as String? ?? _defaultQuadrant,
        };
        _isAnalyzing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analysisError = '분석 중 오류가 발생했습니다.\n백엔드 서버 연결을 확인해주세요.';
        _isAnalyzing = false;
      });
    }
  }

  // ─── Derived Values ───────────────────────────────────────────────────────

  String get _cacheKey => _selectedRoom?.id ?? _allKey;

  Map<String, dynamic>? get _scores => _scoreCache[_cacheKey];

  double _scoreDouble(String key) =>
      (_scores?[key] as num? ?? 50).toDouble();

  String get _currentQuadrant =>
      _scores?['quadrant'] as String? ?? _defaultQuadrant;

  /// [주도, 우호, 순응, 적대]
  List<double> get _learyValues {
    final dom = _scoreDouble('dominance');
    final aff = _scoreDouble('affiliation');
    return [dom, aff, 100 - dom, 100 - aff];
  }

  String get _selectedLabel =>
      _selectedRoom == null ? '전체 평균' : _selectedRoom!.title;

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyle.backgroundGrey,
      appBar: AppBar(
        backgroundColor: AppStyle.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: AppStyle.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('성격 분석 리포트',
            style: AppStyle.appBarTitleStyle),
        actions: [
          if (!_isLoadingRooms) _buildRoomSelector(),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppStyle.divider),
        ),
      ),
      body: _isLoadingRooms
          ? const Center(
              child: CircularProgressIndicator(color: AppStyle.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildCurrentViewHeader(),
                  const SizedBox(height: 16),
                  _buildLearyCard(),
                  const SizedBox(height: 16),
                  _buildAxisExplanation(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // ─── Room Selector ────────────────────────────────────────────────────────

  Widget _buildRoomSelector() {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == _allKey) {
          _triggerAnalysis(null);
        } else {
          final room = _chatRooms.firstWhere((r) => r.id == value);
          _triggerAnalysis(room);
        }
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppStyle.primaryLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline_rounded,
                size: 15, color: AppStyle.primary),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 90),
              child: Text(
                _selectedLabel,
                style: const TextStyle(
                  color: AppStyle.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down_rounded,
                color: AppStyle.primary, size: 18),
          ],
        ),
      ),
      itemBuilder: (context) => [
        _buildMenuItem(_allKey, '전체 평균', null,
            icon: Icons.bar_chart_rounded),
        if (_chatRooms.isNotEmpty) const PopupMenuDivider(),
        ..._chatRooms.map((room) =>
            _buildMenuItem(room.id, room.title, room.relation)),
      ],
    );
  }

  PopupMenuItem<String> _buildMenuItem(
    String value,
    String title,
    String? subtitle, {
    IconData? icon,
  }) {
    final avatarColor = icon != null
        ? AppStyle.primary
        : AppStyle.getAvatarColor(title);
    final initial = icon != null ? null : AppStyle.getInitial(title);

    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: icon != null
                  ? AppStyle.primaryLight
                  : avatarColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 17, color: AppStyle.primary)
                  : Text(
                      initial!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppStyle.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Header Card ──────────────────────────────────────────────────────────

  Widget _buildCurrentViewHeader() {
    final avatarColor = _selectedRoom != null
        ? AppStyle.getAvatarColor(_selectedRoom!.title)
        : AppStyle.primary;
    final initial = _selectedRoom != null
        ? AppStyle.getInitial(_selectedRoom!.title)
        : null;
    final analyzedCount =
        (_scores?['my_message_count'] as num?)?.toInt();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppStyle.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: avatarColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: initial != null
                  ? Text(initial,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800))
                  : const Icon(Icons.bar_chart_rounded,
                      color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppStyle.textPrimary,
                  ),
                ),
                Text(
                  _selectedRoom != null
                      ? '${_selectedRoom!.relation} · 대화 기반 분석'
                      : '모든 대화방 종합',
                  style: const TextStyle(
                      fontSize: 12, color: AppStyle.textSecondary),
                ),
              ],
            ),
          ),
          if (analyzedCount != null && !_isAnalyzing)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppStyle.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '내 메시지 $analyzedCount개',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppStyle.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Leary Card ───────────────────────────────────────────────────────────

  Widget _buildLearyCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppStyle.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppStyle.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.radar_rounded,
                    color: AppStyle.primary, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Leary 대인관계 모델',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppStyle.textPrimary,
                      ),
                    ),
                    Text(
                      '주도–순응 / 우호–적대 2축 분석',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: AppStyle.textSecondary),
                    ),
                  ],
                ),
              ),
              if (_isAnalyzing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: AppStyle.primary, strokeWidth: 2.5),
                ),
            ],
          ),
          const SizedBox(height: 20),

          if (_analysisError != null)
            _buildErrorState()
          else if (_isAnalyzing && _scores == null)
            _buildLoadingState()
          else
            _buildChartAndBars(),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            CircularProgressIndicator(color: AppStyle.primary),
            SizedBox(height: 16),
            Text(
              '대화 내용을 분석하는 중...',
              style: TextStyle(
                  color: AppStyle.textSecondary, fontSize: 14),
            ),
            SizedBox(height: 4),
            Text(
              '메시지 수에 따라 시간이 걸릴 수 있습니다',
              style: TextStyle(
                  color: AppStyle.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 40, color: AppStyle.textTertiary),
            const SizedBox(height: 12),
            Text(
              _analysisError ?? '분석에 실패했습니다.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppStyle.textSecondary, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _triggerAnalysis(_selectedRoom),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('다시 시도'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppStyle.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartAndBars() {
    final values = _learyValues;
    const labels = ['주도', '우호', '순응', '적대'];
    const colors = [
      Color(0xFF2563EB),
      Color(0xFF10B981),
      Color(0xFF8B5CF6),
      Color(0xFFEF4444),
    ];

    final dominance   = _scoreDouble('dominance');
    final affiliation = _scoreDouble('affiliation');

    return Column(
      children: [
        // Radar + bar 나란히
        SizedBox(
          height: 220,
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: _buildRadarChart(values, labels),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _buildScoreBar(
                        label: labels[i],
                        value: values[i],
                        color: colors[i],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // 포지션 요약 배지
        _buildPositionSummary(dominance, affiliation),
      ],
    );
  }

  Widget _buildRadarChart(List<double> values, List<String> labels) {
    return RadarChart(
      RadarChartData(
        radarBorderData: const BorderSide(color: Colors.transparent),
        tickBorderData:
            BorderSide(color: AppStyle.border, width: 0.5),
        gridBorderData:
            BorderSide(color: AppStyle.divider, width: 0.5),
        radarShape: RadarShape.circle,
        tickCount: 4,
        getTitle: (index, angle) =>
            RadarChartTitle(text: labels[index], angle: angle),
        titleTextStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppStyle.textSecondary,
        ),
        dataSets: [
          RadarDataSet(
            fillColor: AppStyle.primary.withValues(alpha: 0.2),
            borderColor: AppStyle.primary,
            borderWidth: 2,
            entryRadius: 3,
            dataEntries:
                values.map((v) => RadarEntry(value: v)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreBar({
    required String label,
    required double value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color)),
            Text(
              value == 0 ? '-' : value.toStringAsFixed(0),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: value / 100,
            backgroundColor: color.withValues(alpha: 0.12),
            color: color,
            minHeight: 7,
          ),
        ),
      ],
    );
  }

  // quadrant 축(dom/aff)별 배지 색상
  static Color _quadrantColor(String quadrant) {
    if (quadrant.contains('friendly')) return const Color(0xFF10B981);
    if (quadrant.contains('hostile'))  return const Color(0xFFEF4444);
    if (quadrant.startsWith('leading'))  return const Color(0xFF2563EB);
    if (quadrant.startsWith('following')) return const Color(0xFF8B5CF6);
    return const Color(0xFF6B7280);
  }

  Widget _buildPositionSummary(double dominance, double affiliation) {
    final quadrant  = _currentQuadrant;
    final charLabel = _quadrantLabel[quadrant] ?? _defaultCharLabel;
    final iconPath  = _quadrantIcon[quadrant]  ?? _defaultIconPath;
    final color     = _quadrantColor(quadrant);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          // 캐릭터 아이콘 이미지
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              iconPath,
              width: 64,
              height: 64,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.person_rounded, color: color, size: 32),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      charLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '이 관계에서의 성향',
                      style: TextStyle(
                        fontSize: 12,
                        color: color.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    quadrant,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color.withValues(alpha: 0.85),
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

  // ─── Axis Explanation ─────────────────────────────────────────────────────

  static const Map<String, String> _quadrantDesc = {
    'leading-friendly':  '대화를 주도하면서도 따뜻하고 배려 있는 소통을 합니다. 상대방이 편안하게 따를 수 있는 리더십을 보입니다.',
    'leading-neutral':   '대화에서 방향을 제시하고 진행을 이끌지만, 감정 표현은 중립적인 편입니다. 목표 지향적인 소통 스타일입니다.',
    'leading-hostile':   '강한 주도권을 행사하지만 표현이 다소 차갑거나 압박적으로 느껴질 수 있습니다. 관계에서 긴장감이 생길 수 있습니다.',
    'balanced-friendly': '주도와 순응 사이에서 유연하게 균형을 잡으며, 따뜻하고 협력적인 분위기를 만듭니다.',
    'balanced-neutral':  '특별히 주도하거나 따르지 않고 중립적인 위치를 유지합니다. 감정 표현도 절제된 편입니다.',
    'balanced-hostile':  '주도권은 균형적이지만 감정 표현이 방어적이거나 차가운 편입니다. 경계를 두고 소통하는 경향이 있습니다.',
    'following-friendly':'상대방의 흐름에 맞추며 편안하고 부드럽게 반응합니다. 갈등을 피하고 조화를 중시합니다.',
    'following-neutral': '대화에서 주로 반응하는 역할을 하며, 감정 표현이 많지 않습니다. 조용히 상황을 관망하는 편입니다.',
    'following-hostile': '주도권은 낮지만 표현이 차갑거나 방어적입니다. 불만을 직접 표현하지 않고 소극적으로 저항하는 경향이 있습니다.',
  };

  Widget _buildAxisExplanation() {
    final quadrant  = _currentQuadrant;
    final charLabel = _quadrantLabel[quadrant] ?? _defaultCharLabel;
    final charDesc  = _quadrantDesc[quadrant]  ?? '분석 결과를 바탕으로 대화 성향을 파악합니다.';
    final color     = _quadrantColor(quadrant);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppStyle.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '지표 설명',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: AppStyle.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          // 현재 성향 설명 카드 (분석 완료 후에만 표시)
          if (!_isAnalyzing && _scores != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_search_rounded, size: 15, color: color),
                    const SizedBox(width: 6),
                    Text(
                      '$charLabel 성향',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  charDesc,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: color.withValues(alpha: 0.85),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildAxisRow(
            color: const Color(0xFF2563EB),
            icon: Icons.arrow_upward_rounded,
            label: '주도',
            desc: '대화를 먼저 이끌거나 제안·요청하는 비율',
          ),
          _buildAxisRow(
            color: const Color(0xFF10B981),
            icon: Icons.favorite_rounded,
            label: '우호',
            desc: '따뜻한 감정 표현, 공감, 배려하는 말투의 비율',
          ),
          _buildAxisRow(
            color: const Color(0xFF8B5CF6),
            icon: Icons.arrow_downward_rounded,
            label: '순응',
            desc: '상대의 흐름에 따르는 정도 (주도의 반대)',
          ),
          _buildAxisRow(
            color: const Color(0xFFEF4444),
            icon: Icons.bolt_rounded,
            label: '적대',
            desc: '차갑거나 방어적인 표현의 정도 (우호의 반대)',
            isLast: true,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppStyle.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 13, color: AppStyle.textTertiary),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '화행 분석(command/request/question)과 감정 분석(warmth/anger)을 기반으로 계산됩니다.',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppStyle.textTertiary,
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAxisRow({
    required Color color,
    required IconData icon,
    required String label,
    required String desc,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: color)),
                Text(desc,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppStyle.textSecondary,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
