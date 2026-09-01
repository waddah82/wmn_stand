import 'package:decimal/decimal.dart';

class WmnMoney implements Comparable<WmnMoney> {
  const WmnMoney._(this.value);

  final Decimal value;

  static final WmnMoney zero = WmnMoney._(Decimal.zero);

  factory WmnMoney.parse(String value) => WmnMoney._(Decimal.parse(value));
  factory WmnMoney.fromInt(int value) => WmnMoney._(Decimal.fromInt(value));

  WmnMoney operator +(WmnMoney other) => WmnMoney._(value + other.value);
  WmnMoney operator -(WmnMoney other) => WmnMoney._(value - other.value);
  WmnMoney multiply(Decimal factor) => WmnMoney._(value * factor);

  bool get isNegative => value < Decimal.zero;
  bool get isZero => value == Decimal.zero;

  @override
  int compareTo(WmnMoney other) => value.compareTo(other.value);

  @override
  String toString() => value.toString();
}
