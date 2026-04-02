// models/personality_status.dart
import 'package:flutter/material.dart';

// 1. Leary 대인관계 모델 데이터
class LearyData {
  double dominantConforming;  // 주도적 <-> 순응적
  double friendlyHostile;      // 우호적 <-> 적대적

  LearyData({
    this.dominantConforming = 0.0, // 기본값 (중립)
    this.friendlyHostile = 0.0,
  });

  // UI 표현을 위해 0~100 점수로 변환하는 헬퍼 함수
  int get dominanceScore => (((dominantConforming + 1) / 2) * 100).toInt();
  int get friendlinessScore => (((friendlyHostile + 1) / 2) * 100).toInt();
}

// 2. Big-5 모델 데이터 (O C E A N)
class BigFiveData {
  // 0.0 ~ 1.0 사이의 값
  double openness;
  double conscientiousness;
  double extraversion;
  double agreeableness;
  double neuroticism; // 이미지의 Emotional Stability의 역(逆) 지표

  BigFiveData({
    this.openness = 0.5,
    this.conscientiousness = 0.5,
    this.extraversion = 0.5,
    this.agreeableness = 0.5,
    this.neuroticism = 0.5,
  });
}

// 3. 전체 성격 상태 및 프로필 매칭
class PersonalityStatus {
  String userId;
  LearyData leary;
  BigFiveData bigFive;

  // 데이터에 따라 자동으로 결정될 프로필 정보
  String currentProfileImageUrl;
  String title; // 예: "신중한 리더", "사교적인 아이디어 뱅크"

  PersonalityStatus({
    required this.userId,
    LearyData? leary,
    BigFiveData? bigFive,
    this.currentProfileImageUrl = 'assets/images/profiles/default.png',
    this.title = '분석 대기 중',
  }) : this.leary = leary ?? LearyData(),
        this.bigFive = bigFive ?? BigFiveData();

  // ★ 핵심: 나중에 분석 엔진이 호출할 함수
  // 수치가 변하면 이 함수를 통해 프로필 사진과 칭호가 자동으로 업데이트됩니다.
  void updateStatus({LearyData? newLeary, BigFiveData? newBigFive}) {
    if (newLeary != null) leary = newLeary;
    if (newBigFive != null) bigFive = newBigFive;

    // TODO: 여기에 수치에 따라 이미지와 타이틀을 매칭하는 로직을 작성합니다.
    // 예: if(leary.dominantConforming > 0.5 && bigFive.extraversion > 0.7) ...
    _updateProfileResources();
  }

  void _updateProfileResources() {
    // 임시 로직
    if (leary.dominantConforming > 0.3) {
      title = "주도적인 페르소나";
      currentProfileImageUrl = 'assets/images/profiles/leader.png';
    } else {
      title = "협조적인 페르소나";
      currentProfileImageUrl = 'assets/images/profiles/cooperator.png';
    }
  }
}