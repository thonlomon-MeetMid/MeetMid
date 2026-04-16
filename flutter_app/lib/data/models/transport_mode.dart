enum TransportMode {
  transit,
  car,
  walk,
  bike;

  String get label {
    switch (this) {
      case TransportMode.transit:
        return '대중교통';
      case TransportMode.car:
        return '자동차';
      case TransportMode.walk:
        return '도보';
      case TransportMode.bike:
        return '자전거';
    }
  }

  String get icon {
    switch (this) {
      case TransportMode.transit:
        return 'directions_transit';
      case TransportMode.car:
        return 'directions_car';
      case TransportMode.walk:
        return 'directions_walk';
      case TransportMode.bike:
        return 'directions_bike';
    }
  }
}
