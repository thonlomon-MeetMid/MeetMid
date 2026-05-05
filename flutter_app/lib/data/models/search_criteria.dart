enum SearchCriteria {
  timeFair,
  distanceFair,
  transitFocused;

  String get label {
    switch (this) {
      case SearchCriteria.timeFair:
        return '시간 공평';
      case SearchCriteria.distanceFair:
        return '거리 공평';
      case SearchCriteria.transitFocused:
        return '다수결 중간';
    }
  }

  String get description {
    switch (this) {
      case SearchCriteria.timeFair:
        return '이동시간 편차 최소화';
      case SearchCriteria.distanceFair:
        return '이동거리 균등 지점';
      case SearchCriteria.transitFocused:
        return '인원 가중치 반영';
    }
  }
}
