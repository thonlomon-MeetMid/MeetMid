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
        return '대중 교통 중심';
    }
  }

  String get description {
    switch (this) {
      case SearchCriteria.timeFair:
        return '모든 참여자의 이동 시간이 비슷하도록';
      case SearchCriteria.distanceFair:
        return '모든 참여자의 이동 거리가 비슷하도록';
      case SearchCriteria.transitFocused:
        return '대중교통 접근성을 우선으로';
    }
  }
}
